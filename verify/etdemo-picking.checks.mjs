/*
 * Gates propios de ETDEMO_Picking, todos contra el datasource, la escritura y la base, ninguno
 * contra el DOM. W5 el dryRun no mueve nada ni con la bandera ausente o corrupta, W6 el CO real
 * mueve docstatus y el RE lo devuelve, W8 lo que no esta en la whitelist se rechaza con sobre y
 * la fila intacta, W9 el semaforo solo cuenta lineas de almacen, W10 el pending recorta una
 * cantidad negativa, W11 los recuentos del selector no se mueven al cambiar de pedido.
 * W1..W4 y W7 son del runner.
 */
import fs from 'node:fs';
import path from 'node:path';

const SRC = 'com.etendoerp.uikit.samples.picking.PickList';
const RUN = 'com.etendoerp.uikit.samples.picking.ConfirmOrder';
const PROPS = path.resolve(import.meta.dirname, '../../../config/Openbravo.properties');
const CTX = (/^context\.name=(.*)$/m.exec(fs.readFileSync(PROPS, 'utf8')) || [, 'x'])[1].trim();
const BASE = (process.env.ETENDO_URL || `http://localhost:8888/${CTX}`).replace(/\/$/, '');
const STOCKED = "p.isstocked = 'Y' and p.producttype = 'I'";

const lit = (v) => `'${String(v).replace(/'/g, "''")}'`;
const list = (v) => (v && v.length ? v.map(lit).join(',') : 'null');
const done = (pass, fail, id, name, bad, ok) =>
  (bad.length ? fail(id, name, bad.join('; ')) : pass(id, name, ok));
const call = (a, p) =>
  a(SRC, Object.assign({ status: 'null', q: 'null', order: 'null', page: 1, limit: 200 }, p));

/** El predicado de visibilidad del handler, reescrito desde las tablas fisicas. */
const vis = (m, a) => `${a}.ad_client_id in (${list(m.scope.clients)})`
  + ` and ${a}.ad_org_id in (${list(m.scope.orgs)}) and ${a}.isactive = 'Y'`
  + ` and ${a}.issotrx = 'Y'`;
const LINES = `from c_orderline ol join m_product p on p.m_product_id = ol.m_product_id`;

const status = (query, id) =>
  (query(`select docstatus from c_order where c_order_id = ${lit(id)}`)[0] || [''])[0];

async function token(get) {
  const { text } = await get(`${BASE}/org.openbravo.client.kernel/OBCLKER_Kernel/SessionDynamic`);
  const m = /csrfToken\s*:\s*'([A-Za-z0-9]+)'/.exec(text);
  return m ? m[1] : null;
}
const post = (action, tok, body) => action(RUN, {}, Object.assign({ csrfToken: tok }, body));

/**
 * W5: la simulacion no toca la fila, y tampoco la toca una peticion a la que le falta la bandera
 * o la trae corrupta. Eso es lo que hace que el default sea seguro y no una convencion.
 */
async function gateDry({ action, get, query, pass, fail, manifest }) {
  const id = manifest.writes[0].payload.orderId;
  const tok = await token(get);
  if (!tok) return fail('W5', 'el dryRun no toca nada', 'no pude leer OB.User.csrfToken');
  const was = status(query, id);
  const bad = [];
  for (const flag of [undefined, true, 'quizas']) {
    const body = flag === undefined ? { orderId: id } : { orderId: id, dryRun: flag };
    const out = await post(action, tok, body);
    const tag = JSON.stringify(flag === undefined ? 'ausente' : flag);
    if (out.error) bad.push(`${tag}: ${out.error.code}`);
    if (out.dryRun !== true) bad.push(`${tag}: respondio dryRun=${out.dryRun}`);
    if (out.applied !== false) bad.push(`${tag}: respondio applied=${out.applied}`);
    const now = status(query, id);
    if (now !== was) bad.push(`${tag}: c_order paso de ${was} a ${now}`);
  }
  return done(pass, fail, 'W5', 'el dryRun no toca nada', bad,
    `tres cuerpos (bandera ausente, true y basura) devolvieron dryRun:true y applied:false`
    + ` y c_order.docstatus siguio en ${was}`);
}

/**
 * W6: el unico gate que muta un documento de verdad. Fixture repetible: CO y despues RE, y el
 * finally reabre el pedido por el mismo camino si el gate murio en medio -- nunca con un UPDATE,
 * que dejaria el documento a medias.
 */
