package com.etendoerp.uikit.samples.product360;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.List;
import java.util.Map;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.codehaus.jettison.json.JSONArray;
import org.codehaus.jettison.json.JSONObject;
import org.openbravo.client.kernel.BaseActionHandler;

import com.etendoerp.uikit.server.UikQuery;

/**
 * Datasource ETDEMO_ProductLedger: the movement half of one product's 360.
 *
 * Three panels: the ledger by period, the mix of document types behind it, and the trail of
 * individual transactions. It is a separate datasource from {@link ProductStock} so the two halves
 * load in parallel -- the figures at the top of the window do not wait for eleven years of
 * aggregation -- and so the trail can page without re-reading anything else.
 *
 * <h2>Why the ledger is the backbone of the window</h2>
 *
 * {@code m_transaction} is signed: a receipt is positive and a shipment negative. Accumulate one
 * product's transactions in date order and the running total is the quantity on hand, and on this
 * instance it lands exactly: eleven years of ins and outs for the sample product accumulate to
 * 135 665, which is the figure {@code m_storage_detail} reports today, warehouse by warehouse as
 * well as in total. So the ledger is not an illustration of the stock figure -- it is a derivation
 * of it, and if the last balance ever stops matching the header, one of the two is wrong and the
 * window shows both.
 *
 * That is also why {@code series} carries every period from the first movement to the last, with no
 * date filter: a balance is only a balance if nothing before it is missing. {@code grain} chooses
 * how finely those periods are cut, never which of them are included.
 *
 * <h2>Where a trail row can be opened</h2>
 *
 * Every transaction on this instance resolves to exactly one parent document -- 8737 through
 * {@code m_inoutline}, 402 through {@code m_inventoryline}, 28 through {@code m_movementline}, and
 * none with no parent at all. So the trail names its document and offers to open it, in the right
 * window of the four: a receipt and a shipment are both {@code m_inout} but they live in different
 * windows, and the physical inventory has no {@code documentno} column at all -- it is named.
 *
 * <h2>What is not here</h2>
 *
 * No velocity, no coverage, no reorder point. Dividing the last year's outflow by 365 would produce
 * a number, and calling it "days of cover" would turn an arithmetic mean into a promise about the
 * future that nothing in this database supports. The ledger says what was moved and when; the
 * reader draws the conclusion.
 */
public class ProductLedger extends BaseActionHandler {

  private static final Logger log = LogManager.getLogger();

  /** This datasource's name in the server log. Never returned to the browser. */
  private static final String DATASOURCE = "ETDEMO_ProductLedger";

  /** Core's windows the trail can open into. Tabs are resolved from the dictionary. */
  private static final String MOVEMENT_WINDOW = "170";

  private static final String SHIPMENT_WINDOW = "169";

  private static final String RECEIPT_WINDOW = "184";

  private static final String INVENTORY_WINDOW = "168";

  /**
   * Whitelisted period grains. The request picks a key; the key picks the format string. No request
   * value ever reaches the SQL text, here as everywhere.
   *
   * The pair is (format, label): {@code to_char} renders the period and the second half is what the
   * axis of the chart is measured in, so the view does not have to guess from the shape of the
   * string.
   */
  private static final Map<String, String> GRAIN = Map.of(
      "year", "YYYY",
      "month", "YYYY-MM");

  private static final String DEFAULT_GRAIN = "year";

  /**
   * The ledger: one row per period, with the running balance.
   *
   * Bind order: the grain format, id, scope(t), scope(l), filter pair.
   *
   * The format string is bound rather than concatenated even though it comes from
   * {@link #GRAIN} and could not carry a request value: binding it costs nothing and means the
   * whitelist is a second lock rather than the only one.
   */
  private static String seriesSql() {
    return "with per as ("
        + " select to_char(t.movementdate, ?) as period,"
        + "        sum(case when t.movementqty > 0 then t.movementqty else 0 end) as qty_in,"
        + "        sum(case when t.movementqty < 0 then -t.movementqty else 0 end) as qty_out,"
        + "        sum(t.movementqty) as net,"
        + "        count(*) as lines,"
        + "        min(t.movementdate) as first_date, max(t.movementdate) as last_date"
        + " from m_transaction t"
        + "   join m_locator l on l.m_locator_id = t.m_locator_id"
        + " where t.m_product_id = ? and " + UikQuery.scopeClause("t") + " and "
        + UikQuery.scopeClause("l")
        + "   and (?::text is null or l.m_warehouse_id = ?)"
        // Ordinal, not the expression again: two placeholders over one expression are two
        // distinct parameters for Postgres, which then refuses to see them as the same thing and
        // demands the column in the group by. The ordinal says it once.
        + " group by 1"
        + ")"
        + " select period, qty_in, qty_out, net, lines, first_date, last_date,"
        // El acumulado es la columna que sostiene la ventana: al ultimo periodo tiene que valer lo
        // que dice la cabecera. Se calcula sobre el periodo ordenado como texto, que es correcto
        // porque los dos formatos del whitelist ordenan igual como texto que como fecha.
        + "        sum(net) over (order by period asc rows between unbounded preceding"
        + "                       and current row) as balance"
        + " from per order by period asc";
  }

