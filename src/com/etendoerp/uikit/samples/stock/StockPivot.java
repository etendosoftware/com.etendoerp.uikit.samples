package com.etendoerp.uikit.samples.stock;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.codehaus.jettison.json.JSONArray;
import org.codehaus.jettison.json.JSONObject;
import org.openbravo.client.kernel.BaseActionHandler;

import com.etendoerp.uikit.server.UikQuery;

/**
 * Datasource ETDEMO_Stock: quantity on hand pivoted as products (rows) by warehouses (columns).
 *
 * Reached at {@code org.openbravo.client.kernel?action=} plus this class's fully qualified
 * name.
 * KernelServlet resolves an action handler by class name and only gates portal roles, so no AD row
 * publishes this endpoint.
 *
 * Accepted parameters: {@code q} (free text over product code and name), {@code page} (1-based),
 * {@code limit} (page size), {@code zeros} ({@code Y} keeps products whose total is zero) and
 * {@code sort} ({@code code}, {@code name} or {@code qty}). Search, ordering and paging are all
 * SQL: the client never receives a row it is not showing, so the window behaves the same on 255
 * rows and on 255 million.
 *
 * The asymmetry this datasource exists to demonstrate: the warehouse axis and the column totals
 * are computed ignoring part of the filter, and the detail is not.
 *
 * <ul>
 * <li>{@code warehouses} ignores {@code q}, {@code page}, {@code limit}, {@code zeros} and
 * {@code sort} entirely. A column that appeared and vanished between keystrokes would make the
 * pivot unreadable and its numbers untrustworthy.</li>
 * <li>{@code colTotals} honours {@code q} and {@code zeros} -- they choose which products the
 * pivot is about -- and ignores {@code page} and {@code limit}, so a column total is over the
 * whole filtered set and not over the visible page. The view says so on screen.</li>
 * <li>{@code rows} honours everything.</li>
 * </ul>
 *
 * Everything is scoped with {@link UikQuery#scopeClause(String)}, on the storage row and on the
 * warehouse, because fact F6 records that {@code ViewComponent} serves a view without consulting
 * {@code OBUIAPP_View_Role_Access}: a client-side filter here would be decoration, not security.
 */
public class StockPivot extends BaseActionHandler {

  private static final Logger log = LogManager.getLogger();

  /**
   * Core's Product window. The <em>tab</em> is never hardcoded -- {@link UikQuery#tabFor} resolves
   * it from the dictionary and the client only ever sees what that returned -- but tabFor needs a
   * window to look inside, and this one id is core dictionary data that predates the instance.
   * A miss returns null and the row renders as plain text instead of a dead link.
   */
  private static final String PRODUCT_WINDOW = "140";

  /** Whitelisted orderings. User input never reaches the ORDER BY, only one of these keys does. */
  private static final Map<String, String> ORDER = Map.of(
      "code", "code asc, id asc",
      "name", "name asc, id asc",
      "qty", "total desc, id asc");

  /**
   * det = every readable storage row with its warehouse; prod = one row per product with its
   * total, already narrowed by the search box and by the zero-total switch. Both are shared by the
   * page query, the count query and the column-total query, so the three cannot disagree.
   *
   * Bind order, and it is the same for every query built on this: scope(sd), scope(w), the like
   * marker plus one pattern per searched column, then the zeros flag.
   */
  private static final String BASE = "with det as ("
      + " select sd.m_product_id as prod, l.m_warehouse_id as wh, sd.qtyonhand as qty"
      + " from m_storage_detail sd"
      + "   join m_locator l on l.m_locator_id = sd.m_locator_id"
      + "   join m_warehouse w on w.m_warehouse_id = l.m_warehouse_id"
      + " where " + UikQuery.scopeClause("sd") + " and " + UikQuery.scopeClause("w")
      + "), prod as ("
      + " select d.prod as id, p.value as code, p.name as name,"
      + "        coalesce(nullif(trim(u.uomsymbol), ''), u.name, '') as uom,"
      + "        sum(d.qty) as total"
      + " from det d"
      + "   join m_product p on p.m_product_id = d.prod"
      + "   left join c_uom u on u.c_uom_id = p.c_uom_id"
      + " where " + UikQuery.likeClause("p.value", "p.name")
      + " group by d.prod, p.value, p.name, u.uomsymbol, u.name"
      + " having ?::text = 'Y' or sum(d.qty) <> 0"
      + ")";

