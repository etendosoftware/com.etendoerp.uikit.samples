package com.etendoerp.uikit.samples.picking;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.codehaus.jettison.json.JSONArray;
import org.codehaus.jettison.json.JSONObject;
import org.openbravo.client.kernel.BaseActionHandler;
import org.openbravo.dal.core.OBContext;

import com.etendoerp.uikit.server.UikQuery;

/**
 * Datasource ETDEMO_Picking: sales orders to prepare, their lines, and what stock backs them.
 *
 * Reached at {@code org.openbravo.client.kernel?_action=} plus this class's fully qualified name.
 * KernelServlet resolves an action handler by class name, so no dictionary row publishes it.
 *
 * Accepted parameters: {@code status} (one of {@link #STATUSES}, anything else means no filter),
 * {@code q} (free text over document number and customer name), {@code order} (the selected
 * {@code c_order_id}), {@code page} / {@code limit}, and {@code asOf}.
 *
 * The asymmetry this datasource exists to demonstrate:
 *
 * <ul>
 * <li>{@code statuses} ignores every filter and every selection. It is the navigation rail, and a
 * count that moved when the reader clicked an order could not answer "how many are still drafts",
 * which is the only question a preparation screen exists to answer.</li>
 * <li>{@code orders} honours {@code status}, {@code q} and the page window.</li>
 * <li>{@code order} and {@code lines} exist only for the selected id, and only when that id comes
 * back from {@link #VIS}. An id outside scope is answered exactly like an id that never existed:
 * both produce a null header and no lines. Fact F6 -- the window granted the caller nothing, so
 * this query is the whole access decision.</li>
 * </ul>
 *
 * {@link #VIS}, {@link #FROM}, {@link #TRANSITIONS} and {@link #NEXT} are shared with
 * {@link ConfirmOrder} on purpose: the write re-reads its target through the same predicate the
 * read used, and offers exactly the transition this screen advertised. Two copies would drift
 * into a window that offers a button the server refuses, or worse, one it accepts on a row the
 * window would never have shown.
 */
public class PickList extends BaseActionHandler {

  private static final Logger log = LogManager.getLogger();

  /**
   * The rail's buckets, in the order a document walks them. Fixed, never derived from the data:
   * a chip row that loses a chip when a bucket empties reflows under the reader's cursor, and
   * "no drafts left" is itself the answer to a question.
   */
  static final List<String> STATUSES = List.of("DR", "CO", "CL", "VO");

  /**
   * The whitelist, and the only door. Key is the current {@code c_order.docstatus}, value is the
   * document action this screen will send. {@code DR -> CO} books the order; {@code CO -> RE}
   * reopens it, which is what makes the demo repeatable rather than a one-way trip through the
   * fixture. Anything absent here is refused by {@link ConfirmOrder} with an error envelope --
   * not an exception -- whatever the browser claims.
   *
   * Core allows more from each state ({@code VO} and {@code PR} from a draft, {@code CL} from a
   * completed order): this map is deliberately narrower than
   * {@code ActionButtonUtility.docAction}, and narrowing is the point.
   */
  static final Map<String, String> TRANSITIONS = transitions();

  private static Map<String, String> transitions() {
    final Map<String, String> out = new LinkedHashMap<>();
    out.put("DR", "CO");
    out.put("CO", "RE");
    return java.util.Collections.unmodifiableMap(out);
  }

  /** Order, its document type, its customer and its warehouse. All joined on primary keys. */
  static final String FROM = " from c_order o"
      + " join c_doctype dt on dt.c_doctype_id = o.c_doctypetarget_id"
      + " join c_bpartner bp on bp.c_bpartner_id = o.c_bpartner_id"
      + " left join m_warehouse w on w.m_warehouse_id = o.m_warehouse_id";

  /**
   * Who may see one order: the caller's readable clients and orgs, active, and a sales order.
   * {@code issotrx = 'Y'} is not cosmetic -- {@code c_order} holds purchase orders too, and this
   * window must not offer to book one.
   *
   * Bind order, repeated by every query built on this: scope(o).
   */
  static final String VIS = UikQuery.scopeClause("o") + " and o.issotrx = 'Y'";