async function gateRoundTrip({ action, get, query, pass, fail, skip, manifest }) {
  const id = manifest.writes[0].payload.orderId;
  const tok = await token(get);
  if (!tok) return fail('W6', 'el CO real y el RE que lo deshace', 'no pude leer el csrfToken');
  const was = status(query, id);
  if (was !== 'DR') return skip('W6', 'el CO real y el RE que lo deshace', `esta en ${was}`);
  const bad = [];
  try {
    const co = await post(action, tok, { orderId: id, action: 'CO', dryRun: false });
    if (co.error) bad.push(`el CO fue rechazado: ${co.error.message}`);
    if (co.applied !== true || co.after !== 'CO') {
      bad.push(`el CO respondio applied=${co.applied} after=${co.after}`);
    }
    const mid = status(query, id);
    if (mid !== 'CO') bad.push(`c_order quedo en ${mid} tras el CO`);
    const re = await post(action, tok, { orderId: id, action: 'RE', dryRun: false });
    if (re.error) bad.push(`el RE fue rechazado: ${re.error.message}`);
    if (re.before !== 'CO' || re.after !== 'DR') {
      bad.push(`el RE respondio ${re.before} -> ${re.after}`);
    }
  } finally {
    if (status(query, id) === 'CO') await post(action, tok, { orderId: id, dryRun: false });
  }
  const end = status(query, id);
  if (end !== was) bad.push(`el fixture quedo en ${end} y no en ${was}`);
  return done(pass, fail, 'W6', 'el CO real y el RE que lo deshace', bad,
    `${id.slice(0, 8)} paso DR -> CO -> DR en c_order.docstatus por ProcessOrderUtil, asi que`
    + ' el gate es repetible');
}

/** W8: fuera de la whitelist, y fuera del ambito, se responde con sobre y sin tocar la fila. */
async function gateWhitelist({ action, get, query, pass, fail, skip }) {
  const all = await call(action);
  const victim = query(`select o.c_order_id, o.docstatus from c_order o
    where ${vis(all.meta, 'o')} and o.docstatus not in ('DR', 'CO') limit 1`)[0];
  if (!victim) return skip('W8', 'la transicion prohibida se rechaza', 'no hay estado ajeno');
  const tok = await token(get);
  if (!tok) return fail('W8', 'la transicion prohibida se rechaza', 'no pude leer el csrfToken');
  const bad = [];
  // action() lanza con cualquier status que no sea 200: llegar aqui ya prueba que el rechazo de
  // dominio no es un 500 ni una pagina de error.
  const out = await post(action, tok, { orderId: victim[0], dryRun: false });
  if (!out.error) bad.push(`acepto ${victim[1]} -> algo`);
  else if (out.error.code !== 'ETDEMO_PickingBadTransition') bad.push(`codigo ${out.error.code}`);
  else if (!out.error.message.includes(victim[1])) bad.push('el mensaje no nombra el estado');
  const now = status(query, victim[0]);
  if (now !== victim[1]) bad.push(`la fila paso a ${now} pese al rechazo`);
  const hidden = (query(`select o.c_order_id from c_order o where o.c_order_id not in
    (select o.c_order_id from c_order o where ${vis(all.meta, 'o')}) limit 1`)[0] || [])[0];
  if (hidden) {
    const o = await post(action, tok, { orderId: hidden, dryRun: false });
    const code = o.error ? o.error.code : 'sin error';
    if (code !== 'ETDEMO_PickingNotVisible') bad.push(`un pedido invisible respondio ${code}`);
  }
  return done(pass, fail, 'W8', 'la transicion prohibida se rechaza', bad,
    `${victim[1]} devolvio ETDEMO_PickingBadTransition con HTTP 200 y la fila intacta${hidden
      ? ', y un pedido fuera de ambito devolvio ETDEMO_PickingNotVisible' : ''}`);
}

