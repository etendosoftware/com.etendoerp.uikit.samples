/*
 * Window-specific gates for ETDEMO_Partner360. The promise here is an asymmetry, not a layout: the
 * header counts every document of the partner whatever the active tab is, only the document list
 * narrows, and the directory ignores both. So the gates ask the three datasources and the database,
 * never the DOM -- and never the browser: which aliases were actually fetched is not observable
 * from the server, so that proof belongs to the runtime harness and the doc says so. meta.scope
 * carries the session's readable clients and orgs, so the SQL below sees exactly the handler's
 * rows: the comparison is about arithmetic, not permissions. W5 the header, W6 the list, W8 the
 * directory, W10 the tabs; W1..W4 and W7 belong to check-window.mjs.
 */
const LIST = 'com.etendoerp.uikit.samples.partner360.Directory';
const HEAD = 'com.etendoerp.uikit.samples.partner360.PartnerHead';
const DOCS = 'com.etendoerp.uikit.samples.partner360.PartnerDocs';
const KINDS = [['so', 'c_order', 'grandtotal', 'issotrx', 'Y'],
  ['po', 'c_order', 'grandtotal', 'issotrx', 'N'],
  ['si', 'c_invoice', 'grandtotal', 'issotrx', 'Y'],
  ['pi', 'c_invoice', 'grandtotal', 'issotrx', 'N'],
  ['rc', 'fin_payment', 'amount', 'isreceipt', 'Y'],
  ['pm', 'fin_payment', 'amount', 'isreceipt', 'N']].map(([k, t, a, c, v]) => ({ k, t, a, c, v }));
const lit = (v) => `'${String(v).replace(/'/g, "''")}'`;
const list = (v) => (v && v.length ? v.map(lit).join(',') : 'null');
const ids = (rows) => rows.map((r) => r.id);
const done = (pass, fail, id, name, bad, ok) =>
  (bad.length ? fail(id, name, bad.join('; ')) : pass(id, name, ok));
const scope = (meta, a) => `${a}.ad_client_id in (${list(meta.scope.clients)}) and `
  + `${a}.ad_org_id in (${list(meta.scope.orgs)}) and ${a}.isactive = 'Y'`;
/** The handler's predicate for one kind, written again from the physical table. */
const from = (meta, kind, bp) => `from ${kind.t} d where d.c_bpartner_id = ${lit(bp)} and `
  + `d.${kind.c} = ${lit(kind.v)} and ${scope(meta, 'd')}`;
/** The directory's own CTEs: every partner in scope, with its document count. */
const dirSql = (meta, q) => `with doc as (
    select o.c_bpartner_id bp from c_order o where ${scope(meta, 'o')}
    union all select i.c_bpartner_id from c_invoice i where ${scope(meta, 'i')}
    union all select p.c_bpartner_id from fin_payment p where ${scope(meta, 'p')}),
  cnt as (select bp, count(*) n from doc group by bp),
  part as (select b.c_bpartner_id id from c_bpartner b
    left join cnt c on c.bp = b.c_bpartner_id where ${scope(meta, 'b')} and ${q
    ? `(b.value ilike ${lit(`%${q}%`)} or b.name ilike ${lit(`%${q}%`)}`
      + ` or b.taxid ilike ${lit(`%${q}%`)})` : '1=1'})`;
/** The partner with most documents: the file is only worth checking where there is one. */
const busiest = async (action) => {
  const dir = await action(LIST, { page: 1, limit: 5 });
  return dir.rows.length && dir.rows[0].docs > 0 ? dir.rows[0].id : null;
};
/** limit and offset belong to the server: page 1 is capped, and page 2 repeats nothing. */
async function paged(action, src, base, limit) {
  const p1 = await action(src, Object.assign({}, base, { page: 1, limit }));
  const p2 = await action(src, Object.assign({}, base, { page: 2, limit }));
  const first = new Set(ids(p1.rows));
  return (p1.page.limit !== limit || p1.rows.length > limit ? [`no respeta limit=${limit}`] : [])
    .concat(ids(p2.rows).some((id) => first.has(id)) ? ['las paginas 1 y 2 se solapan'] : []);
}