  @Override
  protected JSONObject execute(Map<String, Object> parameters, String content) {
    try {
      final Connection conn = UikQuery.connection();
      final String q = UikQuery.param(parameters, "q");
      final String zeros = "Y".equals(UikQuery.param(parameters, "zeros")) ? "Y" : "N";
      final String sortKey = ORDER.containsKey(UikQuery.param(parameters, "sort"))
          ? UikQuery.param(parameters, "sort")
          : "code";
      final int[] window = UikQuery.page(parameters);

      final JSONObject result = new JSONObject();
      result.put("warehouses", warehouses(conn));
      final JSONArray rows = rows(conn, q, zeros, sortKey, window[0], window[1]);
      cells(conn, rows);
      result.put("rows", rows);
      result.put("colTotals", colTotals(conn, q, zeros));
      final JSONObject summary = summary(conn, q, zeros);
      result.put("summary", summary);
      final long total = (long) summary.getDouble("products");
      result.put("page", new JSONObject()
          .put("limit", window[0])
          .put("offset", window[1])
          .put("page", (window[1] / window[0]) + 1)
          .put("total", total)
          .put("pages", Math.max(1, (total + window[0] - 1) / window[0])));
      result.put("meta", new JSONObject()
          .put("productTab", nullSafe(UikQuery.tabFor(conn, PRODUCT_WINDOW, "m_product")))
          .put("sort", sortKey)
          .put("q", q == null ? "" : q)
          .put("zeros", zeros)
          .put("scope", new JSONObject()
              .put("clients", new JSONArray(List.of(UikQuery.readableClients())))
              .put("orgs", new JSONArray(List.of(UikQuery.readableOrgs())))));
      return result;
    } catch (Exception e) {
      log.error("ETDEMO_Stock failed: {}", e.getMessage(), e);
      return error(e);
    }
  }

  private Object nullSafe(String value) {
    return value == null ? JSONObject.NULL : value;
  }

  private JSONObject error(Exception e) {
    try {
      return new JSONObject().put("error",
          new JSONObject().put("message", e.getMessage() == null ? e.toString() : e.getMessage()));
    } catch (Exception ignored) {
      return new JSONObject();
    }
  }

  /** Binds what {@link #BASE} needs, in the order the SQL text mentions it. */
  private int bindBase(PreparedStatement st, int from, String q, String zeros) throws Exception {
    int i = UikQuery.bindScope(st, from);
    i = UikQuery.bindScope(st, i);
    i = UikQuery.bindLike(st, i, q, 2);
    st.setString(i++, zeros);
    return i;
  }

  /**
   * The column axis: every readable warehouse that holds any readable storage row at all.
   *
   * Deliberately built without the search box, the page or the zero switch. The axis is the shape
   * of the pivot, not a result of the query the user is currently typing.
   */
  private JSONArray warehouses(Connection conn) throws Exception {
    final String sql = "select w.m_warehouse_id as id, w.value as code, w.name"
        + " from m_warehouse w where " + UikQuery.scopeClause("w")
        + " and exists (select 1 from m_storage_detail sd"
        + "   join m_locator l on l.m_locator_id = sd.m_locator_id"
        + "   where l.m_warehouse_id = w.m_warehouse_id and " + UikQuery.scopeClause("sd") + ")"
        + " order by w.name";
    try (PreparedStatement st = conn.prepareStatement(sql)) {
      UikQuery.bindScope(st, UikQuery.bindScope(st, 1));
      try (ResultSet rs = st.executeQuery()) {
        return UikQuery.rows(rs, UikQuery.str("id", "id"), UikQuery.str("code", "code"),
            UikQuery.str("name", "name"));
      }
    }
  }

