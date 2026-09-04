/*
 * Window gates for ETDEMO_Cash: W5, W6, W8, W9, W10 (W1-W4 and W7 belong to the runner).
 * No DOM. Every claim this window makes is about numbers, so each one is recomputed here from
 * fin_payment_schedule in SQL written independently of the handler's -- reusing its own SQL would
 * only prove it agrees with itself. Scope is not under test: ctx.query runs unscoped, so every
 * recomputation is restricted to the clients and orgs the answer reports under meta.
 */
const DS = 'com.etendoerp.uikit.samples.cash.Portfolio';
const FROM = 'from fin_payment_schedule ps join c_invoice i on i.c_invoice_id = ps.c_invoice_id';
const near = (a, b) => Math.abs(Number(a) - Number(b)) < 0.01; // DECIMALes: cuadran al centimo
const esc = (v) => `'${String(v).replace(/'/g, "''")}'`;
const cell = (rows) => (rows[0] || [null])[0];
const plus = (iso, n) => new Date(Date.parse(iso) + n * 864e5).toISOString().slice(0, 10);
const done = (c, i, w, b, ok) => (b.length ? c.fail(i, w, b.join('; ')) : c.pass(i, w, ok));
/** The outstanding invoice-backed portfolio under the reported scope; side narrows to one half. */
const where = (d, side) => `ps.isactive = 'Y' and i.isactive = 'Y' and ps.outstandingamt > 0
  and ps.ad_client_id in (${d.meta.scopeClients.map(esc).join(',')})
  and ps.ad_org_id in (${d.meta.scopeOrgs.map(esc).join(',')})
  ${side ? `and i.issotrx = ${esc(d.side === 'AR' ? 'Y' : 'N')}` : ''}`;
const bucketOf = (asOf, a = `(${esc(asOf)}::date - ps.duedate::date)`) =>
  `case when ${a} < 0 then 'cur' when ${a} <= 30 then 'd30' when ${a} <= 60 then 'd60'
    when ${a} <= 90 then 'd90' else 'd90p' end`;
/** The datasource's five buckets against the same five computed here. Zeros must be present. */
function diff(query, d, asOf) {
  const rows = query(`select ${bucketOf(asOf)} as b, count(*), coalesce(sum(ps.outstandingamt), 0)
    ${FROM} where ${where(d, true)} and ps.c_currency_id = ${esc(d.currency.id)} group by 1`);
  const mine = new Map(rows.map(([b, n, amt]) => [b, [Number(n), Number(amt)]]));
  return d.buckets.flatMap((b) => {
    const [docs, amount] = mine.get(b.id) || [0, 0];
    return (Number(b.docs) === docs ? [] : [`${b.id}: ${b.docs} docs, SQL da ${docs}`])
      .concat(near(b.amount, amount) ? [] : [`${b.id}: ${b.amount}, SQL da ${amount}`]);
  });
}
/** W5: section 5 recomputed -- each bucket, and the buckets adding up to the side's total. */
async function gateArithmetic(c) {
  const d = await c.action(DS, {});
  if (!d.currency) return c.skip('W5', 'aritmetica de los tramos', 'el lado no tiene documentos');
  const bad = diff(c.query, d, d.asOf);
  const ids = d.buckets.map((b) => b.id).join(',');
  if (ids !== 'cur,d30,d60,d90,d90p') bad.push(`buckets[] llego como ${ids}`);
  const sum = d.buckets.reduce((a, b) => a + Number(b.amount), 0);
  const docs = d.buckets.reduce((a, b) => a + Number(b.docs), 0);
  if (!near(sum, d.total.amount)) bad.push(`los tramos suman ${sum}, total ${d.total.amount}`);
  if (docs !== Number(d.total.docs)) bad.push(`${docs} docs en tramos, total ${d.total.docs}`);
  return done(c, 'W5', 'aritmetica de los tramos', bad, `${docs} docs y ${d.total.amount} ` +
    `${d.currency.iso} en 5 tramos, recalculados en SQL contra ${d.asOf}`);
}
/** W6: with no param the date comes from the data and equals an independent max() over both sides;
 * with one it is honoured, and SQL proves a document really changes bucket at the shifted date. */