/**
 * W5: the header is the whole partner. Every count and sum is recomputed from the tables, the
 * active tab cannot move one, and with no partner the answer is neutral instead of everybody's.
 */
async function gateHead({ action, query, pass, fail, skip }) {
  const bp = await busiest(action);
  if (!bp) return skip('W5', 'cabecera del tercero', 'ningun tercero con documentos');
  const head = await action(HEAD, { bp });
  const byKind = new Map(head.totals.map((t) => [t.tab, t]));
  const bad = [];
  let seen = 0;
  for (const kind of KINDS) {
    const got = byKind.get(kind.k);
    if (!got) { bad.push(`falta la pestana ${kind.k}`); continue; }
    const [[n, amt, curs]] = query(`select count(*), coalesce(sum(d.${kind.a}), 0),
      count(distinct d.c_currency_id) ${from(head.meta, kind, bp)}`);
    if (Number(n) !== got.count) bad.push(`${kind.k}: count ${got.count} != SQL ${n}`);
    if (Number(curs) === 1 && Math.abs(got.amount - amt) > 0.005) {
      bad.push(`${kind.k}: importe ${got.amount} != SQL ${amt}`);
    }
    if (Number(curs) > 1 && got.amount !== null) bad.push(`${kind.k}: suma ${curs} monedas`);
    seen += Number(n) > 0 ? 1 : 0;
  }
  const shape = JSON.stringify(head.totals);
  for (const tab of ['sum', 'so', 'pm']) {
    const other = await action(HEAD, { bp, tab, page: 3, limit: 1 });
    if (JSON.stringify(other.totals) !== shape) bad.push(`tab=${tab} movio los totales`);
  }
  for (const params of [{}, { bp: '' }, { bp: 'NO-SUCH-PARTNER-ID' }]) {
    const empty = await action(HEAD, params);
    const label = JSON.stringify(params);
    if (empty.error) bad.push(`${label}: error ${empty.error.message}`);
    if (empty.partner !== null) bad.push(`${label}: devolvio un tercero`);
    if (!Array.isArray(empty.totals) || empty.totals.length) bad.push(`${label}: totales`);
    if (!empty.meta || !empty.meta.tabs) bad.push(`${label}: sin meta.tabs`);
  }
  return done(pass, fail, 'W5', 'cabecera del tercero', bad, `${head.totals.length} pestanas del `
    + `tercero ${bp} (${seen} con documentos) = count(*)/sum(), ajenas a la pestana activa, y sin `
    + 'tercero: 200 con partner null y totales vacios');
}

/** W6: only the list narrows -- per tab, in SQL, disjoint, sized by the header, paged on server. */
async function gateNarrow({ action, query, pass, fail, skip }) {
  const bp = await busiest(action);
  if (!bp) return skip('W6', 'la lista estrecha en SQL', 'ningun tercero con documentos');
  const head = await action(HEAD, { bp });
  const seen = new Map();
  const bad = [];
  let live = 0;
  for (const total of head.totals) {
    const kind = KINDS.find((x) => x.k === total.tab);
    const page = await action(DOCS, { bp, tab: total.tab, page: 1, limit: 200 });
    if (page.page.total !== total.count) {
      bad.push(`${total.tab}: docs ${page.page.total} != head ${total.count}`);
    }
    if (page.rows.length) {
      live += 1;
      const [[n]] = query(`select count(*) ${from(head.meta, kind, bp)}
        and d.${kind.t}_id in (${list(ids(page.rows))})`);
      if (Number(n) !== page.rows.length) bad.push(`${total.tab}: filas ajenas a la pestana`);
    }
    for (const id of ids(page.rows)) {
      if (seen.has(id)) bad.push(`${id} sale en ${seen.get(id)} y en ${total.tab}`);
      seen.set(id, total.tab);
    }
  }
  for (const params of [{ bp: '', tab: 'so' }, { bp, tab: 'no-such-tab' }]) {
    const off = await action(DOCS, params);
    if (off.error) bad.push(`${JSON.stringify(params)}: error ${off.error.message}`);
    if (off.rows.length || off.page.total) bad.push(`${JSON.stringify(params)}: devolvio filas`);
  }
  bad.push(...await paged(action, DOCS, { bp, tab: head.totals[0].tab }, 3));
  return done(pass, fail, 'W6', 'la lista estrecha en SQL', bad, `${seen.size} documentos en `
    + `${live} pestanas con filas, disjuntas, cada tamano = su total de cabecera; sin tercero o `
    + 'con pestana desconocida, cero filas');
}