  /** One page of products: the ilike, the ordering and the limit/offset are all in SQL. */
  private JSONArray rows(Connection conn, String q, String zeros, String sortKey, int limit,
      int offset) throws Exception {
    final String sql = BASE + " select id, code, name, uom, total from prod order by "
        + ORDER.get(sortKey) + " limit ? offset ?";
    try (PreparedStatement st = conn.prepareStatement(sql)) {
      int i = bindBase(st, 1, q, zeros);
      st.setInt(i++, limit);
      st.setInt(i, offset);
      try (ResultSet rs = st.executeQuery()) {
        return UikQuery.rows(rs, UikQuery.str("id", "id"), UikQuery.str("code", "code"),
            UikQuery.str("name", "name"), UikQuery.str("uom", "uom"),
            UikQuery.num("total", "total"));
      }
    }
  }

  /**
   * The cells of the page, and only of the page: one query over the products the page query
   * returned, so the payload grows with the page size and not with the table.
   */
  private void cells(Connection conn, JSONArray rows) throws Exception {
    if (rows.length() == 0) {
      return;
    }
    final List<String> ids = new ArrayList<>();
    for (int r = 0; r < rows.length(); r++) {
      ids.add(rows.getJSONObject(r).getString("id"));
      rows.getJSONObject(r).put("cells", new JSONObject());
    }
    final String sql = "select sd.m_product_id as prod, l.m_warehouse_id as wh,"
        + " sum(sd.qtyonhand) as qty from m_storage_detail sd"
        + "   join m_locator l on l.m_locator_id = sd.m_locator_id"
        + "   join m_warehouse w on w.m_warehouse_id = l.m_warehouse_id"
        + " where " + UikQuery.scopeClause("sd") + " and " + UikQuery.scopeClause("w")
        + " and sd.m_product_id in (" + UikQuery.marks(ids.size()) + ")"
        + " group by sd.m_product_id, l.m_warehouse_id";
    try (PreparedStatement st = conn.prepareStatement(sql)) {
      int i = UikQuery.bindScope(st, UikQuery.bindScope(st, 1));
      for (String id : ids) {
        st.setString(i++, id);
      }
      try (ResultSet rs = st.executeQuery()) {
        while (rs.next()) {
          final int at = ids.indexOf(rs.getString("prod"));
          if (at >= 0) {
            rows.getJSONObject(at).getJSONObject("cells")
                .put(rs.getString("wh"), rs.getBigDecimal("qty").doubleValue());
          }
        }
      }
    }
  }

  /**
   * Column totals over the whole filtered set, page ignored. Summing the visible page instead
   * would print a different number for the same filter on every page, which is the classic pivot
   * lie -- so it is computed here and labelled on screen.
   */
  private JSONArray colTotals(Connection conn, String q, String zeros) throws Exception {
    final String sql = BASE + " select d.wh as id, sum(d.qty) as total from det d"
        + " join prod pr on pr.id = d.prod group by d.wh";
    try (PreparedStatement st = conn.prepareStatement(sql)) {
      bindBase(st, 1, q, zeros);
      try (ResultSet rs = st.executeQuery()) {
        return UikQuery.rows(rs, UikQuery.str("id", "id"), UikQuery.num("total", "total"));
      }
    }
  }

  /** Distinct products matching the filter, and their grand total. Also the pager's count. */
  private JSONObject summary(Connection conn, String q, String zeros) throws Exception {
    final String sql = BASE
        + " select count(*) as products, coalesce(sum(total), 0) as grand from prod";
    try (PreparedStatement st = conn.prepareStatement(sql)) {
      bindBase(st, 1, q, zeros);
      try (ResultSet rs = st.executeQuery()) {
        final JSONArray one = UikQuery.rows(rs, UikQuery.num("products", "products"),
            UikQuery.num("grand", "grand"));
        return one.length() == 0
            ? new JSONObject().put("products", 0).put("grand", 0)
            : one.getJSONObject(0);
      }
    }
  }
}
