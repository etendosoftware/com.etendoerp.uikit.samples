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
 * Datasource ETDEMO_ProductStock: one product's stock read along every dimension the data has.
 *
 * Eight panels off one product id: the header, the totals, the recorded cost, the warehouses, the
 * locators, the attribute instances, the product's rank inside its category, and the order lines
 * still outstanding. The movement side -- the ledger, the document mix and the trail -- lives in
 * {@link ProductLedger}, so the two halves of the window load in parallel and a slow year-by-year
 * aggregate never delays the figure at the top.
 *
 * <h2>What was measured before any of this was designed</h2>
 *
 * Three findings from the live instance shaped these panels, and each one removed something a 360
 * screen would normally show:
 *
 * <ul>
 * <li><b>There is no expiry.</b> {@code m_attributesetinstance.guaranteedate} is null in all 218
 * instances, so there is no shelf-life panel and no "expires in N days". A window that computed one
 * would be reporting the absence of a column as a business fact.</li>
 * <li><b>The purchase pending is not stock in transit.</b> Its lines accumulate from 2011 to 2021
 * -- roughly three hundred a year that were never received -- and for the sample product they add
 * up to 5 394 680 against 135 665 actually on hand. So {@code pending} is published <b>dated by
 * year</b> and is never added to a stock figure. Forty times the on-hand quantity announced as
 * "incoming" would be the single most misleading number this module could print.</li>
 * <li><b>The sales commitment is dormant.</b> 52 lines, the newest from 2016, six units. It is
 * reported in the same panel and by the same rule, as its own direction.</li>
 * </ul>
 *
 * A fourth rule was decided here rather than found: <b>no valuation</b>. {@code worth} carries the
 * average cost per unit actually recorded on receipt lines, per currency, and the number of lines
 * behind it. It does not multiply that average by today's quantity. Etendo has a costing engine for
 * inventory value; an average of eleven years of receipts multiplied by a current quantity would
 * look like that number and would not be it. Note the currencies are plural on this instance -- the
 * same product records receipts in EUR and in USD -- which is the same reason quantities are never
 * added across units of measure.
 *
 * <h2>The warehouse filter</h2>
 *
 * {@code warehouseId} narrows {@code totals}, {@code worth}, {@code locators}, {@code lots},
 * {@code peers} and {@code pending}. It deliberately does <b>not</b> narrow {@code warehouses}:
 * that panel is the control the reader clicks to set the filter, and a filter whose options depend
 * on its own value cannot be cleared.
 *
 * <h2>Not found and not readable answer the same</h2>
 *
 * No product selected, a product that does not exist, and a product outside the session's scope all
 * return {@link #empty()} -- one method, so the three cannot be told apart by the shape of the
 * payload, and the window cannot be used to probe for the existence of rows it may not read.
 */
public class ProductStock extends BaseActionHandler {

  private static final Logger log = LogManager.getLogger();

  /** This datasource's name in the server log. Never returned to the browser. */
  private static final String DATASOURCE = "ETDEMO_ProductStock";

  /**
   * Panel caps. These are panels, not lists: they have no pager, so each one states how many rows
   * it will draw and the totals block says how many there are, rather than the panel quietly
   * ending. The widest product on this instance holds 22 attribute instances and 6 locators.
   */
  private static final int LOCATOR_ROWS = 50;

  private static final int LOT_ROWS = 20;

  private static final int PEER_ROWS = 12;

  /** The product's own row, its category and its unit. Bind order: scope(pc), scope(ats), id, scope(p). */
  private static String headSql() {
    return "select p.m_product_id as id, p.value as code, p.name as name,"
        + " coalesce(p.description, '') as description,"
        + " coalesce(pc.m_product_category_id, '') as category_id,"
        + " coalesce(pc.name, '') as category,"
        + " coalesce(nullif(trim(u.uomsymbol), ''), u.name, '') as uom,"
        + " p.qtymin as qtymin, p.isstocked as stocked,"
        + " coalesce(ats.name, '') as attribute_set"
        + " from m_product p"
        // La categoria y el conjunto de atributos llevan alcance dentro del ON: si no casan, el
        // producto se sigue leyendo sin su categoria, que es mejor que no leerlo. La unidad no
        // lleva alcance, igual que en las otras siete ventanas: c_uom es vocabulario.
        + "   left join m_product_category pc"
        + "     on pc.m_product_category_id = p.m_product_category_id"
        + "        and " + UikQuery.scopeClause("pc")
        + "   left join m_attributeset ats"
        + "     on ats.m_attributeset_id = p.m_attributeset_id"
        + "        and " + UikQuery.scopeClause("ats")
        + "   left join c_uom u on u.c_uom_id = p.c_uom_id"
        + " where p.m_product_id = ? and " + UikQuery.scopeClause("p");
  }

  /**
   * Everything the storage rows say at once. Bind order: id, scope(sd), scope(l), filter pair.
   *
   * {@code locators}, {@code warehouses} and {@code lots} count only rows with a quantity: a
   * storage row at zero is inventory history, not a place to go and look, and counting it would
   * make this block disagree with the panels below it. {@code rows} counts them all, so the
   * locator panel can say how many it is not drawing.
   */
  private static String totalsSql() {
    return "select coalesce(sum(sd.qtyonhand), 0) as onhand,"
        + " coalesce(sum(coalesce(sd.reservedqty, 0)), 0) as reserved,"
        + " coalesce(sum(sd.qtyonhand), 0) - coalesce(sum(coalesce(sd.reservedqty, 0)), 0)"
        + "   as available,"
        + " count(distinct case when sd.qtyonhand <> 0 then sd.m_locator_id end) as locators,"
        + " count(distinct case when sd.qtyonhand <> 0 then l.m_warehouse_id end) as warehouses,"
        // La instancia "sin atributo" es el id '0', una fila real de m_attributesetinstance que
        // llevan 169 de las 255 filas de existencias de esta base. Contarla hacia que la casilla
        // dijese "1 lote" para un producto que no lleva lote ninguno, y el panel de debajo
        // dibujase una barra fija repitiendo el "en mano" de la cabecera.
        + " count(distinct case when sd.qtyonhand <> 0"
        + "        and sd.m_attributesetinstance_id <> '0'"
        + "        then sd.m_attributesetinstance_id end) as lots,"
        + " count(*) as rows,"
        + " max(sd.datelastinventory) as last_inventory"
        + " from m_storage_detail sd"
        + "   join m_locator l on l.m_locator_id = sd.m_locator_id"
        + " where sd.m_product_id = ? and " + UikQuery.scopeClause("sd") + " and "
        + UikQuery.scopeClause("l")
        + "   and (?::text is null or l.m_warehouse_id = ?)";
  }

  /**
   * The cost this instance actually recorded, per currency. Bind order: id, scope(t), scope(l),
   * filter pair.
   *
   * Only inbound transactions, because a cost per unit is a thing you paid on receipt. The division
   * is the recorded total cost over the recorded quantity -- an average of what happened, not a
   * valuation of what is there.
   */
  private static String worthSql() {
    return "select c.iso_code as currency,"
        + " sum(t.transactioncost) / nullif(sum(abs(t.movementqty)), 0) as unit_cost,"
        + " count(*) as lines, min(t.movementdate) as first_date, max(t.movementdate) as last_date"
        + " from m_transaction t"
        + "   join m_locator l on l.m_locator_id = t.m_locator_id"
        + "   join c_currency c on c.c_currency_id = t.c_currency_id"
        + " where t.m_product_id = ? and t.movementqty > 0"
        + "   and " + UikQuery.scopeClause("t") + " and " + UikQuery.scopeClause("l")
        + "   and (?::text is null or l.m_warehouse_id = ?)"
        + " group by c.iso_code order by count(*) desc, c.iso_code asc";
  }

  /**
   * Where the product sits, one row per warehouse holding a storage row for it.
   *
   * Bind order: id, scope(sd), scope(l), scope(w). No filter pair, on purpose: this panel is the
   * filter. Warehouses whose rows are all at zero stay in the list -- an empty shelf that used to
   * hold something is information, and dropping it would make the panel disagree with the locator
   * count in {@code totals}.
   */
  private static String warehousesSql() {
    return "select w.m_warehouse_id as id, w.name as name,"
        + " coalesce(sum(sd.qtyonhand), 0) as onhand,"
        + " coalesce(sum(coalesce(sd.reservedqty, 0)), 0) as reserved,"
        + " count(distinct case when sd.qtyonhand <> 0 then sd.m_locator_id end) as locators,"
        + " count(*) as rows"
        + " from m_storage_detail sd"
        + "   join m_locator l on l.m_locator_id = sd.m_locator_id"
        + "   join m_warehouse w on w.m_warehouse_id = l.m_warehouse_id"
        + " where sd.m_product_id = ? and " + UikQuery.scopeClause("sd") + " and "
        + UikQuery.scopeClause("l") + " and " + UikQuery.scopeClause("w")
        + " group by w.m_warehouse_id, w.name"
        + " order by coalesce(sum(sd.qtyonhand), 0) desc, w.name asc";
  }

  /**
   * The actual shelves. Bind order: scope(asi), id, scope(sd), scope(l), scope(w), filter pair.
   *
   * The attribute scope binds first because it lives in the ON of a left join and the from clause
   * renders before the where -- and it is a left join on purpose: an attribute instance the
   * session may not read must void the lot name, not discard the quantity standing on the
   * shelf, or this panel would stop adding up to the totals above it.
   */
  private static String locatorsSql() {
    return "select w.m_warehouse_id as warehouse_id, w.name as warehouse, l.value as locator,"
        + " coalesce(asi.description, '') as attribute,"
        + " sd.qtyonhand as onhand, coalesce(sd.reservedqty, 0) as reserved,"
        + " sd.datelastinventory as last_inventory"
        + " from m_storage_detail sd"
        + "   join m_locator l on l.m_locator_id = sd.m_locator_id"
        + "   join m_warehouse w on w.m_warehouse_id = l.m_warehouse_id"
        + "   left join m_attributesetinstance asi"
        + "     on asi.m_attributesetinstance_id = sd.m_attributesetinstance_id"
        + "        and " + UikQuery.scopeClause("asi")
        + " where sd.m_product_id = ? and " + UikQuery.scopeClause("sd") + " and "
        + UikQuery.scopeClause("l") + " and " + UikQuery.scopeClause("w")
        + "   and (?::text is null or l.m_warehouse_id = ?)"
        + " order by sd.qtyonhand desc nulls last, w.name asc, l.value asc"
        + " limit ?";
  }

  /**
   * Lots and serial numbers, by the description Etendo prints for the instance.
   *
   * Bind order: scope(asi), id, scope(sd), scope(l), filter pair. Rows with no instance group under
   * an empty label, which the window renders as its own line rather than hiding: on this instance
   * most products have no attribute instance at all, and the honest answer is to say so.
   */
  private static String lotsSql() {
    return "select coalesce(asi.description, '') as label,"
        + " coalesce(sum(sd.qtyonhand), 0) as onhand,"
        + " count(distinct case when sd.qtyonhand <> 0 then sd.m_locator_id end) as locators,"
        + " count(*) as rows"
        + " from m_storage_detail sd"
        + "   join m_locator l on l.m_locator_id = sd.m_locator_id"
        + "   left join m_attributesetinstance asi"
        + "     on asi.m_attributesetinstance_id = sd.m_attributesetinstance_id"
        + "        and " + UikQuery.scopeClause("asi")
        + " where sd.m_product_id = ? and " + UikQuery.scopeClause("sd") + " and "
        + UikQuery.scopeClause("l")
        + "   and (?::text is null or l.m_warehouse_id = ?)"
        + " group by coalesce(asi.description, '')"
        + " order by coalesce(sum(sd.qtyonhand), 0) desc, 1 asc"
        + " limit ?";
  }

  /**
   * The product's place among the goods sharing its category.
   *
   * Bind order: id, scope(p0), scope(p2), then per peer row the correlated pair scope(sd),
   * scope(l) and the filter pair, then the row cap and the product id again.
   *
   * The rank is computed over the whole category and only then cut, and the {@code or id = ?} keeps
   * the product itself in the answer even when it ranks below the cap -- a panel that dropped the
   * product you are looking at would be answering a different question.
   */
  private static String peersSql() {
    return "with cat as ("
        + " select p0.m_product_category_id as cid from m_product p0"
        + " where p0.m_product_id = ? and " + UikQuery.scopeClause("p0")
        + "), agg as ("
        + " select p2.m_product_id as id, p2.value as code, p2.name as name,"
        + "        coalesce((select sum(sd.qtyonhand) from m_storage_detail sd"
        + "                    join m_locator l on l.m_locator_id = sd.m_locator_id"
        + "                  where sd.m_product_id = p2.m_product_id"
        + "                    and " + UikQuery.scopeClause("sd") + " and "
        + UikQuery.scopeClause("l")
        + "                    and (?::text is null or l.m_warehouse_id = ?)), 0) as onhand"
        + " from m_product p2 join cat on p2.m_product_category_id = cat.cid"
        + " where " + UikQuery.scopeClause("p2")
        + "   and p2.producttype = 'I' and p2.isactive = 'Y'"
        + "), ranked as ("
        + " select agg.*, row_number() over (order by onhand desc, code asc) as rank,"
        + "        count(*) over () as peers from agg"
        + ")"
        + " select id, code, name, onhand, rank, peers from ranked"
        + " where rank <= ? or id = ? order by rank asc";
  }

  /**
   * Order lines still outstanding, dated by the year of the order.
   *
   * Bind order: id, scope(ol), scope(o), filter pair.
   *
   * The year is the point. These lines are not in transit: on this instance they run from 2011 to
   * 2021 and their sum is around forty times the quantity on hand, because purchase orders here are
   * booked and never received. Dating them lets the reader see that at a glance, and nothing in
   * this module ever adds this figure to a stock figure.
   */
  private static String pendingSql() {
    return "select to_char(o.dateordered, 'YYYY') as period,"
        + " case when o.issotrx = 'Y' then 'sales' else 'purchase' end as direction,"
        + " count(*) as lines,"
        + " coalesce(sum(ol.qtyordered - ol.qtydelivered), 0) as qty"
        + " from c_orderline ol"
        + "   join c_order o on o.c_order_id = ol.c_order_id"
        + " where ol.m_product_id = ? and ol.qtyordered > ol.qtydelivered"
        + "   and o.docstatus in ('CO', 'CL')"
        + "   and " + UikQuery.scopeClause("ol") + " and " + UikQuery.scopeClause("o")
        + "   and (?::text is null or o.m_warehouse_id = ?)"
        + " group by 1, 2 order by 1 asc, 2 asc";
  }

  /** The newest movement in scope, which is what {@code meta.asOf} reports. Bind: scope(t). */
  private static String newestSql() {
    return "select max(t.movementdate) from m_transaction t where " + UikQuery.scopeClause("t");
  }

  @Override
  protected JSONObject execute(Map<String, Object> parameters, String content) {
    try {
      final Connection conn = UikQuery.connection();
      final String itemId = UikQuery.param(parameters, "itemId");
      final String warehouse = UikQuery.param(parameters, "warehouseId");

      final JSONObject result = new JSONObject();
      result.put("meta", meta(conn, warehouse));
      if (itemId == null || itemId.trim().isEmpty()) {
        return empty(result);
      }
      final JSONObject head = head(conn, itemId);
      if (head == null) {
        return empty(result);
      }

      result.put("head", head);
      result.put("totals", totals(conn, itemId, warehouse));
      result.put("worth", worth(conn, itemId, warehouse));
      result.put("warehouses", warehouses(conn, itemId));
      result.put("locators", locators(conn, itemId, warehouse));
      result.put("lots", lots(conn, itemId, warehouse));
      result.put("peers", peers(conn, itemId, warehouse));
      result.put("pending", pending(conn, itemId, warehouse));
      return result;
    } catch (Exception e) {
      log.error("{} failed: {}", DATASOURCE, e.getMessage(), e);
      return Product360.error(e);
    }
  }

  /**
   * The answer for "nothing to show": no product asked for, no such product, or a product this
   * session may not read.
   *
   * One method rather than two copies of an expression, so the three cases are indistinguishable by
   * construction and not by a reviewer's diligence. Every key the window reads is present and
   * empty, so the view renders its empty states instead of failing on a missing key.
   */
  private JSONObject empty(JSONObject result) throws Exception {
    return result.put("head", JSONObject.NULL)
        .put("totals", new JSONObject())
        .put("worth", new JSONArray())
        .put("warehouses", new JSONArray())
        .put("locators", new JSONArray())
        .put("lots", new JSONArray())
        .put("peers", new JSONArray())
        .put("pending", new JSONArray());
  }

  private JSONObject meta(Connection conn, String warehouse) throws Exception {
    final JSONObject asOf = UikQuery.asOf(conn, null, newestSql());
    return new JSONObject()
        .put("productTab", nullSafe(UikQuery.tabFor(conn, Product360.PRODUCT_WINDOW, "m_product")))
        .put("warehouseId", warehouse == null ? "" : warehouse)
        .put("asOf", asOf.get("asOf"))
        .put("asOfSource", asOf.get("asOfSource"))
        .put("locatorRows", LOCATOR_ROWS)
        .put("lotRows", LOT_ROWS)
        .put("peerRows", PEER_ROWS)
        .put("scope", new JSONObject()
            .put("clients", new JSONArray(List.of(UikQuery.readableClients())))
            .put("orgs", new JSONArray(List.of(UikQuery.readableOrgs()))));
  }

  /** The header, re-read under scope, or null when it is not readable. */
  private JSONObject head(Connection conn, String itemId) throws Exception {
    try (PreparedStatement st = conn.prepareStatement(headSql())) {
      int i = 1;
      i = UikQuery.bindScope(st, i);
      i = UikQuery.bindScope(st, i);
      st.setString(i++, itemId);
      UikQuery.bindScope(st, i);
      try (ResultSet rs = st.executeQuery()) {
        final JSONArray rows = UikQuery.rows(rs,
            UikQuery.str("id", "id"),
            UikQuery.str("code", "code"),
            UikQuery.str("name", "name"),
            UikQuery.str("description", "description"),
            UikQuery.str("categoryId", "category_id"),
            UikQuery.str("category", "category"),
            UikQuery.str("uom", "uom"),
            UikQuery.str("stocked", "stocked"),
            UikQuery.str("attributeSet", "attribute_set"),
            UikQuery.num("qtymin", "qtymin"));
        return rows.length() == 0 ? null : rows.getJSONObject(0);
      }
    }
  }

  private JSONObject totals(Connection conn, String itemId, String warehouse) throws Exception {
    try (PreparedStatement st = conn.prepareStatement(totalsSql())) {
      // id, scope(sd), scope(l), filter pair.
      bindItemTwoScopesFilter(st, itemId, warehouse);
      try (ResultSet rs = st.executeQuery()) {
        final JSONArray rows = UikQuery.rows(rs,
            UikQuery.num("onhand", "onhand"),
            UikQuery.num("reserved", "reserved"),
            UikQuery.num("available", "available"),
            UikQuery.num("locators", "locators"),
            UikQuery.num("warehouses", "warehouses"),
            UikQuery.num("lots", "lots"),
            UikQuery.num("rows", "rows"),
            UikQuery.date("lastInventory", "last_inventory"));
        return rows.length() == 0 ? new JSONObject() : rows.getJSONObject(0);
      }
    }
  }

  private JSONArray worth(Connection conn, String itemId, String warehouse) throws Exception {
    try (PreparedStatement st = conn.prepareStatement(worthSql())) {
      // id, scope(t), scope(l), filter pair.
      bindItemTwoScopesFilter(st, itemId, warehouse);
      try (ResultSet rs = st.executeQuery()) {
        return UikQuery.rows(rs,
            UikQuery.str("currency", "currency"),
            UikQuery.num("unitCost", "unit_cost"),
            UikQuery.num("lines", "lines"),
            UikQuery.date("firstDate", "first_date"),
            UikQuery.date("lastDate", "last_date"));
      }
    }
  }

  private JSONArray warehouses(Connection conn, String itemId) throws Exception {
    try (PreparedStatement st = conn.prepareStatement(warehousesSql())) {
      int i = 1;
      st.setString(i++, itemId);
      i = UikQuery.bindScope(st, i);
      i = UikQuery.bindScope(st, i);
      UikQuery.bindScope(st, i);
      try (ResultSet rs = st.executeQuery()) {
        return UikQuery.rows(rs,
            UikQuery.str("id", "id"),
            UikQuery.str("name", "name"),
            UikQuery.num("onhand", "onhand"),
            UikQuery.num("reserved", "reserved"),
            UikQuery.num("locators", "locators"),
            UikQuery.num("rows", "rows"));
      }
    }
  }

  private JSONArray locators(Connection conn, String itemId, String warehouse) throws Exception {
    try (PreparedStatement st = conn.prepareStatement(locatorsSql())) {
      int i = UikQuery.bindScope(st, 1);
      st.setString(i++, itemId);
      i = UikQuery.bindScope(st, i);
      i = UikQuery.bindScope(st, i);
      i = UikQuery.bindScope(st, i);
      st.setString(i++, warehouse);
      st.setString(i++, warehouse);
      st.setInt(i, LOCATOR_ROWS);
      try (ResultSet rs = st.executeQuery()) {
        return UikQuery.rows(rs,
            UikQuery.str("warehouseId", "warehouse_id"),
            UikQuery.str("warehouse", "warehouse"),
            UikQuery.str("locator", "locator"),
            UikQuery.str("attribute", "attribute"),
            UikQuery.num("onhand", "onhand"),
            UikQuery.num("reserved", "reserved"),
            UikQuery.date("lastInventory", "last_inventory"));
      }
    }
  }

  private JSONArray lots(Connection conn, String itemId, String warehouse) throws Exception {
    try (PreparedStatement st = conn.prepareStatement(lotsSql())) {
      int i = UikQuery.bindScope(st, 1);
      st.setString(i++, itemId);
      i = UikQuery.bindScope(st, i);
      i = UikQuery.bindScope(st, i);
      st.setString(i++, warehouse);
      st.setString(i++, warehouse);
      st.setInt(i, LOT_ROWS);
      try (ResultSet rs = st.executeQuery()) {
        return UikQuery.rows(rs,
            UikQuery.str("label", "label"),
            UikQuery.num("onhand", "onhand"),
            UikQuery.num("locators", "locators"),
            UikQuery.num("rows", "rows"));
      }
    }
  }

  private JSONArray peers(Connection conn, String itemId, String warehouse) throws Exception {
    try (PreparedStatement st = conn.prepareStatement(peersSql())) {
      int i = 1;
      st.setString(i++, itemId);
      i = UikQuery.bindScope(st, i);
      i = UikQuery.bindScope(st, i);
      i = UikQuery.bindScope(st, i);
      st.setString(i++, warehouse);
      st.setString(i++, warehouse);
      i = UikQuery.bindScope(st, i);
      st.setInt(i++, PEER_ROWS);
      st.setString(i, itemId);
      try (ResultSet rs = st.executeQuery()) {
        return UikQuery.rows(rs,
            UikQuery.str("id", "id"),
            UikQuery.str("code", "code"),
            UikQuery.str("name", "name"),
            UikQuery.num("onhand", "onhand"),
            UikQuery.num("rank", "rank"),
            UikQuery.num("peers", "peers"));
      }
    }
  }

  private JSONArray pending(Connection conn, String itemId, String warehouse) throws Exception {
    try (PreparedStatement st = conn.prepareStatement(pendingSql())) {
      // id, scope(ol), scope(o), filter pair.
      bindItemTwoScopesFilter(st, itemId, warehouse);
      try (ResultSet rs = st.executeQuery()) {
        return UikQuery.rows(rs,
            UikQuery.str("period", "period"),
            UikQuery.str("direction", "direction"),
            UikQuery.num("lines", "lines"),
            UikQuery.num("qty", "qty"));
      }
    }
  }

  /**
   * Binds the shape three panels share: the product id, two scope clauses, then the warehouse
   * marker and its value.
   *
   * The two scopes are written out rather than looped, because a loop over a count would hide the
   * number from the check that reads this file to confirm the binds arrive in the order the SQL
   * renders them. The panels that do not have this shape -- the ones with a scope inside a join's
   * ON, and {@code peers}, whose CTEs interleave -- bind by hand next to a comment saying why.
   */
  private int bindItemTwoScopesFilter(PreparedStatement st, String itemId, String warehouse)
      throws Exception {
    int i = 1;
    st.setString(i++, itemId);
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
