package com.etendoerp.uikit.samples.partner360;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.Map;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.codehaus.jettison.json.JSONArray;
import org.codehaus.jettison.json.JSONObject;
import org.openbravo.client.kernel.BaseActionHandler;

import com.etendoerp.uikit.server.UikQuery;

/**
 * Datasource {@code list} of ETDEMO_Partner360: the searchable, paged partner directory.
 *
 * Reached at {@code org.openbravo.client.kernel?_action=} plus this class's fully qualified name.
 * KernelServlet resolves an action handler by class name and only gates portal roles, so no AD row
 * publishes this endpoint.
 *
 * Accepted parameters: {@code q} (free text over code, name and tax id), {@code page} (1-based)
 * and {@code limit}. The {@code ilike}, the ordering and the {@code limit}/{@code offset} are all
 * SQL, and the total is its own {@code count(*)} over the same CTE, so the pager cannot disagree
 * with the page.
 *
 * <b>This source is the constant half of the window.</b> It never receives the selected partner or
 * the active tab and could not use them: a directory that re-queried itself every time the user
 * opened a payments tab would be the exact bug the runtime's lazy aliases exist to prevent. The
 * document count per partner is over every readable document of every kind, which is why the
 * directory can be read before anything is selected.
 */
public class Directory extends BaseActionHandler {

  private static final Logger log = LogManager.getLogger();

  /**
   * doc = every readable document of the three tables, reduced to its partner; cnt = one row per
   * partner; part = the filtered directory. The page query and the count query share the CTEs, so
   * the pager total is the same set the page came out of.
   *
   * Bind order: scope(o), scope(i), scope(p), scope(b), then the like marker and its three
   * patterns.
   */
  private static final String BASE = "with doc as ("
      + " select o.c_bpartner_id as bp from c_order o where " + UikQuery.scopeClause("o")
      + " union all select i.c_bpartner_id from c_invoice i where " + UikQuery.scopeClause("i")
      + " union all select p.c_bpartner_id from fin_payment p where " + UikQuery.scopeClause("p")
      + "), cnt as (select bp, count(*) as n from doc group by bp), part as ("
      + " select b.c_bpartner_id as id, b.value as code, b.name as name,"
      + "        coalesce(b.taxid, '') as taxid, b.iscustomer as cust, b.isvendor as vend,"
      + "        coalesce(g.name, '') as grp, coalesce(c.n, 0) as docs"
      + " from c_bpartner b"
      + "   left join c_bp_group g on g.c_bp_group_id = b.c_bp_group_id"
      + "   left join cnt c on c.bp = b.c_bpartner_id"
      + " where " + UikQuery.scopeClause("b") + " and "
      + UikQuery.likeClause("b.value", "b.name", "b.taxid") + ")";

  @Override
  protected JSONObject execute(Map<String, Object> parameters, String content) {
    try {
      final Connection conn = UikQuery.connection();
      final String q = UikQuery.param(parameters, "q");
      final int[] window = UikQuery.page(parameters);
      final JSONObject result = new JSONObject();
      result.put("rows", rows(conn, q, window[0], window[1]));
      result.put("page", Partner360.pageInfo(window[0], window[1], total(conn, q)));
      result.put("meta", new JSONObject()
          .put("q", q == null ? "" : q)
          .put("partnerTab",
              Partner360.nullSafe(UikQuery.tabFor(conn, Partner360.PARTNER_WINDOW, "c_bpartner")))
          .put("scope", Partner360.scope()));
      return result;
    } catch (Exception e) {
      log.error("ETDEMO_Partner360 list failed: {}", e.getMessage(), e);
      return Partner360.error(e);
    }
  }

  /** Binds what {@link #BASE} needs, in the order the SQL text mentions it. */
  private int bindBase(PreparedStatement st, String q) throws Exception {
    int i = UikQuery.bindScope(st, 1);
    i = UikQuery.bindScope(st, i);
    i = UikQuery.bindScope(st, i);
    i = UikQuery.bindScope(st, i);
    return UikQuery.bindLike(st, i, q, 3);
  }

  /**
   * One page of the directory, busiest partner first.
   *
   * The ordering is by document count rather than by name because that is the question the screen
   * answers -- who this instance actually trades with -- and because a directory sorted by name
   * puts the six partners that carry the data behind twenty that carry none.
   */
  private JSONArray rows(Connection conn, String q, int limit, int offset) throws Exception {
    final String sql = BASE + " select id, code, name, taxid, cust, vend, grp, docs from part"
        + " order by docs desc, name, id limit ? offset ?";
    try (PreparedStatement st = conn.prepareStatement(sql)) {
      int i = bindBase(st, q);
      st.setInt(i++, limit);
      st.setInt(i, offset);
      try (ResultSet rs = st.executeQuery()) {
        return UikQuery.rows(rs, UikQuery.str("id", "id"), UikQuery.str("code", "code"),
            UikQuery.str("name", "name"), UikQuery.str("taxId", "taxid"),
            UikQuery.str("group", "grp"), UikQuery.num("docs", "docs"),
            flag("customer", "cust"), flag("vendor", "vend"));
      }
    }
  }

  /** The pager's own count over the same filtered set, page and limit excluded. */
  private long total(Connection conn, String q) throws Exception {
    try (PreparedStatement st = conn.prepareStatement(BASE + " select count(*) from part")) {
      bindBase(st, q);
      return Partner360.count(st);
    }
  }

  /** A {@code Y}/{@code N} column as a JSON boolean: the client tests it, it does not parse it. */
  private static UikQuery.Col flag(String key, String column) {
    return (rs, row) -> row.put(key, "Y".equals(rs.getString(column)));
  }
}