  /**
   * The whitelist rendered as SQL, built from {@link #TRANSITIONS} so the two cannot disagree.
   * The client paints its button from this column; the server re-derives it from the same map.
   */
  static final String NEXT = nextSql();

  private static String nextSql() {
    final StringBuilder sql = new StringBuilder("case o.docstatus");
    for (Map.Entry<String, String> e : TRANSITIONS.entrySet()) {
      sql.append(" when '").append(e.getKey()).append("' then '").append(e.getValue()).append("'");
    }
    return sql.append(" else '' end").toString();
  }

  /** Binds {@link #VIS} starting at {@code from}; returns the next free index. */
  static int bindVis(PreparedStatement st, int from) throws Exception {
    return UikQuery.bindScope(st, from);
  }

  /**
   * Availability of one line's product in the order's own warehouse, summed over its locators.
   * Correlated on purpose: joining {@code m_storage_detail} into the line query fans a line into
   * one row per bin, and a semaphore built on a fanned count is wrong by a factor nobody notices.
   */
  private static final String ONHAND = "coalesce((select sum(sd.qtyonhand)"
      + " from m_storage_detail sd"
      + " join m_locator loc on loc.m_locator_id = sd.m_locator_id"
      + " where sd.m_product_id = ol.m_product_id and loc.m_warehouse_id = o.m_warehouse_id"
      + " and sd.isactive = 'Y' and loc.isactive = 'Y'), 0)";

  /** Sales Order window. The <em>tab</em> is resolved from the dictionary, never hardcoded. */
  static final String ORDER_WINDOW = "143";

  @Override
  protected JSONObject execute(Map<String, Object> parameters, String content) {
    try {
      final Connection conn = UikQuery.connection();
      final String raw = UikQuery.param(parameters, "status");
      final String status = raw != null && STATUSES.contains(raw) ? raw : null;
      final String q = UikQuery.param(parameters, "q");
      final String wanted = UikQuery.param(parameters, "order");
      final int[] window = UikQuery.page(parameters);

      final JSONObject counts = statuses(conn);
      final JSONArray statusList = new JSONArray();
      long all = 0;
      for (String s : STATUSES) {
        statusList.put(new JSONObject().put("status", s).put("n", counts.getLong(s)));
        all += counts.getLong(s);
      }

      // The header is read first and the lines only for the id it returned, so an id that is
      // not visible cannot reach the line query at all.
      final JSONObject head = wanted == null ? null : head(conn, wanted);
      final String id = head == null ? null : head.getString("id");

      final JSONObject asOf = UikQuery.asOf(conn, UikQuery.param(parameters, "asOf"),
          "select max(o.dateordered)" + FROM + " where " + VIS);

      return new JSONObject()
          .put("statuses", statusList)
          .put("total", all)
          .put("orders", orders(conn, status, q, window))
          .put("order", head == null ? JSONObject.NULL : head)
          .put("lines", id == null ? new JSONArray() : lines(conn, id))
          .put("page", new JSONObject()
              .put("limit", window[0])
              .put("offset", window[1])
              .put("matched", matched(conn, status, q)))
          .put("meta", new JSONObject()
              .put("role", OBContext.getOBContext().getRole().getId())
              .put("user", OBContext.getOBContext().getUser().getId())
              .put("statusList", new JSONArray(STATUSES))
              .put("transitions", new JSONObject(TRANSITIONS))
              .put("filter", new JSONObject()
                  .put("status", status == null ? "" : status)
                  .put("q", q == null ? "" : q)
                  .put("order", wanted == null ? "" : wanted))
              .put("resolved", id == null ? "" : id)
              .put("asOf", asOf.getString("asOf"))
              .put("asOfSource", asOf.getString("asOfSource"))
              .put("orderTab", nullSafe(UikQuery.tabFor(conn, ORDER_WINDOW, "c_order")))
              .put("scope", new JSONObject()
                  .put("clients", new JSONArray(List.of(UikQuery.readableClients())))
                  .put("orgs", new JSONArray(List.of(UikQuery.readableOrgs())))));
    } catch (Exception e) {
      log.error("ETDEMO_Picking read failed: {}", e.getMessage(), e);
      return error(e);
    }
  }