  /**
   * The document types behind the ledger. Bind order: id, scope(t), scope(l), filter pair.
   *
   * The label is Etendo's own, read from {@code ad_ref_list} through {@link Product360#refLabel}: {@code C-}
   * reads "Customer Shipment" because the dictionary says so, not because this module decided.
   */
  private static String mixSql() {
    return "select t.movementtype as type,"
        + " coalesce(nullif(trim(mtl.name), ''), t.movementtype) as label,"
        + " count(*) as lines,"
        + " sum(case when t.movementqty > 0 then t.movementqty else 0 end) as qty_in,"
        + " sum(case when t.movementqty < 0 then -t.movementqty else 0 end) as qty_out,"
        + " min(t.movementdate) as first_date, max(t.movementdate) as last_date"
        + " from m_transaction t"
        + "   join m_locator l on l.m_locator_id = t.m_locator_id"
        + Product360.refLabel("mtl", "M_Transaction", "MovementType", "t.movementtype")
        + " where t.m_product_id = ? and " + UikQuery.scopeClause("t") + " and "
        + UikQuery.scopeClause("l")
        + "   and (?::text is null or l.m_warehouse_id = ?)"
        + " group by t.movementtype, coalesce(nullif(trim(mtl.name), ''), t.movementtype)"
        + " order by count(*) desc";
  }

  /**
   * Every readable transaction of this product, newest first, with the document it belongs to.
   *
   * Shared by the page query and the count query so the two cannot disagree about what the trail
   * is.
   *
   * Bind order, which is SQL text order: the six document tables are reached through left joins
   * and each one carries its scope inside its ON, so they bind before the where -- il, io, invl,
   * inv, mvl, mv -- then the label join takes none, then id, scope(t), scope(l), scope(w), and the
   * filter pair.
   *
   * The document tables are left joins and scoped inside the ON for the same reason the shelves
   * are in {@link ProductStock}: a parent document outside scope must leave the row without a
   * document to open, not remove a movement the ledger above has already counted. The trail and
   * the ledger have to describe the same transactions.
   */
  private static String trailSql() {
    return "with det as ("
        + " select t.m_transaction_id as id, t.movementdate as move_date,"
        + "        t.movementtype as type,"
        + "        coalesce(nullif(trim(mtl.name), ''), t.movementtype) as label,"
        + "        t.movementqty as qty,"
        + "        w.m_warehouse_id as warehouse_id, w.name as warehouse, l.value as locator,"
        + "        coalesce(io.documentno, mv.documentno, inv.name, '') as document,"
        + "        case when io.m_inout_id is not null and io.issotrx = 'Y' then 'shipment'"
        + "             when io.m_inout_id is not null then 'receipt'"
        + "             when inv.m_inventory_id is not null then 'inventory'"
        + "             when mv.m_movement_id is not null then 'movement'"
        + "             else '' end as doc_kind,"
        + "        coalesce(io.m_inout_id, inv.m_inventory_id, mv.m_movement_id, '') as doc_id"
        + " from m_transaction t"
        + "   join m_locator l on l.m_locator_id = t.m_locator_id"
        + "   join m_warehouse w on w.m_warehouse_id = l.m_warehouse_id"
        + "   left join m_inoutline il on il.m_inoutline_id = t.m_inoutline_id"
        + "        and " + UikQuery.scopeClause("il")
        + "   left join m_inout io on io.m_inout_id = il.m_inout_id"
        + "        and " + UikQuery.scopeClause("io")
        + "   left join m_inventoryline invl on invl.m_inventoryline_id = t.m_inventoryline_id"
        + "        and " + UikQuery.scopeClause("invl")
        + "   left join m_inventory inv on inv.m_inventory_id = invl.m_inventory_id"
        + "        and " + UikQuery.scopeClause("inv")
        + "   left join m_movementline mvl on mvl.m_movementline_id = t.m_movementline_id"
        + "        and " + UikQuery.scopeClause("mvl")
        + "   left join m_movement mv on mv.m_movement_id = mvl.m_movement_id"
        + "        and " + UikQuery.scopeClause("mv")
        + Product360.refLabel("mtl", "M_Transaction", "MovementType", "t.movementtype")
        + " where t.m_product_id = ? and " + UikQuery.scopeClause("t") + " and "
        + UikQuery.scopeClause("l") + " and " + UikQuery.scopeClause("w")
        + "   and (?::text is null or l.m_warehouse_id = ?)"
        + ")";
  }

