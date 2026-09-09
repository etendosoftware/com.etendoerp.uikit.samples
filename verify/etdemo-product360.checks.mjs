/*
 * Window-specific gates for ETDEMO_Product360. The promise here is a derivation, not a layout: the
 * ledger is not an illustration of the stock figure, it is where that figure comes from, so its
 * closing balance has to be the header's on-hand -- with the warehouse filter on as well as off.
 * The second promise is the asymmetry of that filter: it narrows seven panels and deliberately
 * does not narrow the one panel that is the control for setting it. So the gates ask the three
 * datasources and the database, never the DOM -- and never the browser: which aliases were
 * actually fetched is not observable from the server, so that proof belongs to the runtime harness
 * and the doc says so. meta.scope carries the session's readable clients and orgs, so the SQL below
 * sees exactly the handler's rows: the comparison is about arithmetic, not permissions. W5 the
 * ledger against the header, W6 the filter, W8 the rail, W9 the neutral shape, W10 the tabs;
 * W1..W4 and W7 belong to check-window.mjs.
 */
const INDEX = 'com.etendoerp.uikit.samples.product360.ProductIndex';
const STOCK = 'com.etendoerp.uikit.samples.product360.ProductStock';
const LEDGER = 'com.etendoerp.uikit.samples.product360.ProductLedger';
const lit = (v) => `'${String(v).replace(/'/g, "''")}'`;
const list = (v) => (v && v.length ? v.map(lit).join(',') : 'null');
const ids = (rows) => rows.map((r) => r.id);
const near = (a, b) => Math.abs(Number(a) - Number(b)) < 0.005;
const done = (pass, fail, id, name, bad, ok) =>
  (bad.length ? fail(id, name, bad.join('; ')) : pass(id, name, ok));
const scope = (meta, a) => `${a}.ad_client_id in (${list(meta.scope.clients)}) and `
  + `${a}.ad_org_id in (${list(meta.scope.orgs)}) and ${a}.isactive = 'Y'`;
/** The warehouse filter, written again: null leaves it inert, like the handler's marker. */
const only = (wh, a) => (wh ? ` and ${a}.m_warehouse_id = ${lit(wh)}` : '');
/** The on-hand of one product, from the storage rows. */
const onhandSql = (meta, id, wh) => `select coalesce(sum(sd.qtyonhand), 0) from m_storage_detail sd
  join m_locator l on l.m_locator_id = sd.m_locator_id
  where sd.m_product_id = ${lit(id)} and ${scope(meta, 'sd')}
    and ${scope(meta, 'l')}${only(wh, 'l')}`;
/** The same quantity from the other side: the signed sum of every readable movement. */
const movedSql = (meta, id, wh) => `select coalesce(sum(t.movementqty), 0) from m_transaction t
  join m_locator l on l.m_locator_id = t.m_locator_id
  where t.m_product_id = ${lit(id)} and ${scope(meta, 't')}
    and ${scope(meta, 'l')}${only(wh, 'l')}`;
/** The rail's own CTEs: every stocked or moved product in scope, narrowed as the handler does. */
const railSql = (meta, q) => `with stock as (
    select sd.m_product_id pid from m_storage_detail sd
      join m_locator l on l.m_locator_id = sd.m_locator_id
      where ${scope(meta, 'sd')} and ${scope(meta, 'l')} group by sd.m_product_id),
  moves as (
    select t.m_product_id pid from m_transaction t
      join m_locator l on l.m_locator_id = t.m_locator_id
      where ${scope(meta, 't')} and ${scope(meta, 'l')} group by t.m_product_id),
  det as (select p.m_product_id id from m_product p
    left join m_product_category pc on pc.m_product_category_id = p.m_product_category_id
      and ${scope(meta, 'pc')}
    left join stock s on s.pid = p.m_product_id
    left join moves m on m.pid = p.m_product_id
    where ${scope(meta, 'p')} and p.producttype = 'I' and p.isactive = 'Y'
      and (s.pid is not null or m.pid is not null) and ${q
    ? `(p.value ilike ${lit(`%${q}%`)} or p.name ilike ${lit(`%${q}%`)}`
      + ` or pc.name ilike ${lit(`%${q}%`)})` : '1=1'})`;
