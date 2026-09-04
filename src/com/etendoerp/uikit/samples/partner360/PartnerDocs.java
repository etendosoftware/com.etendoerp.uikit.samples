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
 * Datasource {@code docs} of ETDEMO_Partner360: one page of one document kind of one partner.
 *
 * Accepted parameters: {@code bp} (a {@code c_bpartner_id}), {@code tab} (one of the six keys of
 * {@link Partner360#KINDS}), {@code page} (1-based) and {@code limit}.
 *
 * <b>This is the only source that narrows.</b> The directory ignores the partner and the tab, the
 * header ignores the tab; here both matter, and both are applied in SQL. The row set for a tab is
 * therefore disjoint from every other tab's -- the direction column makes it so -- and its size is
 * exactly the count the header already published, which is what makes the counts on the tab strip
 * trustworthy before anything is opened.
 *
 * An unknown or absent {@code tab}, or an absent {@code bp}, answers the neutral shape rather than
 * an error or a scan: no rows, a zero page, {@code meta.tabId} null. The view never asks for it --
 * {@code when: (s) => !!s.bp && s.tab !== 'sum'} -- but the endpoint is public and cannot rely on
 * that.
 */
public class PartnerDocs extends BaseActionHandler {

  private static final Logger log = LogManager.getLogger();

  @Override
  protected JSONObject execute(Map<String, Object> parameters, String content) {
    try {
      final Connection conn = UikQuery.connection();
      final String bp = UikQuery.param(parameters, "bp");
      final String tab = UikQuery.param(parameters, "tab");
      final Kind kind = tab == null ? null : Partner360.KINDS.get(tab);
      final int[] window = UikQuery.page(parameters);
      final JSONObject result = new JSONObject();
      final boolean live = kind != null && bp != null;
      result.put("rows", live ? rows(conn, kind, bp, window[0], window[1]) : new JSONArray());
      result.put("page", Partner360.pageInfo(window[0], window[1],
          live ? total(conn, kind, bp) : 0L));
      result.put("meta", new JSONObject()
          .put("bp", bp == null ? "" : bp)
          .put("tab", kind == null ? "" : kind.key)
          .put("table", kind == null ? "" : kind.table)
          .put("tabId", kind == null ? JSONObject.NULL
              : Partner360.nullSafe(UikQuery.tabFor(conn, kind.window, kind.table)))
          .put("scope", Partner360.scope()));
      return result;
    } catch (Exception e) {
      log.error("ETDEMO_Partner360 docs failed: {}", e.getMessage(), e);
      return Partner360.error(e);
    }
  }

  /**
   * One page of documents, newest first.
   *
   * Each row carries its own currency symbol next to its own amount: two documents of the same
   * partner can be in different currencies, and a column formatted with one guessed symbol would
   * be a reporting bug rather than a rendering one.
   */
  private JSONArray rows(Connection conn, Kind kind, String bp, int limit, int offset)
      throws Exception {
    final String sql = "select d." + kind.idCol() + " as id, d.documentno as docno,"
        + " d." + kind.dateCol + " as dt, d." + kind.amtCol + " as amt,"
        + " coalesce(nullif(cu.cursymbol, ''), cu.iso_code, '') as sym,"
        + " coalesce(cu.iso_code, '') as iso, coalesce(d." + kind.statusCol + ", '') as st,"
        + " coalesce(rl.name, '') as stname"
        + " from " + kind.table + " d"
        + "   left join c_currency cu on cu.c_currency_id = d.c_currency_id"
        + Partner360.statusJoin(kind, "d")
        + Partner360.where(kind, "d")
        + " order by d." + kind.dateCol + " desc, d.documentno desc, d." + kind.idCol() + " desc"
        + " limit ? offset ?";
    try (PreparedStatement st = conn.prepareStatement(sql)) {
      int i = Partner360.bindWhere(st, 1, bp);
      st.setInt(i++, limit);
      st.setInt(i, offset);
      try (ResultSet rs = st.executeQuery()) {
        return UikQuery.rows(rs, UikQuery.str("id", "id"), UikQuery.str("docNo", "docno"),
            UikQuery.date("date", "dt"), UikQuery.num("amount", "amt"),
            UikQuery.str("currency", "sym"), UikQuery.str("iso", "iso"),
            UikQuery.str("status", "st"), UikQuery.str("statusName", "stname"));
      }
    }
  }

  /** The pager's count, over the same partner and the same kind, page excluded. */
  private long total(Connection conn, Kind kind, String bp) throws Exception {
    final String sql = "select count(*) from " + kind.table + " d" + Partner360.where(kind, "d");
    try (PreparedStatement st = conn.prepareStatement(sql)) {
      Partner360.bindWhere(st, 1, bp);
      return Partner360.count(st);
    }
  }
}