  @Override
  protected JSONObject execute(Map<String, Object> parameters, String content) {
    try {
      final Connection conn = UikQuery.connection();
      final String itemId = UikQuery.param(parameters, "itemId");
      final String warehouse = UikQuery.param(parameters, "warehouseId");
      final String requested = UikQuery.param(parameters, "grain");
      // requested is null when the caller omits grain, and Map.of's ImmutableCollections
      // throws on containsKey(null) rather than answering false -- so the null is tested first.
      final String grainKey = requested != null && GRAIN.containsKey(requested) ? requested
          : DEFAULT_GRAIN;
      final int[] window = UikQuery.page(parameters);

      final JSONObject result = new JSONObject();
      result.put("meta", meta(conn, warehouse, grainKey));
      if (itemId == null || itemId.trim().isEmpty()) {
        return empty(result);
      }

      result.put("series", series(conn, itemId, warehouse, grainKey));
      result.put("mix", mix(conn, itemId, warehouse));
      result.put("trail", trail(conn, itemId, warehouse, window[0], window[1]));

      final long total = count(conn, itemId, warehouse);
      result.put("page", new JSONObject()
          .put("limit", window[0])
          .put("offset", window[1])
          .put("page", (window[1] / window[0]) + 1)
          .put("total", total)
          .put("pages", Math.max(1, (total + window[0] - 1) / window[0])));
      return result;
    } catch (Exception e) {
      log.error("{} failed: {}", DATASOURCE, e.getMessage(), e);
      return Product360.error(e);
    }
  }

  /**
   * The answer for "no product asked for": every key present and empty.
   *
   * A product that does not exist, or one outside scope, needs no special case here -- it simply
   * has no transactions, and the three panels come back empty on their own. That is the same answer
   * this method gives, which is the point: the payload cannot be used to tell the two apart.
   */
  private JSONObject empty(JSONObject result) throws Exception {
    return result.put("series", new JSONArray())
        .put("mix", new JSONArray())
        .put("trail", new JSONArray())
        .put("page", new JSONObject()
            .put("limit", 0).put("offset", 0).put("page", 1).put("total", 0).put("pages", 1));
  }

  private JSONObject meta(Connection conn, String warehouse, String grainKey) throws Exception {
    return new JSONObject()
        .put("productTab", nullSafe(UikQuery.tabFor(conn, Product360.PRODUCT_WINDOW, "m_product")))
        .put("movementTab", nullSafe(UikQuery.tabFor(conn, MOVEMENT_WINDOW, "m_movement")))
        .put("shipmentTab", nullSafe(UikQuery.tabFor(conn, SHIPMENT_WINDOW, "m_inout")))
        .put("receiptTab", nullSafe(UikQuery.tabFor(conn, RECEIPT_WINDOW, "m_inout")))
        .put("inventoryTab", nullSafe(UikQuery.tabFor(conn, INVENTORY_WINDOW, "m_inventory")))
        .put("grain", grainKey)
        .put("warehouseId", warehouse == null ? "" : warehouse)
        .put("scope", new JSONObject()
            .put("clients", new JSONArray(List.of(UikQuery.readableClients())))
            .put("orgs", new JSONArray(List.of(UikQuery.readableOrgs()))));
  }

