package com.etendoerp.uikit.samples.okr;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.Map;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.codehaus.jettison.json.JSONArray;
import org.codehaus.jettison.json.JSONObject;
import org.openbravo.client.kernel.BaseActionHandler;

/**
 * Datasource ETOKRS_ReviewTree: everything the OKR review window needs for one quarter, in one
 * call -- the cycle list, the selected cycle with its elapsed day, the departments that actually
 * have objectives in it, those objectives, and their key results.
 *
 * Reached at {@code org.openbravo.client.kernel?action=com.etendoerp.uikit.samples.okr.ReviewTree}.
 * KernelServlet resolves an action handler by class name and only gates portal roles, so no AD row
 * is needed to publish this endpoint.
 *
 * Accepted parameters: {@code cycle} (an ETOKRS_Cycle id, defaults to the cycle containing today)
 * and {@code dept} (an ETOKRS_Department id, absent or "all" for every readable department). The
 * department filter is applied here in SQL, never in the client.
 */
public class ReviewTree extends BaseActionHandler {

  private static final Logger log = LogManager.getLogger();

  @Override
  protected JSONObject execute(Map<String, Object> parameters, String content) {
    try {
      final JSONObject result = new JSONObject();
      final Connection conn = OkrQuery.connection();
      result.put("cycles", cycles(conn));
      final JSONObject cycle = pickCycle(conn, OkrQuery.param(parameters, "cycle"));
      if (cycle == null) {
        result.put("cycle", JSONObject.NULL);
        result.put("depts", new JSONArray());
        result.put("objs", new JSONArray());
        result.put("krs", new JSONArray());
        return result;
      }
      result.put("cycle", cycle);
      final String cycleId = cycle.getString("id");
      final String dept = OkrQuery.param(parameters, "dept");
      result.put("depts", depts(conn, cycleId));
      result.put("deptStats", deptStats(conn, cycleId));
      result.put("objs", objs(conn, cycleId, dept));
      result.put("krs", krs(conn, cycleId, dept));
      return result;
    } catch (Exception e) {
      log.error("ETOKRS_ReviewTree failed: {}", e.getMessage(), e);
      return error(e);
    }
  }

  private JSONObject error(Exception e) {
    try {
      return new JSONObject().put("error",
          new JSONObject().put("message", e.getMessage() == null ? e.toString() : e.getMessage()));
    } catch (Exception ignored) {
      return new JSONObject();
    }
  }

  /** Every readable cycle, flagged with whether it carries objectives at all. */
  private JSONArray cycles(Connection conn) throws Exception {
    final String sql = "select c.etokrs_cycle_id as id, c.name, c.datefrom, c.dateto,"
        + " case when exists (select 1 from etokrs_objective o"
        + "   where o.etokrs_cycle_id = c.etokrs_cycle_id and o.isactive = 'Y')"
        + " then 'Y' else 'N' end as hasdata" + " from etokrs_cycle c where "
        + OkrQuery.scopeClause("c") + " order by c.datefrom";
    try (PreparedStatement st = conn.prepareStatement(sql)) {
      OkrQuery.bindScope(st, 1);
      try (ResultSet rs = st.executeQuery()) {
        return OkrQuery.rows(rs, OkrQuery.str("id", "id"), OkrQuery.str("name", "name"),
            OkrQuery.date("datefrom", "datefrom"), OkrQuery.date("dateto", "dateto"),
            (r, row) -> row.put("hasData", "Y".equals(r.getString("hasdata"))));
      }
    }
  }

  /**
   * The requested cycle, or the one containing today, or -- outside every cycle -- the most recent
   * one that started. {@code day} counts elapsed days inclusive and is clamped to the cycle, so a
   * finished quarter reads 92/92 and a future one 0/92.
   */
  private JSONObject pickCycle(Connection conn, String requested) throws Exception {
    final String sql = "select c.etokrs_cycle_id as id, c.name, c.datefrom, c.dateto,"
        + " (c.dateto::date - c.datefrom::date) + 1 as days,"
        + " greatest(0, least((c.dateto::date - c.datefrom::date) + 1,"
        + "   (current_date - c.datefrom::date) + 1)) as day"
        + " from etokrs_cycle c where " + OkrQuery.scopeClause("c")
        + (requested == null ? "" : " and c.etokrs_cycle_id = ?")
        + " order by case when current_date between c.datefrom::date and c.dateto::date then 0"
        + "   when current_date > c.dateto::date then 1 else 2 end, c.datefrom desc limit 1";
    try (PreparedStatement st = conn.prepareStatement(sql)) {
      final int next = OkrQuery.bindScope(st, 1);
      if (requested != null) {
        st.setString(next, requested);
      }
      try (ResultSet rs = st.executeQuery()) {
        final JSONArray found = OkrQuery.rows(rs, OkrQuery.str("id", "id"),
            OkrQuery.str("name", "name"), OkrQuery.date("datefrom", "datefrom"),
            OkrQuery.date("dateto", "dateto"), OkrQuery.num("days", "days"),
            OkrQuery.num("day", "day"));
        return found.length() == 0 ? null : found.getJSONObject(0);
      }
    }
  }

  /** Departments with at least one objective in the cycle, so the filter never offers a dead chip. */
  private JSONArray depts(Connection conn, String cycleId) throws Exception {
    final String sql = "select d.etokrs_department_id as id, d.name, d.lead"
        + " from etokrs_department d where " + OkrQuery.scopeClause("d")
        + " and exists (select 1 from etokrs_objective o"
        + "   where o.etokrs_department_id = d.etokrs_department_id"
        + "   and o.etokrs_cycle_id = ? and o.isactive = 'Y')" + " order by d.seqno, d.name";
    try (PreparedStatement st = conn.prepareStatement(sql)) {
      st.setString(OkrQuery.bindScope(st, 1), cycleId);
      try (ResultSet rs = st.executeQuery()) {
        return OkrQuery.rows(rs, OkrQuery.str("id", "id"), OkrQuery.str("name", "name"),
            OkrQuery.str("lead", "lead"));
      }
    }
  }

