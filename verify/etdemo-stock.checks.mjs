/*
 * Window-specific gates for ETDEMO_Stock. What is true of this window and of no other is the
 * promise that nothing is filtered, sorted, paged or totalled in the browser, so every gate asks
 * the datasource and the database, never the DOM. meta.scope carries the session's readable clients
 * and organizations, so the independent SQL below sees exactly the rows the handler was allowed to
 * see: the comparison is about arithmetic, not about permissions. W5 search, W6 paging, W8 axis,
 * W9 arithmetic -- W1..W4 and W7 belong to check-window.mjs.
 */
const SRC = 'com.etendoerp.uikit.samples.stock.StockPivot';
const lit = (v) => `'${String(v).replace(/'/g, "''")}'`;
const list = (v) => (v && v.length ? v.map(lit).join(',') : 'null');
const ids = (rows) => rows.map((r) => r.id);
const near = (a, b) => Math.abs(Number(a) - Number(b)) < 1e-6;
const call = (action, params) =>
  action(SRC, Object.assign({ q: 'null', page: 1, limit: 200, zeros: 'N', sort: 'code' }, params));
const done = (pass, fail, id, name, bad, ok) =>
  (bad.length ? fail(id, name, bad.join('; ')) : pass(id, name, ok));

/** The handler's two CTEs, written again here straight from the physical tables. */
function base(meta, q) {
  const scope = (a) => `${a}.ad_client_id in (${list(meta.scope.clients)})`
    + ` and ${a}.ad_org_id in (${list(meta.scope.orgs)}) and ${a}.isactive = 'Y'`;
  const like = q ? `(p.value ilike ${lit(`%${q}%`)} or p.name ilike ${lit(`%${q}%`)})` : '1=1';
  return `with det as (select sd.m_product_id prod, l.m_warehouse_id wh, sd.qtyonhand qty
    from m_storage_detail sd join m_locator l on l.m_locator_id = sd.m_locator_id
      join m_warehouse w on w.m_warehouse_id = l.m_warehouse_id
    where ${scope('sd')} and ${scope('w')}),
  prod as (select d.prod id, p.value code, sum(d.qty) total from det d
    join m_product p on p.m_product_id = d.prod
    where ${like} group by 1, 2 having sum(d.qty) <> 0)`;
}

/** W5: the ilike runs in SQL. The row sets narrow, and an independent count agrees. */
async function gateSearch({ action, query, pass, fail, skip }) {
  const all = await call(action);
  if (all.page.total < 2) return skip('W5', 'busqueda en SQL', 'hacen falta dos productos');
  const universe = new Set(ids(all.rows));
  const bad = [];
  let used = 0;
  for (const q of [all.rows[0].code.slice(0, 3), all.rows[0].code]) {
    const one = await call(action, { q });
    const kept = new Set(ids(one.rows));
    if (kept.size === 0 || kept.size >= universe.size) continue;
    used += 1;
    for (const id of kept) if (!universe.has(id)) bad.push(`q=${q} devolvio ${id}, ajeno`);
    const [[n]] = query(`${base(all.meta, q)} select count(*) from prod`);
    if (Number(n) !== one.page.total || one.page.total !== kept.size) {
      bad.push(`q=${q}: total ${one.page.total}, filas ${kept.size}, SQL ${n}`);
    }
  }
  if (used === 0) bad.push('ninguna sonda estrecho: la busqueda no filtra en SQL');
  return done(pass, fail, 'W5', 'busqueda en SQL', bad, `${used} sonda(s) estrecharon el conjunto `
    + `de ${all.page.total} productos y el recuento independiente coincide`);
}