  private JSONArray series(Connection conn, String itemId, String warehouse, String grainKey)
      throws Exception {
    try (PreparedStatement st = conn.prepareStatement(seriesSql())) {
      int i = 1;
      // The format from the whitelist, bound where the select renders it.
      st.setString(i++, GRAIN.get(grainKey));
      st.setString(i++, itemId);
      i = UikQuery.bindScope(st, i);
      i = UikQuery.bindScope(st, i);
      st.setString(i++, warehouse);
      st.setString(i, warehouse);
      try (ResultSet rs = st.executeQuery()) {
        return UikQuery.rows(rs,
            UikQuery.str("period", "period"),
            UikQuery.num("qtyIn", "qty_in"),
            UikQuery.num("qtyOut", "qty_out"),
            UikQuery.num("net", "net"),
            UikQuery.num("lines", "lines"),
            UikQuery.num("balance", "balance"),
            UikQuery.date("firstDate", "first_date"),
            UikQuery.date("lastDate", "last_date"));
      }
    }
  }

  private JSONArray mix(Connection conn, String itemId, String warehouse) throws Exception {
    try (PreparedStatement st = conn.prepareStatement(mixSql())) {
      int i = 1;
      st.setString(i++, itemId);
      i = UikQuery.bindScope(st, i);
      i = UikQuery.bindScope(st, i);
      st.setString(i++, warehouse);
      st.setString(i, warehouse);
      try (ResultSet rs = st.executeQuery()) {
        return UikQuery.rows(rs,
            UikQuery.str("type", "type"),
            UikQuery.str("label", "label"),
            UikQuery.num("lines", "lines"),
            UikQuery.num("qtyIn", "qty_in"),
            UikQuery.num("qtyOut", "qty_out"),
            UikQuery.date("firstDate", "first_date"),
            UikQuery.date("lastDate", "last_date"));
      }
    }
  }

  private JSONArray trail(Connection conn, String itemId, String warehouse, int limit, int offset)
      throws Exception {
    final String sql = trailSql()
        + " select * from det order by move_date desc, id desc limit ? offset ?";
    try (PreparedStatement st = conn.prepareStatement(sql)) {
      int i = bindTrail(st, itemId, warehouse);
      st.setInt(i++, limit);
      st.setInt(i, offset);
      try (ResultSet rs = st.executeQuery()) {
        return UikQuery.rows(rs,
            UikQuery.str("id", "id"),
            UikQuery.date("date", "move_date"),
            UikQuery.str("type", "type"),
            UikQuery.str("label", "label"),
            UikQuery.num("qty", "qty"),
            UikQuery.str("warehouseId", "warehouse_id"),
            UikQuery.str("warehouse", "warehouse"),
            UikQuery.str("locator", "locator"),
            UikQuery.str("document", "document"),
            UikQuery.str("docKind", "doc_kind"),
            UikQuery.str("docId", "doc_id"));
      }
    }
  }

  private long count(Connection conn, String itemId, String warehouse) throws Exception {
    try (PreparedStatement st = conn.prepareStatement(trailSql() + " select count(*) from det")) {
      bindTrail(st, itemId, warehouse);
      return UikQuery.total(st);
    }
  }

  /**
   * Fills the shared prefix of both queries built on {@code trailSql()} and returns the next free
   * index.
   *
   * Nine scope clauses, and the order is the order the SQL renders: the six document tables carry
   * theirs inside a join's ON, so they come first, and only then the three in the where.
   */
  private int bindTrail(PreparedStatement st, String itemId, String warehouse) throws Exception {
    int i = 1;
    // The document chain, in the order the left joins render: il, io, invl, inv, mvl, mv.
    i = UikQuery.bindScope(st, i);
    i = UikQuery.bindScope(st, i);
    i = UikQuery.bindScope(st, i);
    i = UikQuery.bindScope(st, i);
    i = UikQuery.bindScope(st, i);
    i = UikQuery.bindScope(st, i);
    // Then the where: the product, and the three tables the row is built from.
    st.setString(i++, itemId);
    i = UikQuery.bindScope(st, i);
    i = UikQuery.bindScope(st, i);
    i = UikQuery.bindScope(st, i);
    // The marker and the value are the same string twice: null leaves the clause inert.
    st.setString(i++, warehouse);
    st.setString(i++, warehouse);
    return i;
  }

  private Object nullSafe(String value) {
    return value == null ? JSONObject.NULL : value;
  }

}