  /** An absent drill-down travels as an empty string, never as a JSON null. */
  static String nullSafe(String value) {
    return value == null ? "" : value;
  }

  private JSONObject error(Exception e) {
    try {
      return new JSONObject().put("error",
          new JSONObject().put("message", e.getMessage() == null ? e.toString() : e.getMessage()));
    } catch (Exception ignored) {
      return new JSONObject();
    }
  }

  /**
   * One count per status over the whole visible set: filter ignored, selection ignored. Every
   * bucket of {@link #STATUSES} is present even at zero.
   */
  private JSONObject statuses(Connection conn) throws Exception {
    final JSONObject out = new JSONObject();
    for (String s : STATUSES) {
      out.put(s, 0L);
    }
    final String sql = "select o.docstatus as st, count(*) as n" + FROM + " where " + VIS
        + " group by o.docstatus";
    try (PreparedStatement st = conn.prepareStatement(sql)) {
      bindVis(st, 1);
      try (ResultSet rs = st.executeQuery()) {
        while (rs.next()) {
          if (out.has(rs.getString("st"))) {
            out.put(rs.getString("st"), rs.getLong("n"));
          }
        }
      }
    }
    return out;
  }

  private static final String SEARCH = UikQuery.likeClause("o.documentno", "bp.name");

  private static final String NARROW = " where " + VIS
      + " and (?::text is null or o.docstatus = ?) and " + SEARCH;

  /** Binds {@link #NARROW} starting at 1; returns the next free index. */
  private int bindNarrow(PreparedStatement st, String status, String q) throws Exception {
    int i = bindVis(st, 1);
    st.setString(i++, status);
    st.setString(i++, status);
    return UikQuery.bindLike(st, i, q, 2);
  }

  /** How many orders the current filter matches, before the page window cuts it. */
  private long matched(Connection conn, String status, String q) throws Exception {
    try (PreparedStatement st = conn.prepareStatement("select count(*)" + FROM + NARROW)) {
      bindNarrow(st, status, q);
      return UikQuery.total(st);
    }
  }

  /**
   * The selector, and the only list that narrows. Drafts first, then completed, then everything
   * else, newest first inside each bucket: the orders this screen can act on come first, and the
   * hundreds of historical completed ones stay reachable behind them -- they are where the
   * service lines live, and the semaphore has to be shown ignoring one.
   */
  private JSONArray orders(Connection conn, String status, String q, int[] window)
      throws Exception {
    final String sql = "select o.c_order_id as id, o.documentno as documentno,"
        + " o.docstatus as st, " + NEXT + " as nextaction,"
        + " bp.name as bpname, dt.name as doctype, o.dateordered as dateordered,"
        + " o.grandtotal as grandtotal, coalesce(w.name, '') as warehouse,"
        + " (select count(*) from c_orderline ol where ol.c_order_id = o.c_order_id"
        + "   and ol.isactive = 'Y') as nlines"
        + FROM + NARROW
        + " order by case o.docstatus when 'DR' then 0 when 'CO' then 1 else 2 end,"
        + " o.dateordered desc, o.documentno desc limit ? offset ?";
    try (PreparedStatement st = conn.prepareStatement(sql)) {
      int i = bindNarrow(st, status, q);
      st.setInt(i++, window[0]);
      st.setInt(i, window[1]);
      try (ResultSet rs = st.executeQuery()) {
        return UikQuery.rows(rs, UikQuery.str("id", "id"),
            UikQuery.str("documentNo", "documentno"), UikQuery.str("status", "st"),
            UikQuery.str("nextAction", "nextaction"), UikQuery.str("bp", "bpname"),
            UikQuery.str("docType", "doctype"), UikQuery.date("date", "dateordered"),
            UikQuery.num("total", "grandtotal"), UikQuery.str("warehouse", "warehouse"),
            UikQuery.num("lines", "nlines"));
      }
    }
  }