/** W6: limit/offset belong to the server. Two pages are disjoint and total is its own count. */
async function gatePaging({ action, query, pass, fail, skip }) {
  const all = await call(action);
  if (all.page.total < 4) return skip('W6', 'paginacion en servidor', 'hacen falta 4 productos');
  const p1 = await call(action, { page: 1, limit: 2 });
  const p2 = await call(action, { page: 2, limit: 2 });
  const bad = [];
  if (p1.rows.length !== 2 || p1.page.limit !== 2) bad.push('la pagina 1 no respeta limit=2');
  const first = new Set(ids(p1.rows));
  const shared = ids(p2.rows).filter((id) => first.has(id));
  if (shared.length) bad.push(`las paginas 1 y 2 comparten ${shared.length} producto(s)`);
  const [[n]] = query(`${base(all.meta, null)} select count(*) from prod`);
  if (Number(n) !== p1.page.total) bad.push(`page.total ${p1.page.total}, count(*) ${n}`);
  return done(pass, fail, 'W6', 'paginacion en servidor', bad, `paginas de 2 disjuntas sobre `
    + `${p1.page.total} productos en ${p1.page.pages} paginas, total = count(*)`);
}

/** W8: the asymmetry the design promises -- the axis does not move when the filter does. */
async function gateAxis({ action, query, pass, fail }) {
  const all = await call(action);
  const axis = ids(all.warehouses).join(',');
  const bad = [];
  const probes = [{ q: all.rows[0].code }, { page: 2, limit: 1 }, { zeros: 'Y' }, { sort: 'qty' }];
  for (const p of probes) {
    const got = ids((await call(action, p)).warehouses).join(',');
    if (got !== axis) bad.push(`${JSON.stringify(p)} movio el eje: ${got}`);
  }
  const rows = query(`${base(all.meta, null)} select d.wh from det d
    join m_warehouse w on w.m_warehouse_id = d.wh group by 1, w.name order by w.name`);
  if (rows.map((r) => r[0]).join(',') !== axis) bad.push('el eje no es el de la base sin filtro');
  return done(pass, fail, 'W8', 'eje de almacenes', bad, `${all.warehouses.length} almacenes, `
    + 'identicos con q, con pagina, con zeros y con sort');
}

/** W9: row totals, cell sums, column totals and the product count, all recomputed in SQL. */
async function gateArithmetic({ action, query, pass, fail }) {
  const page = await call(action, { page: 1, limit: 5 });
  const bad = [];
  const totals = new Map(query(`${base(page.meta, null)} select id, total from prod`)
    .map((r) => [r[0], Number(r[1])]));
  for (const row of page.rows) {
    if (!near(row.total, totals.get(row.id))) bad.push(`${row.code}: total ${row.total} != SQL`);
    const sum = page.warehouses.reduce((a, w) => a + (row.cells[w.id] || 0), 0);
    if (!near(sum, row.total)) bad.push(`${row.code}: celdas suman ${sum}, no ${row.total}`);
  }
  const cols = new Map(query(`${base(page.meta, null)} select d.wh, sum(d.qty) from det d
    join prod pr on pr.id = d.prod group by 1`).map((r) => [r[0], Number(r[1])]));
  for (const col of page.colTotals) {
    if (!near(col.total, cols.get(col.id))) bad.push(`columna ${col.id}: ${col.total} != SQL`);
  }
  if (cols.size !== page.colTotals.length) bad.push('colTotals no cubre todas las columnas');
  const [[n, grand]] = query(`${base(page.meta, null)}
    select count(*), coalesce(sum(total), 0) from prod`);
  if (Number(n) !== page.summary.products) bad.push(`products ${page.summary.products} != ${n}`);
  if (!near(grand, page.summary.grand)) bad.push(`grand ${page.summary.grand} != ${grand}`);
  const colSum = page.colTotals.reduce((a, c) => a + c.total, 0);
  if (!near(colSum, page.summary.grand)) bad.push(`las columnas suman ${colSum}, no el gran total`);
  return done(pass, fail, 'W9', 'aritmetica del pivote', bad, `${page.rows.length} filas, `
    + `${page.colTotals.length} columnas y ${n} productos (total ${grand}) coinciden`);
}

export default async function (ctx) {
  for (const gate of [gateSearch, gatePaging, gateAxis, gateArithmetic]) await gate(ctx);
}