/** The product with the most movements: the ledger is only worth checking where there is one. */
const busiest = async (action) => {
  const rail = await action(INDEX, { sort: 'moves', page: 1, limit: 5 });
  return rail.rows.length && rail.rows[0].moves > 0 ? rail.rows[0] : null;
};
/** limit and offset belong to the server: page 1 is capped, and page 2 repeats nothing. */
async function paged(action, src, key, base, limit) {
  const p1 = await action(src, Object.assign({}, base, { page: 1, limit }));
  const p2 = await action(src, Object.assign({}, base, { page: 2, limit }));
  const first = new Set(ids(p1[key]));
  return (p1.page.limit !== limit || p1[key].length > limit ? [`no respeta limit=${limit}`] : [])
    .concat(ids(p2[key]).some((id) => first.has(id)) ? ['las paginas 1 y 2 se solapan'] : []);
}

/**
 * W5: the ledger derives the header. The closing balance of the accumulated series is the on-hand
 * at the top, both figures are recomputed from their own table, and the identity survives the
 * warehouse filter -- which is the only proof that the two halves narrow by the same rule.
 */
async function gateBalance({ action, query, pass, fail, skip }) {
  const top = await busiest(action);
  if (!top) return skip('W5', 'el rastro deriva la cabecera', 'ningun producto con movimientos');
  const item = await action(STOCK, { itemId: top.id });
  const led = await action(LEDGER, { itemId: top.id });
  const bad = [];
  const check = (label, stock, ledger, wh) => {
    const last = ledger.series.length ? ledger.series[ledger.series.length - 1].balance : 0;
    const [[sql]] = query(onhandSql(item.meta, top.id, wh));
    const [[moved]] = query(movedSql(item.meta, top.id, wh));
    if (!near(stock.totals.onhand, sql)) {
      bad.push(`${label}: en mano ${stock.totals.onhand} != SQL ${sql}`);
    }
    if (!near(last, moved)) bad.push(`${label}: cierre ${last} != suma de movimientos ${moved}`);
    if (!near(last, stock.totals.onhand)) {
      bad.push(`${label}: cierre ${last} != en mano ${stock.totals.onhand}`);
    }
  };
  check('total', item, led, null);
  const held = item.warehouses.filter((w) => Number(w.onhand) !== 0);
  for (const w of held.slice(0, 3)) {
    const one = await action(STOCK, { itemId: top.id, warehouseId: w.id });
    const oneLed = await action(LEDGER, { itemId: top.id, warehouseId: w.id });
    check(w.name, one, oneLed, w.id);
    if (!near(one.totals.onhand, w.onhand)) {
      bad.push(`${w.name}: filtrado ${one.totals.onhand} != su fila del panel ${w.onhand}`);
    }
  }
  const grains = await Promise.all(['year', 'month', 'no-such-grain']
    .map((grain) => action(LEDGER, { itemId: top.id, grain })));
  for (const g of grains) {
    const last = g.series.length ? g.series[g.series.length - 1].balance : 0;
    if (!near(last, item.totals.onhand)) bad.push(`grain=${g.meta.grain}: cierre ${last}`);
    if (!['year', 'month'].includes(g.meta.grain)) bad.push('grain fuera del whitelist');
  }
  return done(pass, fail, 'W5', 'el rastro deriva la cabecera', bad, `${top.code}: el acumulado de `
    + `${led.series.length} periodos cierra en ${item.totals.onhand} = sum(qtyonhand) = `
    + `sum(movementqty), igual en ${Math.min(held.length, 3)} almacenes y en los dos grains `
    + 'del whitelist');
}

/**
 * W6: the warehouse filter narrows everything except the panel that sets it. The axes of the rail
 * follow the same rule -- a filter whose options depend on its own value cannot be cleared.
 */
