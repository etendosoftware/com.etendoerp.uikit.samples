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
 * Datasource ETDEMO_ProductIndex: the rail that chooses whose 360 is on screen.
 *
 * One row per product, not per storage row. That is the opposite grain from the pivot in
 * {@code ETDEMO_Stock}, and it is only defensible because of something that was measured on
 * this instance rather than assumed: no product mixes units of measure. The check was
 *
 * <pre>
 * select count(*) from (select m_product_id from m_storage_detail
 *                        group by 1 having count(distinct c_uom_id) &gt; 1) s;   -- 0
 * </pre>
 *
 * and the same over {@code m_transaction}, also 0. So summing one product's own rows adds
 * comparable numbers. Summing <b>across</b> products stays forbidden, here as everywhere: this
 * datasource has no total row and never will.
 *
 * <h2>Which products the rail lists</h2>
 *
 * Stocked goods that this instance has actually touched -- a storage row or a transaction. On this
 * dataset that is 50 of the 80 rows in {@code m_product}, and the 30 it leaves out are services,
 * expense types and goods that were created and never moved. A 360 of a product with no stock and
 * no history would be ten empty panels, so the rail does not offer one.
 *
 * <h2>The two filters, and what they do to the numbers</h2>
 *
 * The category filter narrows <b>which products are listed</b>. The warehouse filter narrows
 * <b>what the numbers count</b>: with a warehouse chosen, {@code onhand}, {@code locators} and the
 * movement counters answer for that warehouse alone, and a product with nothing there drops out of
 * the list because every figure on its row would be zero. {@code warehouses} is the one column
 * that ignores the filter, on purpose -- it says in how many warehouses the product sits, which is
 * the reason to reach for the filter in the first place.
 *
 * <h2>What this datasource does not do</h2>
 *
 * It does not rank, score or flag. {@code moves} is a count of recorded transactions and
 * {@code lastMove} is the newest of their dates; neither is turned into "fast", "slow" or "dead"
 * here, because those words are business rules and nobody has written them down.
 */
public class ProductIndex extends BaseActionHandler {

  private static final Logger log = LogManager.getLogger();

  /** This datasource's name in the server log. Never returned to the browser. */
  private static final String DATASOURCE = "ETDEMO_ProductIndex";

  /** Whitelisted orderings. User input never reaches the ORDER BY, only one of these keys does. */
  private static final Map<String, String> ORDER = Map.of(
      "code", "code asc",
      "name", "name asc",
      "category", "category asc, code asc",
      "onhand", "onhand desc nulls last, code asc",
      "moves", "moves desc nulls last, code asc",
      "recent", "last_move desc nulls last, code asc");

  private static final String DEFAULT_SORT = "code";

  /** How many columns {@link UikQuery#likeClause(String...)} spans below. */
  private static final int SEARCH_COLUMNS = 3;