  /**
   * The selected order's header, re-read under {@link #VIS}. Returns null both for an id that
   * does not exist and for one the caller may not see: the two answers are identical on purpose,
   * because a screen that distinguishes them has just told an outsider that the row is real.
   */
  static JSONObject head(Connection conn, String id) throws Exception {
    final String sql = "select o.c_order_id as id, o.documentno as documentno,"
        + " o.docstatus as st, " + NEXT + " as nextaction, o.processing as processing,"
        + " bp.name as bpname, dt.name as doctype, dt.c_doctype_id as doctypeid,"
        + " o.dateordered as dateordered, o.grandtotal as grandtotal,"
        + " coalesce(w.name, '') as warehouse, coalesce(o.description, '') as description"
        + FROM + " where " + VIS + " and o.c_order_id = ?";
    try (PreparedStatement st = conn.prepareStatement(sql)) {
      final int i = bindVis(st, 1);
      st.setString(i, id);
      try (ResultSet rs = st.executeQuery()) {
        final JSONArray found = UikQuery.rows(rs, UikQuery.str("id", "id"),
            UikQuery.str("documentNo", "documentno"), UikQuery.str("status", "st"),
            UikQuery.str("nextAction", "nextaction"), UikQuery.str("processing", "processing"),
            UikQuery.str("bp", "bpname"), UikQuery.str("docType", "doctype"),
            UikQuery.str("docTypeId", "doctypeid"), UikQuery.date("date", "dateordered"),
            UikQuery.num("total", "grandtotal"), UikQuery.str("warehouse", "warehouse"),
            UikQuery.str("description", "description"));
        return found.length() == 0 ? null : found.getJSONObject(0);
      }
    }
  }

  /**
   * The lines of one order with the semaphore, computed in SQL so a gate can recompute it from
   * the physical tables without re-implementing JavaScript.
   *
   * <ul>
   * <li>{@code stocked} is {@code isstocked = 'Y' and producttype = 'I'}. A service line has no
   * stock to be short of, so it is {@code na} -- grey, not red. This instance's completed sales
   * orders carry 487 such lines against 5499 stocked ones, which is why the distinction is not
   * theoretical.</li>
   * <li>{@code pending} is {@code greatest(0, qtyordered - qtydelivered)}. The clamp is
   * defensive: no visible line has a negative ordered quantity today, but return lines elsewhere
   * in this database do, and a semaphore that renders "-1 pending" as red is worse than one that
   * renders it as nothing to do.</li>
   * </ul>
   */
  private JSONArray lines(Connection conn, String id) throws Exception {
    final String sql = "with l as (select ol.c_orderline_id as id, ol.line as line,"
        + " p.value as code, p.name as pname, p.producttype as producttype,"
        + " p.isstocked as isstocked, coalesce(um.name, '') as uom,"
        + " ol.qtyordered as qtyordered, ol.qtydelivered as qtydelivered,"
        + " greatest(0, ol.qtyordered - ol.qtydelivered) as pending,"
        + " (p.isstocked = 'Y' and p.producttype = 'I') as stocked,"
        + " " + ONHAND + " as onhand"
        + " from c_orderline ol"
        + " join c_order o on o.c_order_id = ol.c_order_id"
        + " join m_product p on p.m_product_id = ol.m_product_id"
        + " left join c_uom um on um.c_uom_id = ol.c_uom_id"
        + " where " + VIS + " and o.c_order_id = ? and ol.isactive = 'Y')"
        + " select l.*, case when not l.stocked then 'na' when l.pending <= 0 then 'done'"
        + " when l.onhand >= l.pending then 'ok' when l.onhand > 0 then 'partial'"
        + " else 'short' end as tone from l order by l.line, l.id";
    try (PreparedStatement st = conn.prepareStatement(sql)) {
      final int i = bindVis(st, 1);
      st.setString(i, id);
      try (ResultSet rs = st.executeQuery()) {
        return UikQuery.rows(rs, UikQuery.str("id", "id"), UikQuery.num("line", "line"),
            UikQuery.str("code", "code"), UikQuery.str("product", "pname"),
            UikQuery.str("productType", "producttype"), UikQuery.str("stocked", "isstocked"),
            UikQuery.str("uom", "uom"), UikQuery.num("ordered", "qtyordered"),
            UikQuery.num("delivered", "qtydelivered"), UikQuery.num("pending", "pending"),
            UikQuery.num("onHand", "onhand"), UikQuery.str("tone", "tone"));
      }
    }
  }
}