async function gateFilter({ action, query, pass, fail, skip }) {
  const top = await busiest(action);
  if (!top) return skip('W6', 'el filtro no toca su propio eje', 'ningun producto con movimientos');
  const item = await action(STOCK, { itemId: top.id });
  const held = item.warehouses.filter((w) => Number(w.onhand) !== 0);
  if (!held.length) return skip('W6', 'el filtro no toca su propio eje', 'sin almacen con stock');
  const wh = held[0];
  const one = await action(STOCK, { itemId: top.id, warehouseId: wh.id });
  const bad = [];
  if (JSON.stringify(one.warehouses) !== JSON.stringify(item.warehouses)) {
    bad.push('el filtro movio el panel de almacenes, que es el propio filtro');
  }
  for (const row of one.locators) {
    if (row.warehouseId !== wh.id) bad.push(`ubicacion de ${row.warehouse}, ajena al filtro`);
  }
  const [[locs]] = query(`select count(*) from m_storage_detail sd
    join m_locator l on l.m_locator_id = sd.m_locator_id
    where sd.m_product_id = ${lit(top.id)} and ${scope(item.meta, 'sd')}
      and ${scope(item.meta, 'l')} and l.m_warehouse_id = ${lit(wh.id)}`);
  if (one.locators.length !== Math.min(Number(locs), one.meta.locatorRows)) {
    bad.push(`ubicaciones ${one.locators.length} != SQL ${locs} (tope ${one.meta.locatorRows})`);
  }
  const lots = one.lots.reduce((a, r) => a + Number(r.onhand), 0);
  if (!near(lots, one.totals.onhand)) bad.push(`los lotes suman ${lots} != ${one.totals.onhand}`);
  const trail = await action(LEDGER, { itemId: top.id, warehouseId: wh.id, page: 1, limit: 50 });
  for (const row of trail.trail) {
    if (row.warehouseId !== wh.id) bad.push(`el rastro trajo ${row.warehouse}, ajeno al filtro`);
  }
  const base = await action(INDEX, { page: 1, limit: 1 });
  for (const params of [{ warehouseId: wh.id }, { categoryId: top.categoryId }, { q: top.code }]) {
    const axes = await action(INDEX, Object.assign({ page: 1, limit: 1 }, params));
    if (JSON.stringify(axes.categories) !== JSON.stringify(base.categories)) {
      bad.push(`${JSON.stringify(params)} movio el eje de categorias`);
    }
    if (JSON.stringify(axes.warehouses) !== JSON.stringify(base.warehouses)) {
      bad.push(`${JSON.stringify(params)} movio el eje de almacenes`);
    }
  }
  return done(pass, fail, 'W6', 'el filtro no toca su propio eje', bad, `con ${wh.name} elegido: `
    + `${one.locators.length} ubicaciones y ${trail.trail.length} movimientos del almacen y de `
    + `ningun otro, lotes que suman ${one.totals.onhand}, y los tres ejes (almacenes del producto, `
    + 'categorias y almacenes del carril) intactos');
}

/** W8: the rail filters, orders and pages on the server, and its total is count(*). */
async function gateRail({ action, query, pass, fail, skip }) {
  const all = await action(INDEX, { page: 1, limit: 200 });
  if (all.page.total < 4) return skip('W8', 'carril en servidor', 'hacen falta 4 productos');
  const bad = [];
  const [[n]] = query(`${railSql(all.meta, null)} select count(*) from det`);
  if (Number(n) !== all.page.total) bad.push(`total ${all.page.total} != count(*) ${n}`);
  const universe = new Set(ids(all.rows));
  const q = all.rows[0].code.slice(0, 3);
  const one = await action(INDEX, { q, page: 1, limit: 200 });
  const kept = new Set(ids(one.rows));
  if (!kept.size || kept.size >= universe.size) bad.push(`q=${q} no estrecho el carril`);
  for (const id of kept) if (!universe.has(id)) bad.push(`q=${q} devolvio ${id}, ajeno`);
  const [[m]] = query(`${railSql(all.meta, q)} select count(*) from det`);
  if (Number(m) !== one.page.total) bad.push(`q=${q}: total ${one.page.total} != SQL ${m}`);
  bad.push(...await paged(action, INDEX, 'rows', {}, 2));
  const sorted = await action(INDEX, { sort: 'onhand', page: 1, limit: 200 });
  for (let i = 1; i < sorted.rows.length; i += 1) {
    if (Number(sorted.rows[i - 1].onhand) < Number(sorted.rows[i].onhand)) {
      bad.push('sort=onhand no vino ordenado del servidor');
      break;
    }
  }
  const fallback = await action(INDEX, { sort: 'drop table', page: 1, limit: 1 });
  if (fallback.meta.sort !== 'code') {
    bad.push(`un orden fuera del whitelist quedo en ${fallback.meta.sort}`);
  }
  return done(pass, fail, 'W8', 'carril en servidor', bad, `${all.page.total} productos = `
    + `count(*), q=${q} dejo ${kept.size}, paginas de 2 disjuntas, sort=onhand en SQL y un orden `
    + 'inventado cae en code');
}