  /**
   * Every listable product with its figures, already narrowed by search, category and warehouse.
   *
   * Shared by the page query and the count query so the two cannot disagree about what the rail
   * is. The aggregates are grouped CTEs rather than correlated subqueries: one pass over the
   * storage rows and one over the transactions, instead of two per product.
   *
   * Bind order, which is SQL text order: scope(sd), scope(l), warehouse marker + id;
   * scope(t), scope(l), warehouse marker + id; scope(sw), scope(lw); scope(pc), scope(p),
   * like marker + 3 patterns, category marker + id.
   */
  private static String baseSql() {
    return "with stock as ("
        + " select sd.m_product_id as pid,"
        + "        sum(sd.qtyonhand) as onhand,"
        + "        sum(coalesce(sd.reservedqty, 0)) as reserved,"
        // Un hueco cuenta cuando tiene existencia. Un renglon a cero es historia del inventario,
        // no un sitio donde ir a buscar, y contarlo haria que "3 huecos" no se pareciese a lo que
        // el panel de ubicaciones ensena debajo.
        + "        count(distinct case when sd.qtyonhand <> 0 then sd.m_locator_id end) as locators"
        + " from m_storage_detail sd"
        + "   join m_locator l on l.m_locator_id = sd.m_locator_id"
        + " where " + UikQuery.scopeClause("sd") + " and " + UikQuery.scopeClause("l")
        + "   and (?::text is null or l.m_warehouse_id = ?)"
        + " group by sd.m_product_id"
        + "), moves as ("
        + " select t.m_product_id as pid, max(t.movementdate) as last_move, count(*) as moves"
        + " from m_transaction t"
        + "   join m_locator l on l.m_locator_id = t.m_locator_id"
        + " where " + UikQuery.scopeClause("t") + " and " + UikQuery.scopeClause("l")
        + "   and (?::text is null or l.m_warehouse_id = ?)"
        + " group by t.m_product_id"
        // La cuenta de almacenes es la unica que ignora el filtro: es el dato por el que se abre
        // el filtro, y si respondiese "1" con un almacen elegido no diria nada.
        + "), spread as ("
        + " select sw.m_product_id as pid, count(distinct lw.m_warehouse_id) as warehouses"
        + " from m_storage_detail sw"
        + "   join m_locator lw on lw.m_locator_id = sw.m_locator_id"
        + " where " + UikQuery.scopeClause("sw") + " and " + UikQuery.scopeClause("lw")
        + "   and sw.qtyonhand <> 0"
        + " group by sw.m_product_id"
        + "), det as ("
        + " select p.m_product_id as id, p.value as code, p.name as name,"
        + "        coalesce(pc.m_product_category_id, '') as category_id,"
        + "        coalesce(pc.name, '') as category,"
        + "        coalesce(nullif(trim(u.uomsymbol), ''), u.name, '') as uom,"
        + "        p.qtymin as qtymin,"
        + "        coalesce(s.onhand, 0) as onhand,"
        + "        coalesce(s.reserved, 0) as reserved,"
        + "        coalesce(s.onhand, 0) - coalesce(s.reserved, 0) as available,"
        + "        coalesce(s.locators, 0) as locators,"
        + "        coalesce(sp.warehouses, 0) as warehouses,"
        + "        m.last_move as last_move,"
        + "        coalesce(m.moves, 0) as moves"
        + " from m_product p"
        // La categoria lleva alcance y la unidad no, y la diferencia es deliberada:
        // m_product_category son datos de cliente (esta instancia tiene 13 repartidas entre dos),
        // mientras c_uom es vocabulario, como ad_ref_list. Es tambien lo que hacen las otras siete
        // ventanas del modulo.
        + "   left join m_product_category pc"
        + "     on pc.m_product_category_id = p.m_product_category_id"
        + "        and " + UikQuery.scopeClause("pc")
        + "   left join c_uom u on u.c_uom_id = p.c_uom_id"
        + "   left join stock s on s.pid = p.m_product_id"
        + "   left join moves m on m.pid = p.m_product_id"
        + "   left join spread sp on sp.pid = p.m_product_id"
        + " where " + UikQuery.scopeClause("p")
        + "   and p.producttype = 'I' and p.isactive = 'Y'"
        + "   and " + UikQuery.likeClause("p.value", "p.name", "pc.name")
        + "   and (?::text is null or p.m_product_category_id = ?)"
        // Sin existencias y sin historia no hay 360 que ensenar. Con un almacen elegido esto
        // ademas hace el filtro: las dos CTE ya vienen acotadas a ese almacen.
        + "   and (s.pid is not null or m.pid is not null)"
        + ")";
  }

  /**
   * The category axis for the filter control.
   *
   * It ignores the search box and both filters: the options a filter offers must not depend on
   * what that filter is currently set to, or clearing it would become impossible.
   */
  private static String categoriesSql() {
    return "select pc.m_product_category_id as id, pc.name as name, count(p.m_product_id) as n"
        + " from m_product_category pc"
        + "   join m_product p on p.m_product_category_id = pc.m_product_category_id"
        + "        and " + UikQuery.scopeClause("p")
        + "        and p.producttype = 'I' and p.isactive = 'Y'"
        + " where " + UikQuery.scopeClause("pc")
        + " group by pc.m_product_category_id, pc.name"
        + " having count(p.m_product_id) > 0"
        + " order by pc.name asc";
  }

  /** The warehouse axis, same rule: independent of what is currently filtered. */
  private static String warehousesSql() {
    return "select w.m_warehouse_id as id, w.name as name"
        + " from m_warehouse w where " + UikQuery.scopeClause("w") + " order by w.name asc";
  }

  @Override
  protected JSONObject execute(Map<String, Object> parameters, String content) {
    try {
      final Connection conn = UikQuery.connection();
      final String q = UikQuery.param(parameters, "q");
      final String category = UikQuery.param(parameters, "categoryId");
      final String warehouse = UikQuery.param(parameters, "warehouseId");
      final String requested = UikQuery.param(parameters, "sort");
      // requested is null when the caller omits sort, and Map.of's ImmutableCollections
      // throws on containsKey(null) rather than answering false -- so the null is tested first.
      final String sortKey = requested != null && ORDER.containsKey(requested) ? requested
          : DEFAULT_SORT;
      final int[] window = UikQuery.page(parameters);

      final JSONObject result = new JSONObject();
      result.put("categories", categories(conn));
      result.put("warehouses", warehouses(conn));
      result.put("rows", rows(conn, q, category, warehouse, sortKey, window[0], window[1]));

      final long total = count(conn, q, category, warehouse);
      result.put("page", new JSONObject()
          .put("limit", window[0])
          .put("offset", window[1])
          .put("page", (window[1] / window[0]) + 1)
          .put("total", total)
          .put("pages", Math.max(1, (total + window[0] - 1) / window[0])));
      result.put("meta", new JSONObject()
          .put("productTab", nullSafe(UikQuery.tabFor(conn, Product360.PRODUCT_WINDOW, "m_product")))
          .put("sort", sortKey)
          .put("q", q == null ? "" : q)
          .put("categoryId", category == null ? "" : category)
          .put("warehouseId", warehouse == null ? "" : warehouse)
          .put("scope", new JSONObject()
              .put("clients", new JSONArray(List.of(UikQuery.readableClients())))
              .put("orgs", new JSONArray(List.of(UikQuery.readableOrgs())))));
      return result;
    } catch (Exception e) {
      log.error("{} failed: {}", DATASOURCE, e.getMessage(), e);
      return Product360.error(e);
    }
  }

