package com.etendoerp.uikit.samples.partner360;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.codehaus.jettison.json.JSONArray;
import org.codehaus.jettison.json.JSONObject;

import com.etendoerp.uikit.server.UikQuery;

/**
 * What the three ETDEMO_Partner360 datasources share: the document taxonomy, the tab resolution
 * and the envelope helpers.
 *
 * The taxonomy is the interesting part. A business partner file mixes three physical tables and
 * two directions, and the direction column is <em>not</em> the same in all three: {@code c_order}
 * and {@code c_invoice} discriminate with {@code issotrx}, while {@code fin_payment} uses
 * {@code isreceipt}. Six kinds come out of that, and each one belongs to a different standard
 * window -- so each one resolves its own tab through {@link UikQuery#tabFor}, per kind, in SQL.
 * A single "document tab" constant would open "Return to vendor" for a sales order.
 *
 * Nothing here is user input: the table, column, direction and window of a kind are constants
 * reached by a whitelist key, so they can be concatenated into SQL while the partner id, the page
 * and the search text stay bound parameters.
 */
final class Partner360 {

  /** Core's Business Partner window. The tab inside it is still resolved from the dictionary. */
  static final String PARTNER_WINDOW = "123";

  /** One document kind: where it lives, how it is dated and amounted, and which window owns it. */
  static final class Kind {
    final String key;
    final String table;
    final String dateCol;
    final String amtCol;
    final String statusCol;
    final String dirCol;
    final String dirVal;
    final String window;

    private Kind(String key, String table, String dateCol, String amtCol, String statusCol,
        String dirCol, String dirVal, String window) {
      this.key = key;
      this.table = table;
      this.dateCol = dateCol;
      this.amtCol = amtCol;
      this.statusCol = statusCol;
      this.dirCol = dirCol;
      this.dirVal = dirVal;
      this.window = window;
    }

    /** Every one of the three tables names its primary key after itself. */
    String idCol() {
      return table + "_id";
    }
  }

  /**
   * The six kinds, in the order the tab strip shows them. Sales before purchase, and documents
   * before money, which is the order a partner file is read in.
   */
  static final Map<String, Kind> KINDS = kinds();

  private Partner360() {
  }

  private static Map<String, Kind> kinds() {
    final Map<String, Kind> out = new LinkedHashMap<>();
    put(out, new Kind("so", "c_order", "dateordered", "grandtotal", "docstatus", "issotrx", "Y",
        "143"));
    put(out, new Kind("po", "c_order", "dateordered", "grandtotal", "docstatus", "issotrx", "N",
        "181"));
    put(out, new Kind("si", "c_invoice", "dateinvoiced", "grandtotal", "docstatus", "issotrx", "Y",
        "167"));
    put(out, new Kind("pi", "c_invoice", "dateinvoiced", "grandtotal", "docstatus", "issotrx", "N",
        "183"));
    put(out, new Kind("rc", "fin_payment", "paymentdate", "amount", "status", "isreceipt", "Y",
        "E547CE89D4C04429B6340FFA44E70716"));
    put(out, new Kind("pm", "fin_payment", "paymentdate", "amount", "status", "isreceipt", "N",
        "6F8F913FA60F4CBD93DC1D3AA696E76E"));
    return out;
  }

  private static void put(Map<String, Kind> out, Kind kind) {
    out.put(kind.key, kind);
  }

  /**
   * The tab id of every kind, resolved per document type in this request.
   *
   * @param conn
   *          the connection to read the dictionary on
   * @return kind key to tab id, with JSON null for a kind whose window has no active tab
   * @throws Exception
   *           if the dictionary query fails
   */
  static JSONObject tabs(Connection conn) throws Exception {
    final JSONObject out = new JSONObject();
    for (Kind kind : KINDS.values()) {
      out.put(kind.key, nullSafe(UikQuery.tabFor(conn, kind.window, kind.table)));
    }
    return out;
  }

  /**
   * The readable scope of this session, published so an independent check can rebuild the
   * handler's row set instead of guessing at it.
   *
   * @return {@code { clients: [...], orgs: [...] }}
   * @throws Exception
   *           if the JSON assembly fails
   */
  static JSONObject scope() throws Exception {
    return new JSONObject()
        .put("clients", new JSONArray(List.of(UikQuery.readableClients())))
        .put("orgs", new JSONArray(List.of(UikQuery.readableOrgs())));
  }

  /**
   * The status name from the dictionary, joined on the reference the column itself declares.
   *
   * Read out of {@code AD_COLUMN} rather than from a reference id in source: a reference id is
   * dictionary data like a tab id, and {@code CO} means "Complete", "Booked" or "Completed"
   * depending on which of the nine references holding that value is meant.
   *
   * @param kind
   *          the document kind whose status column is being named
   * @param alias
   *          the alias the caller gave the document table
   * @return a left join that exposes {@code rl.name}
   */
  static String statusJoin(Kind kind, String alias) {
    return " left join ad_ref_list rl on rl.value = " + alias + "." + kind.statusCol
        + " and rl.isactive = 'Y' and rl.ad_reference_id = (select c.ad_reference_value_id"
        + "   from ad_column c join ad_table t on t.ad_table_id = c.ad_table_id"
        + "   where upper(t.tablename) = upper('" + kind.table + "')"
        + "     and upper(c.columnname) = upper('" + kind.statusCol + "'))";
  }

  /** The scoped, directional predicate of one kind over {@code alias}, bound as bp then scope. */
  static String where(Kind kind, String alias) {
    return " where " + alias + ".c_bpartner_id = ? and " + alias + "." + kind.dirCol + " = '"
        + kind.dirVal + "' and " + UikQuery.scopeClause(alias);
  }

  /** Binds {@link #where(Kind, String)}: the partner id, then the readable scope. */
  static int bindWhere(PreparedStatement st, int from, String partner) throws Exception {
    st.setString(from, partner);
    return UikQuery.bindScope(st, from + 1);
  }

  /** The pager envelope, so the three sources cannot describe a page differently. */
  static JSONObject pageInfo(int limit, int offset, long total) throws Exception {
    return new JSONObject()
        .put("limit", limit)
        .put("offset", offset)
        .put("page", (offset / limit) + 1)
        .put("total", total)
        .put("pages", Math.max(1, (total + limit - 1) / limit));
  }

  /** Runs a bound count and returns it; the caller owns the binds because it owns the scope. */
  static long count(PreparedStatement st) throws Exception {
    try (ResultSet rs = st.executeQuery()) {
      return rs.next() ? rs.getLong(1) : 0L;
    }
  }

  /** JSON null rather than the string "null", which is what a missing tab renders as otherwise. */
  static Object nullSafe(String value) {
    return value == null ? JSONObject.NULL : value;
  }

  /**
   * The error envelope every uikit datasource answers with: a 200 carrying {@code error.message},
   * which {@code OB.UIKit.fetch} turns into an Error instead of into data a view might render.
   *
   * @param e
   *          the failure
   * @return the envelope, or an empty object if even that could not be built
   */
  static JSONObject error(Exception e) {
    try {
      return new JSONObject().put("error",
          new JSONObject().put("message", e.getMessage() == null ? e.toString() : e.getMessage()));
    } catch (Exception ignored) {
      return new JSONObject();
    }
  }
}
