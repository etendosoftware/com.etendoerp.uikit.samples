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
 * Datasource ETOKRS_Checkins: the check-in feed for a cycle, newest first, optionally narrowed to
 * one department. Same access story as {@link ReviewTree} -- the department filter is SQL, not UI.
 *
 * Reached at {@code org.openbravo.client.kernel?action=com.etendoerp.uikit.samples.okr.Checkins}.
 */
public class Checkins extends BaseActionHandler {

  private static final Logger log = LogManager.getLogger();

  /** Newest first, capped so one very chatty quarter cannot stall the window. */
  private static final int MAX_ROWS = 200;

  @Override
  protected JSONObject execute(Map<String, Object> parameters, String content) {
    try {
      final String cycleId = OkrQuery.param(parameters, "cycle");
      final String dept = OkrQuery.param(parameters, "dept");
      final String sql = "select ci.etokrs_checkin_id as id, ci.etokrs_keyresult_id as kr,"
          + " k.name as krtitle, ci.checkindate, ci.author, ci.valuefrom, ci.valueto,"
          + " ci.scorefrom, ci.scoreto, ci.confidence, ci.note, k.uom" + " from etokrs_checkin ci"
          + " join etokrs_keyresult k on k.etokrs_keyresult_id = ci.etokrs_keyresult_id"
          + " join etokrs_objective o on o.etokrs_objective_id = k.etokrs_objective_id" + " where "
          + OkrQuery.scopeClause("ci") + " and k.isactive = 'Y' and o.isactive = 'Y'"
          + (cycleId == null ? "" : " and o.etokrs_cycle_id = ?")
          + (dept == null ? "" : " and o.etokrs_department_id = ?")
          + " order by ci.checkindate desc, ci.created desc limit " + MAX_ROWS;
      final Connection conn = OkrQuery.connection();
      try (PreparedStatement st = conn.prepareStatement(sql)) {
        int i = OkrQuery.bindScope(st, 1);
        if (cycleId != null) {
          st.setString(i++, cycleId);
        }
        if (dept != null) {
          st.setString(i, dept);
        }
        try (ResultSet rs = st.executeQuery()) {
          final JSONArray rows = OkrQuery.rows(rs, OkrQuery.str("id", "id"),
              OkrQuery.str("kr", "kr"), OkrQuery.str("krTitle", "krtitle"),
              OkrQuery.date("date", "checkindate"), OkrQuery.str("author", "author"),
              OkrQuery.num("valueFrom", "valuefrom"), OkrQuery.num("valueTo", "valueto"),
              OkrQuery.num("scoreFrom", "scorefrom"), OkrQuery.num("scoreTo", "scoreto"),
              OkrQuery.str("confidence", "confidence"), OkrQuery.str("note", "note"),
              OkrQuery.str("unit", "uom"));
          return new JSONObject().put("checkins", rows);
        }
      }
    } catch (Exception e) {
      log.error("ETOKRS_Checkins failed: {}", e.getMessage(), e);
      try {
        return new JSONObject().put("error", new JSONObject().put("message", String.valueOf(e)));
      } catch (Exception ignored) {
        return new JSONObject();
      }
    }
  }
}