  private JSONArray categories(Connection conn) throws Exception {
    try (PreparedStatement st = conn.prepareStatement(categoriesSql())) {
      int i = UikQuery.bindScope(st, 1);
      UikQuery.bindScope(st, i);
      try (ResultSet rs = st.executeQuery()) {
        return UikQuery.rows(rs, UikQuery.str("id", "id"), UikQuery.str("name", "name"),
            UikQuery.num("n", "n"));
      }
    }
  }

  private JSONArray warehouses(Connection conn) throws Exception {
    try (PreparedStatement st = conn.prepareStatement(warehousesSql())) {
      UikQuery.bindScope(st, 1);
      try (ResultSet rs = st.executeQuery()) {
        return UikQuery.rows(rs, UikQuery.str("id", "id"), UikQuery.str("name", "name"));
      }
    }
  }

  private JSONArray rows(Connection conn, String q, String category, String warehouse,
      String sortKey, int limit, int offset) throws Exception {
    final String sql = baseSql() + " select * from det order by " + ORDER.get(sortKey)
        + " limit ? offset ?";
    try (PreparedStatement st = conn.prepareStatement(sql)) {
      int i = bindBase(st, q, category, warehouse);
      st.setInt(i++, limit);
      st.setInt(i, offset);
      try (ResultSet rs = st.executeQuery()) {
        return UikQuery.rows(rs,
            UikQuery.str("id", "id"),
            UikQuery.str("code", "code"),
            UikQuery.str("name", "name"),
            UikQuery.str("categoryId", "category_id"),
            UikQuery.str("category", "category"),
            UikQuery.str("uom", "uom"),
            UikQuery.num("qtymin", "qtymin"),
            UikQuery.num("onhand", "onhand"),
            UikQuery.num("reserved", "reserved"),
            UikQuery.num("available", "available"),
            UikQuery.num("locators", "locators"),
            UikQuery.num("warehouses", "warehouses"),
            UikQuery.num("moves", "moves"),
            UikQuery.date("lastMove", "last_move"));
      }
    }
  }

  private long count(Connection conn, String q, String category, String warehouse)
      throws Exception {
    try (PreparedStatement st = conn.prepareStatement(baseSql() + " select count(*) from det")) {
      bindBase(st, q, category, warehouse);
      return UikQuery.total(st);
    }
  }

  /**
   * Fills the shared prefix of every query built on {@code baseSql()} and returns the next free
   * index. The order here is the order the SQL renders, and the two have to be read together.
   */
  private int bindBase(PreparedStatement st, String q, String category, String warehouse)
      throws Exception {
    int i = 1;
    // stock: scope(sd), scope(l), then the warehouse marker and its value.
    i = UikQuery.bindScope(st, i);
    i = UikQuery.bindScope(st, i);
    st.setString(i++, warehouse);
    st.setString(i++, warehouse);
    // moves: scope(t), scope(l), same warehouse pair.
    i = UikQuery.bindScope(st, i);
    i = UikQuery.bindScope(st, i);
    st.setString(i++, warehouse);
    st.setString(i++, warehouse);
    // spread: scope(sw), scope(lw). No warehouse pair -- that is the point of this CTE.
    i = UikQuery.bindScope(st, i);
    i = UikQuery.bindScope(st, i);
    // det: scope(pc) inside the join's ON, then scope(p) in the where.
    i = UikQuery.bindScope(st, i);
    i = UikQuery.bindScope(st, i);
    i = UikQuery.bindLike(st, i, q, SEARCH_COLUMNS);
    // The marker and the value are the same string twice: null leaves the clause inert.
    st.setString(i++, category);
    st.setString(i++, category);
    return i;
  }

  private Object nullSafe(String value) {
    return value == null ? JSONObject.NULL : value;
  }

}