/** W8: the directory ignores the partner and the tab, and filters and pages on the server. */
async function gateDirectory({ action, query, pass, fail, skip }) {
  const all = await action(LIST, { page: 1, limit: 200 });
  if (all.page.total < 4) return skip('W8', 'directorio en servidor', 'hacen falta 4 terceros');
  const bad = [];
  const [[n]] = query(`${dirSql(all.meta, null)} select count(*) from part`);
  if (Number(n) !== all.page.total) bad.push(`total ${all.page.total} != count(*) ${n}`);
  const universe = new Set(ids(all.rows));
  const q = all.rows[0].code.slice(0, 3);
  const one = await action(LIST, { q, page: 1, limit: 200 });
  const kept = new Set(ids(one.rows));
  if (!kept.size || kept.size >= universe.size) bad.push(`q=${q} no estrecho el directorio`);
  for (const id of kept) if (!universe.has(id)) bad.push(`q=${q} devolvio ${id}, ajeno`);
  const [[m]] = query(`${dirSql(all.meta, q)} select count(*) from part`);
  if (Number(m) !== one.page.total) bad.push(`q=${q}: total ${one.page.total} != SQL ${m}`);
  bad.push(...await paged(action, LIST, {}, 2));
  const fixed = await action(LIST, { page: 1, limit: 200, bp: all.rows[0].id, tab: 'so' });
  if (JSON.stringify(ids(fixed.rows)) !== JSON.stringify(ids(all.rows))) {
    bad.push('el tercero elegido o la pestana movieron el directorio');
  }
  return done(pass, fail, 'W8', 'directorio en servidor', bad, `${all.page.total} terceros = `
    + `count(*), q=${q} dejo ${kept.size}, paginas de 2 disjuntas, bp y tab no lo mueven`);
}

/** W10: every tab id came from the dictionary, and venta and compra did not get the same one. */
async function gateTabs({ action, query, pass, fail }) {
  const head = await action(HEAD, {});
  const dir = await action(LIST, { page: 1, limit: 1 });
  const tabs = head.meta.tabs;
  const bad = [];
  const table = (id) => query(`select lower(t.tablename) from ad_tab b
    join ad_table t on t.ad_table_id = b.ad_table_id
    where b.ad_tab_id = ${lit(id)} and b.isactive = 'Y'`);
  for (const kind of KINDS) {
    const rows = tabs[kind.k] ? table(tabs[kind.k]) : [];
    if (!tabs[kind.k]) bad.push(`${kind.k}: sin ad_tab_id`);
    else if (!rows.length) bad.push(`${kind.k}: ${tabs[kind.k]} no existe en ad_tab`);
    else if (rows[0][0] !== kind.t) bad.push(`${kind.k}: ${tabs[kind.k]} es de ${rows[0][0]}`);
  }
  for (const pair of [['so', 'po'], ['si', 'pi'], ['rc', 'pm']]) {
    if (tabs[pair[0]] === tabs[pair[1]]) bad.push(`${pair.join(' y ')} comparten pestana`);
  }
  const partner = dir.meta.partnerTab ? table(dir.meta.partnerTab) : [];
  if (!partner.length || partner[0][0] !== 'c_bpartner') bad.push('partnerTab no es de c_bpartner');
  return done(pass, fail, 'W10', 'pestanas resueltas en SQL', bad, '6 ad_tab_id reales sobre su '
    + `propia tabla (so=${tabs.so}, po=${tabs.po}, si=${tabs.si}, pi=${tabs.pi}, rc=${tabs.rc}, `
    + `pm=${tabs.pm}) mas partnerTab=${dir.meta.partnerTab}`);
}

export default async function (ctx) {
  for (const gate of [gateHead, gateNarrow, gateDirectory, gateTabs]) await gate(ctx);
}