/** W9: el semaforo solo mira lineas con isstocked='Y' and producttype='I'. */
async function gateSemaphore({ action, query, pass, fail, skip }) {
  const all = await call(action);
  const pick = (query(`select o.c_order_id from c_order o join c_orderline ol
    on ol.c_order_id = o.c_order_id join m_product p on p.m_product_id = ol.m_product_id
    where ${vis(all.meta, 'o')} and ol.isactive = 'Y' group by o.c_order_id
    having count(*) filter (where not (${STOCKED})) > 0
    and count(*) filter (where ${STOCKED}) > 0 limit 1`)[0] || [])[0];
  if (!pick) return skip('W9', 'el semaforo solo cuenta almacen', 'ningun pedido mezcla ambas');
  const d = await call(action, { order: pick });
  const bad = [];
  const [[svc, stk]] = [query(`select count(*) filter (where not (${STOCKED})),
    count(*) filter (where ${STOCKED}) ${LINES}
    where ol.c_order_id = ${lit(pick)} and ol.isactive = 'Y'`)[0]];
  const na = d.lines.filter((l) => l.tone === 'na');
  if (na.length !== Number(svc)) bad.push(`na=${na.length} y SQL dice ${svc} de servicio`);
  if (d.lines.length - na.length !== Number(stk)) bad.push(`almacen=${stk} y la vista discrepa`);
  for (const l of na) {
    if (l.stocked === 'Y' && l.productType === 'I') bad.push(`${l.code} es de almacen y es na`);
  }
  for (const l of d.lines.filter((x) => x.tone !== 'na')) {
    if (l.stocked !== 'Y' || l.productType !== 'I') bad.push(`${l.code} no es de almacen`);
    const want = l.pending <= 0 ? 'done'
      : l.onHand >= l.pending ? 'ok' : l.onHand > 0 ? 'partial' : 'short';
    if (l.tone !== want) bad.push(`${l.code}: tone=${l.tone} y por los numeros es ${want}`);
  }
  return done(pass, fail, 'W9', 'el semaforo solo cuenta almacen', bad,
    `en el pedido ${pick.slice(0, 8)} las ${svc} lineas de servicio son na y las ${stk} de`
    + ' almacen llevan el tono que dictan pending y onhand');
}

/** W10: pending = greatest(0, pedida - entregada), probado con una cantidad negativa. */
async function gateClamp({ action, query, pass, fail, skip }) {
  const all = await call(action);
  const row = query(`select ol.c_orderline_id, o.c_order_id, ol.qtyordered
    from c_order o join c_orderline ol on ol.c_order_id = o.c_order_id
    join m_product p on p.m_product_id = ol.m_product_id
    where ${vis(all.meta, 'o')} and o.docstatus = 'DR' and ol.isactive = 'Y'
    and ${STOCKED} limit 1`)[0];
  if (!row) return skip('W10', 'el pending recorta', 'no hay linea de borrador que forzar');
  const [line, order, qty] = row;
  const bad = [];
  try {
    query(`update c_orderline set qtyordered = -1 where c_orderline_id = ${lit(line)}`);
    const l = (await call(action, { order })).lines.filter((x) => x.id === line)[0];
    if (!l) bad.push('la linea forzada no volvio del datasource');
    else {
      if (Number(l.ordered) !== -1) bad.push(`ordered=${l.ordered} y no -1`);
      if (Number(l.pending) !== 0) bad.push(`pending=${l.pending} y no 0`);
      if (l.tone !== 'done') bad.push(`tone=${l.tone} y no done`);
    }
  } finally {
    query(`update c_orderline set qtyordered = ${lit(qty)} where c_orderline_id = ${lit(line)}`);
  }
  const back = query(`select qtyordered from c_orderline where c_orderline_id = ${lit(line)}`);
  if (Number(back[0][0]) !== Number(qty)) bad.push(`la fixture quedo en ${back[0][0]}`);
  return done(pass, fail, 'W10', 'el pending recorta', bad,
    `con qtyordered=-1 la linea ${line.slice(0, 8)} respondio pending 0 y tono done, y quedo`
    + ` restaurada en ${qty}`);
}

/** W11: el carril se cuenta sobre todo lo legible y no se mueve con la seleccion ni el filtro. */
async function gateRail({ action, query, pass, fail }) {
  const all = await call(action);
  const rail = (d) => JSON.stringify([d.statuses, d.total]);
  const bad = [];
  const probes = [{ status: 'DR' }, { q: all.orders[0].documentNo }, { page: 2 },
    { order: all.orders[0].id }, { order: all.orders[all.orders.length - 1].id }];
  for (const f of probes) {
    if (rail(await call(action, f)) !== rail(all)) bad.push(`cambio con ${JSON.stringify(f)}`);
  }
  for (const b of all.statuses) {
    const [[n]] = query(`select count(*) from c_order o where ${vis(all.meta, 'o')}
      and o.docstatus = ${lit(b.status)}`);
    if (Number(n) !== b.n) bad.push(`${b.status}: la vista dice ${b.n} y SQL ${n}`);
  }
  return done(pass, fail, 'W11', 'el carril ignora filtro y seleccion', bad,
    `${probes.length} sondas (dos de ellas cambiando el pedido seleccionado) dejaron identicos`
    + ` los ${all.statuses.length} recuentos, y cada uno cuadra con un count(*) independiente`);
}

export default async function (ctx) {
  for (const gate of [gateDry, gateRoundTrip, gateWhitelist, gateSemaphore, gateClamp, gateRail]) {
    await gate(ctx);
  }
}