async function gateAsOf(c) {
  const d = await c.action(DS, {});
  if (!d.currency) return c.skip('W6', 'contrato de asOf', 'el lado no tiene documentos');
  const bad = [];
  const max = cell(c.query(`select max(ps.duedate)::date ${FROM} where ${where(d, false)}`));
  if (d.asOfSource !== 'data') bad.push(`sin parametro, asOfSource = ${d.asOfSource}`);
  if (d.asOf !== max) bad.push(`asOf ${d.asOf}, pero max(duedate) es ${max}`);
  const moved = plus(d.asOf, 31);
  const p = await c.action(DS, { asOf: moved });
  if (p.asOfSource !== 'param') bad.push(`con parametro, asOfSource = ${p.asOfSource}`);
  if (p.asOf !== moved) bad.push(`pedi asOf=${moved} y devolvio ${p.asOf}`);
  const n = Number(cell(c.query(`select count(*) ${FROM} where ${where(d, true)}
    and ps.c_currency_id = ${esc(d.currency.id)} and ${bucketOf(d.asOf)} <> ${bucketOf(moved)}`)));
  if (n === 0) bad.push('+31 dias no mueve ningun documento: el caso no probaria nada');
  for (const one of diff(c.query, p, moved)) bad.push(`asOf=${moved}: ${one}`);
  return done(c, 'W6', 'contrato de asOf', bad,
    `data => ${d.asOf} = max(duedate); param => ${moved}, con ${n} doc(s) cambiando de tramo`);
}
/** W8: narrowing the table must not move the rail -- same five totals, bucket selected or not. */
async function gateInvariance(c) {
  const all = await c.action(DS, {});
  if (!all.currency) return c.skip('W8', 'tramos invariantes', 'el lado no tiene documentos');
  const bad = [];
  const live = all.buckets.filter((b) => Number(b.docs) > 0);
  for (const b of live) {
    const only = await c.action(DS, { bucket: b.id });
    if (JSON.stringify(only.buckets) !== JSON.stringify(all.buckets)) {
      bad.push(`bucket=${b.id} cambio los totales por tramo`);
    }
    if (!near(only.total.amount, all.total.amount)) bad.push(`bucket=${b.id} cambio el total`);
    const rows = only.rows || [];
    const foreign = rows.filter((r) => r.bucket !== b.id).length;
    if (foreign) bad.push(`bucket=${b.id} devolvio ${foreign} fila(s) de otro tramo`);
    if (Number(b.docs) !== rows.length) bad.push(`bucket=${b.id}: ${rows.length}/${b.docs} filas`);
  }
  return done(c, 'W8', 'tramos invariantes', bad,
    `${live.length} tramo(s) estrechan el detalle sin tocar los cinco totales ni el total`);
}
/** W9: one currency at a time. What is left out is counted on screen, never added in. */
async function gateCurrency(c) {
  const d = await c.action(DS, {});
  if (!d.currency) return c.skip('W9', 'una sola moneda', 'el lado no tiene documentos');
  const n = Number(cell(c.query(`select count(*) ${FROM} where ${where(d, true)}
    and ps.c_currency_id <> ${esc(d.currency.id)}`)));
  const bad = Number(d.excluded.docs) === n ? [] : [`excluded.docs ${d.excluded.docs}, SQL ${n}`];
  const foreign = (d.rows || []).filter((r) => r.currency !== d.currency.id).length;
  if (foreign) bad.push(`${foreign} fila(s) devueltas en otra moneda`);
  if (!d.currency.symbol) bad.push('la moneda no trae simbolo con el que formatear importes');
  return done(c, 'W9', 'una sola moneda', bad, `${d.currency.iso} (${d.currency.symbol}) de ` +
    `${d.currencies.length}, ${n} documento(s) fuera y ninguno colado en las filas`);
}
/** W10: twelve consecutive months, empty ones included -- a gap lies about the spacing. */
async function gateSeries(c) {
  const d = await c.action(DS, {});
  if (!d.currency) return c.skip('W10', 'doce meses sin huecos', 'el lado no tiene documentos');
  const months = d.series || [];
  const y = Number(String(d.asOf).slice(0, 4)), m = Number(String(d.asOf).slice(5, 7));
  const want = Array.from({ length: 12 },
    (_, k) => new Date(Date.UTC(y, m - 12 + k, 1)).toISOString().slice(0, 7));
  const got = months.map((x) => x.month).join(',');
  const bad = got === want.join(',') ? [] : [`la serie es [${got}], esperaba [${want.join(',')}]`];
  const loose = months.filter((x) => typeof x.amount !== 'number').length;
  if (loose) bad.push(`${loose} mes(es) sin importe numerico`);
  const empty = months.filter((x) => !x.docs).length;
  return done(c, 'W10', 'doce meses sin huecos', bad,
    `${want[0]} a ${want[11]}, ${empty} mes(es) sin pagos rellenados en Java`);
}
export default async function (ctx) {
  const gates = [gateArithmetic, gateAsOf, gateInvariance, gateCurrency, gateSeries];
  for (const g of gates) await g(ctx);
}