/** W9: no product asked for, no such product and a product out of scope answer the same. */
async function gateNeutral({ action, pass, fail }) {
  const bad = [];
  for (const params of [{}, { itemId: '' }, { itemId: 'NO-SUCH-PRODUCT-ID' }]) {
    const label = JSON.stringify(params);
    const item = await action(STOCK, params);
    if (item.error) bad.push(`${label}: error ${item.error.message}`);
    if (item.head !== null) bad.push(`${label}: devolvio cabecera`);
    for (const key of ['worth', 'warehouses', 'locators', 'lots', 'peers', 'pending']) {
      if (!Array.isArray(item[key]) || item[key].length) bad.push(`${label}: ${key} con filas`);
    }
    if (!item.meta || item.meta.asOf === undefined) bad.push(`${label}: sin meta.asOf`);
    const led = await action(LEDGER, params);
    if (led.error) bad.push(`${label}: ledger error ${led.error.message}`);
    for (const key of ['series', 'mix', 'trail']) {
      if (!Array.isArray(led[key]) || led[key].length) bad.push(`${label}: ${key} con filas`);
    }
    if (led.page.total !== 0) bad.push(`${label}: ledger con total ${led.page.total}`);
  }
  return done(pass, fail, 'W9', 'forma neutra sin producto', bad, 'sin producto, con el id vacio y '
    + 'con un id inventado: 200 con cabecera null, ocho paneles vacios y meta completo, las tres '
    + 'indistinguibles');
}

/** W10: every tab id came from the dictionary, and shipment and receipt are not the same. */
async function gateTabs({ action, query, pass, fail }) {
  const led = await action(LEDGER, {});
  const item = await action(STOCK, {});
  const meta = led.meta;
  const bad = [];
  const table = (id) => query(`select lower(t.tablename) from ad_tab b
    join ad_table t on t.ad_table_id = b.ad_table_id
    where b.ad_tab_id = ${lit(id)} and b.isactive = 'Y'`);
  const want = [['productTab', 'm_product'], ['movementTab', 'm_movement'],
    ['shipmentTab', 'm_inout'], ['receiptTab', 'm_inout'], ['inventoryTab', 'm_inventory']];
  for (const [key, tbl] of want) {
    const rows = meta[key] ? table(meta[key]) : [];
    if (!meta[key]) bad.push(`${key}: sin ad_tab_id`);
    else if (!rows.length) bad.push(`${key}: ${meta[key]} no existe en ad_tab`);
    else if (rows[0][0] !== tbl) bad.push(`${key}: ${meta[key]} es de ${rows[0][0]}`);
  }
  if (meta.shipmentTab && meta.shipmentTab === meta.receiptTab) {
    bad.push('albaran y albaran de compra comparten pestana');
  }
  if (item.meta.productTab !== meta.productTab) {
    bad.push('los dos datasources no ven la misma ficha');
  }
  return done(pass, fail, 'W10', 'pestanas resueltas en SQL', bad, '5 ad_tab_id reales sobre su '
    + `propia tabla (producto=${meta.productTab}, movimiento=${meta.movementTab}, `
    + `albaran=${meta.shipmentTab}, recepcion=${meta.receiptTab}, `
    + `inventario=${meta.inventoryTab}), y albaran distinto de recepcion`);
}

export default async function (ctx) {
  for (const gate of [gateBalance, gateFilter, gateRail, gateNeutral, gateTabs]) await gate(ctx);
}
