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

import com.etendoerp.uikit.samples.partner360.Partner360.Kind;

/**
 * Datasource {@code head} of ETDEMO_Partner360: one partner's identity and its per-tab totals.
 *
 * Accepted parameters: {@code bp} (a {@code c_bpartner_id}). This source is only fetched while a
 * partner is selected -- the view declares {@code when: (s) => !!s.bp} -- but a datasource cannot
 * trust the client to have honoured that, so a call with no partner, or with a partner outside the
 * readable scope, answers the neutral shape: {@code partner: null}, {@code totals: []}. It never
 * falls back to "every partner", which would be both a wrong screen and a scope leak.
 *
 * <b>The totals ignore the active tab, on purpose.</b> All six counts are computed over all of the
 * partner's readable documents in one union, so the tab strip can show how many sales invoices
 * there are before anyone opens the sales invoices. Deriving those counts from the document list
 * would make each count appear only after its own tab had been visited, which is the opposite of
 * what a file screen is for.
 *
 * An amount is only emitted when the kind has exactly one currency, because a sum across
 * currencies is not money. {@code currencies} carries the count so the view can say so instead of
 * printing a number that means nothing.
 */
public class PartnerHead extends BaseActionHandler {

  private static final Logger log = LogManager.getLogger();

  /** One branch per document kind, all six over the same partner, none of them tab-aware. */
  private static final String TOTALS = totalsSql();

  private static String totalsSql() {
    final StringBuilder sql = new StringBuilder();
    for (Kind kind : Partner360.KINDS.values()) {
      if (sql.length() > 0) {
        sql.append(" union all ");
      }
      sql.append("select '").append(kind.key).append("' as kind, count(*) as n,")
          .append(" coalesce(sum(d.").append(kind.amtCol).append("), 0) as amt,")
          .append(" max(d.").append(kind.dateCol).append(") as lastd,")
          .append(" count(distinct d.c_currency_id) as curs,")
          .append(" min(cu.cursymbol) as sym, min(cu.iso_code) as iso")
          .append(" from ").append(kind.table).append(" d")
          .append(" left join c_currency cu on cu.c_currency_id = d.c_currency_id")
          .append(Partner360.where(kind, "d"));
    }
    return sql.toString();
  }

  @Override
  protected JSONObject execute(Map<String, Object> parameters, String content) {
    try {
      final Connection conn = UikQuery.connection();
      final String bp = UikQuery.param(parameters, "bp");
      final JSONObject result = new JSONObject();
      result.put("meta", new JSONObject()
          .put("bp", bp == null ? "" : bp)
          .put("tabs", Partner360.tabs(conn))
          .put("partnerTab",
              Partner360.nullSafe(UikQuery.tabFor(conn, Partner360.PARTNER_WINDOW, "c_bpartner")))
          .put("scope", Partner360.scope()));
      final JSONObject partner = bp == null ? null : partner(conn, bp);
      result.put("partner", partner == null ? JSONObject.NULL : partner);
      result.put("totals", partner == null ? new JSONArray() : totals(conn, bp));
      return result;
    } catch (Exception e) {
      log.error("ETDEMO_Partner360 head failed: {}", e.getMessage(), e);
      return Partner360.error(e);
    }
  }

  /** The partner itself, or null when the id is unknown or outside the readable scope. */
  private JSONObject partner(Connection conn, String bp) throws Exception {
    final String sql = "select b.c_bpartner_id as id, b.value as code, b.name as name,"
        + " coalesce(b.taxid, '') as taxid, b.iscustomer as cust, b.isvendor as vend,"
        + " coalesce(g.name, '') as grp from c_bpartner b"
        + "   left join c_bp_group g on g.c_bp_group_id = b.c_bp_group_id"
        + " where b.c_bpartner_id = ? and " + UikQuery.scopeClause("b");
    try (PreparedStatement st = conn.prepareStatement(sql)) {
      st.setString(1, bp);
      UikQuery.bindScope(st, 2);
      try (ResultSet rs = st.executeQuery()) {
        final JSONArray found = UikQuery.rows(rs, UikQuery.str("id", "id"),
            UikQuery.str("code", "code"), UikQuery.str("name", "name"),
            UikQuery.str("taxId", "taxid"), UikQuery.str("group", "grp"),
            (r, row) -> row.put("customer", "Y".equals(r.getString("cust"))),
            (r, row) -> row.put("vendor", "Y".equals(r.getString("vend"))));
        return found.length() == 0 ? null : found.getJSONObject(0);
      }
    }
  }

  /**
   * The six totals, in the order the tab strip shows them.
   *
   * The union is read into a map and then emitted by iterating the taxonomy, so the array order is
   * the taxonomy's and not whatever order the planner returned the branches in. A kind with no
   * documents still gets a row -- {@code count: 0} -- because a tab that vanished when it was
   * empty would make the strip jump between partners.
   */
  private JSONArray totals(Connection conn, String bp) throws Exception {
    final JSONObject byKind = new JSONObject();
    try (PreparedStatement st = conn.prepareStatement(TOTALS)) {
      int i = 1;
      for (int branch = 0; branch < Partner360.KINDS.size(); branch++) {
        i = Partner360.bindWhere(st, i, bp);
      }
      try (ResultSet rs = st.executeQuery()) {
        while (rs.next()) {
          final int currencies = rs.getInt("curs");
          final String symbol = rs.getString("sym") == null ? rs.getString("iso")
              : rs.getString("sym");
          final java.sql.Timestamp last = rs.getTimestamp("lastd");
          byKind.put(rs.getString("kind"), new JSONObject()
              .put("count", rs.getLong("n"))
              .put("amount", currencies == 1 ? rs.getBigDecimal("amt").doubleValue()
                  : JSONObject.NULL)
              .put("currencies", currencies)
              .put("currency", symbol == null ? "" : symbol)
              .put("iso", rs.getString("iso") == null ? "" : rs.getString("iso"))
              .put("last", last == null ? JSONObject.NULL
                  : last.toLocalDateTime().toLocalDate().toString()));
        }
      }
    }
    final JSONArray out = new JSONArray();
    for (Kind kind : Partner360.KINDS.values()) {
      final JSONObject row = byKind.has(kind.key) ? byKind.getJSONObject(kind.key)
          : new JSONObject().put("count", 0).put("amount", JSONObject.NULL)
              .put("currencies", 0).put("currency", "").put("iso", "").put("last", JSONObject.NULL);
      out.put(row.put("tab", kind.key));
    }
    return out;
  }
}