  /**
   * The two-level weighted rollup per department: key results roll into their objective by KR
   * weight, objectives roll into the department by objective weight.
   *
   * This is computed here, for every readable department, and not derived in the client from the
   * rows above -- those rows are narrowed by the department filter, and the rail has to keep
   * showing the departments the user is not looking at. Section 5 of docs/samples/okr-review.md
   * is the authoritative definition; this SQL is the same arithmetic, in the same order.
   */
  private JSONArray deptStats(Connection conn, String cycleId) throws Exception {
    final String sql = "with kr as ("
        + "  select o.etokrs_department_id as dept, k.etokrs_objective_id as obj,"
        + "         o.weight as owgt, k.weight as kwgt,"
        + "         least(1, greatest(0, (k.currentvalue - k.basevalue)"
        + "                             / (k.targetvalue - k.basevalue))) as frac,"
        + "         k.score, k.scoretarget" + "  from etokrs_keyresult k"
        + "  join etokrs_objective o on o.etokrs_objective_id = k.etokrs_objective_id"
        + "  where " + OkrQuery.scopeClause("k")
        + "    and o.isactive = 'Y' and o.etokrs_cycle_id = ?" + "), obj as ("
        + "  select dept, obj, max(owgt) as owgt, count(*) as krs,"
        + "         sum(frac * kwgt) / sum(kwgt) as frac,"
        + "         sum(score * kwgt) / sum(kwgt) as score,"
        + "         sum(scoretarget * kwgt) / sum(kwgt) as scoretarget"
        + "  from kr group by dept, obj" + ")"
        + " select dept as id, count(*) as objs, sum(krs) as krs,"
        + "        100 * sum(frac * owgt) / sum(owgt) as pct,"
        + "        sum(score * owgt) / sum(owgt) as score,"
        + "        sum(scoretarget * owgt) / sum(owgt) as scoretarget"
        + " from obj group by dept";
    try (PreparedStatement st = conn.prepareStatement(sql)) {
      st.setString(OkrQuery.bindScope(st, 1), cycleId);
      try (ResultSet rs = st.executeQuery()) {
        return OkrQuery.rows(rs, OkrQuery.str("id", "id"), OkrQuery.num("objs", "objs"),
            OkrQuery.num("krs", "krs"), OkrQuery.num("pct", "pct"), OkrQuery.num("score", "score"),
            OkrQuery.num("scoreTarget", "scoretarget"));
      }
    }
  }

  private JSONArray objs(Connection conn, String cycleId, String dept) throws Exception {
    final String sql = "select o.etokrs_objective_id as id, o.etokrs_department_id as dept,"
        + " o.name, o.owner, o.weight, o.scoretarget" + " from etokrs_objective o where "
        + OkrQuery.scopeClause("o") + " and o.etokrs_cycle_id = ?"
        + (dept == null ? "" : " and o.etokrs_department_id = ?") + " order by o.seqno, o.name";
    try (PreparedStatement st = conn.prepareStatement(sql)) {
      int i = OkrQuery.bindScope(st, 1);
      st.setString(i++, cycleId);
      if (dept != null) {
        st.setString(i, dept);
      }
      try (ResultSet rs = st.executeQuery()) {
        return OkrQuery.rows(rs, OkrQuery.str("id", "id"), OkrQuery.str("dept", "dept"),
            OkrQuery.str("title", "name"), OkrQuery.str("owner", "owner"),
            OkrQuery.num("weight", "weight"), OkrQuery.num("scoreTarget", "scoretarget"));
      }
    }
  }

  private JSONArray krs(Connection conn, String cycleId, String dept) throws Exception {
    final String sql = "select k.etokrs_keyresult_id as id, k.etokrs_objective_id as obj,"
        + " k.name, k.owner, k.uom, k.basevalue, k.targetvalue, k.currentvalue,"
        + " k.score, k.scoretarget, k.weight, k.confidence" + " from etokrs_keyresult k"
        + " join etokrs_objective o on o.etokrs_objective_id = k.etokrs_objective_id" + " where "
        + OkrQuery.scopeClause("k") + " and o.isactive = 'Y' and o.etokrs_cycle_id = ?"
        + (dept == null ? "" : " and o.etokrs_department_id = ?")
        + " order by o.seqno, k.seqno, k.name";
    try (PreparedStatement st = conn.prepareStatement(sql)) {
      int i = OkrQuery.bindScope(st, 1);
      st.setString(i++, cycleId);
      if (dept != null) {
        st.setString(i, dept);
      }
      try (ResultSet rs = st.executeQuery()) {
        return OkrQuery.rows(rs, OkrQuery.str("id", "id"), OkrQuery.str("obj", "obj"),
            OkrQuery.str("title", "name"), OkrQuery.str("owner", "owner"),
            OkrQuery.str("unit", "uom"), OkrQuery.num("base", "basevalue"),
            OkrQuery.num("target", "targetvalue"), OkrQuery.num("current", "currentvalue"),
            OkrQuery.num("score", "score"), OkrQuery.num("scoreTarget", "scoretarget"),
            OkrQuery.num("weight", "weight"), OkrQuery.str("confidence", "confidence"));
      }
    }
  }
}
