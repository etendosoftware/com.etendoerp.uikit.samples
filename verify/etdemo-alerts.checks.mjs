/*
 * Gates propios de ETDEMO_Alerts, todos contra el datasource y la base y ninguno contra el DOM.
 * W5 el carril ignora el filtro, W6 el detalle estrecha en SQL, W8 el filtro de destinatario
 * recorta para un rol no administrador, W9 la escritura va, vuelve y se restaura, W10 la
 * transicion fuera de la whitelist se rechaza con sobre de error. W1..W4 y W7 son del runner.
 */
import fs from 'node:fs';
import path from 'node:path';

const SRC = 'com.etendoerp.uikit.samples.alerts.AlertInbox';
const ACK = 'com.etendoerp.uikit.samples.alerts.AckAlert';
/* Rol no administrador que ad_alertrecipient lista para una regla y no para la otra. El usuario
 * lo crea el gate: F&BESRNUser existe pero esta inactivo, y ejercitar un filtro con el rol que
 * lo sortea no demuestra nada. */
const ROLE = 'F77D70601AD549B19DE47965F6D48D12';
const PROBE = { id: 'ETDEMOALERTSPROBE00000000000001', name: 'ETDEMO_AlertsProbe' };
const PROPS = path.resolve(import.meta.dirname, '../../../config/Openbravo.properties');
const CTX = (/^context\.name=(.*)$/m.exec(fs.readFileSync(PROPS, 'utf8')) || [, 'x'])[1].trim();
const BASE = (process.env.ETENDO_URL || `http://localhost:8888/${CTX}`).replace(/\/$/, '');
const ST = "coalesce(nullif(trim(a.status), ''), 'NEW')";

const lit = (v) => `'${String(v).replace(/'/g, "''")}'`;
const list = (v) => (v && v.length ? v.map(lit).join(',') : 'null');
const ids = (rows) => new Set(rows.map((r) => r.id));
const call = (a, p) => a(SRC, Object.assign({ status: 'null', rule: 'null', limit: 200 }, p));
const done = (pass, fail, id, name, bad, ok) =>
  (bad.length ? fail(id, name, bad.join('; ')) : pass(id, name, ok));
const jar = (r) => (typeof r.headers.getSetCookie === 'function' ? r.headers.getSetCookie() : [])
  .map((c) => c.split(';')[0]).filter(Boolean).join('; ');

/** El predicado de visibilidad del handler, reescrito desde las tablas fisicas. */
function where(m, extra) {
  const s = (a) => `${a}.ad_client_id in (${list(m.scope.clients)})`
    + ` and ${a}.ad_org_id in (${list(m.scope.orgs)}) and ${a}.isactive = 'Y'`;
  const u = lit(m.user);
  const r = lit(m.role);
  return `from ad_alert a join ad_alertrule r on r.ad_alertrule_id = a.ad_alertrule_id
    where ${s('a')} and ${s('r')} and (a.ad_user_id = ${u}
      or (a.ad_user_id is null and a.ad_role_id = ${r})
      or exists (select 1 from ad_alertrecipient p where p.ad_alertrule_id = r.ad_alertrule_id
        and p.isactive = 'Y' and (p.ad_user_id = ${u}
        or (p.ad_user_id is null and p.ad_role_id = ${r})))) ${extra || ''}`;
}

async function token(get) {
  const { text } = await get(`${BASE}/org.openbravo.client.kernel/OBCLKER_Kernel/SessionDynamic`);
  const m = /csrfToken\s*:\s*'([A-Za-z0-9]+)'/.exec(text);
  return m ? m[1] : null;
}

/** W5: el carril se cuenta sobre todo lo legible y un count(*) independiente lo confirma. */
async function gateRail({ action, query, pass, fail }) {
  const all = await call(action);
  const rail = (d) => JSON.stringify([d.statuses, d.rules, d.total]);
  const bad = [];
  for (const f of [{ status: 'SUPPRESSED' }, { rule: all.rules[0].id }, { status: 'NEW' }]) {
    if (rail(await call(action, f)) !== rail(all)) bad.push(`cambio con ${JSON.stringify(f)}`);
  }
  for (const b of all.statuses) {
    const [[n]] = query(`select count(*) ${where(all.meta, `and ${ST} = ${lit(b.status)}`)}`);
    if (Number(n) !== b.n) bad.push(`${b.status}: la vista dice ${b.n} y SQL ${n}`);
  }
  const [[t]] = query(`select count(*) ${where(all.meta)}`);
  if (Number(t) !== all.total) bad.push(`total: la vista dice ${all.total} y SQL ${t}`);
  return done(pass, fail, 'W5', 'el carril ignora el filtro', bad,
    `3 filtros dejaron identicos los ${all.statuses.length} estados y las ${all.rules.length}`
    + ` reglas, y el count(*) independiente cuadra con ${all.total} alertas`);
}

/** W6: solo el detalle estrecha, y comparado como conjunto de ids, no como recuento. */
async function gateDetail({ action, query, pass, fail }) {
  const all = await call(action);
  const universe = ids(all.rows);
  const bad = [];
  let used = 0;
  for (const f of [{ status: all.rows[0].status }, { rule: all.rows[0].rule }]) {
    const kept = ids((await call(action, f)).rows);
    if (!kept.size || kept.size >= universe.size) continue;
    used += 1;
    for (const id of kept) if (!universe.has(id)) bad.push(`${JSON.stringify(f)} trajo ${id}`);
    const extra = f.status ? `and ${ST} = ${lit(f.status)}`
      : `and r.ad_alertrule_id = ${lit(f.rule)}`;
    const sql = new Set(query(`select a.ad_alert_id ${where(all.meta, extra)}`).map((r) => r[0]));
    if (sql.size !== kept.size || [...kept].some((id) => !sql.has(id))) {
      bad.push(`${JSON.stringify(f)}: vista ${kept.size}, SQL ${sql.size}, conjuntos distintos`);
    }
  }
  if (!used) bad.push('ningun filtro estrecho el detalle');
  return done(pass, fail, 'W6', 'el detalle estrecha en SQL', bad,
    `${used} filtro(s) recortaron el detalle de ${universe.size} filas y el conjunto de ids`
    + ' coincide con el de SQL');
}

/**
 * W8: el filtro de destinatario, preguntado a un rol que no administra nada. El usuario sonda se
 * crea aqui de forma idempotente y lleva el hash del admin, asi que no introduce ningun secreto
 * nuevo, y lo que se afirma es lo unico que importa: lo que pierde lo pierde por
 * ad_alertrecipient y no por la clausula de ambito.
 */
async function gateRecipient({ action, query, pass, fail }) {
  query(`insert into ad_user (ad_user_id, ad_client_id, ad_org_id, isactive, created, createdby,
    updated, updatedby, name, username, password, default_ad_client_id, default_ad_org_id,
    default_ad_role_id, islocked) select ${lit(PROBE.id)}, r.ad_client_id, '0', 'Y', now(), '100',
    now(), '100', 'ETDEMO Alerts probe', ${lit(PROBE.name)}, u.password, r.ad_client_id,
    '7BABA5FF80494CAFA54DEBD22EC46F01', r.ad_role_id, 'N' from ad_role r, ad_user u
    where r.ad_role_id = ${lit(ROLE)} and u.ad_user_id = '100'
    and not exists (select 1 from ad_user x where x.ad_user_id = ${lit(PROBE.id)})`);
  query(`insert into ad_user_roles (ad_user_roles_id, ad_client_id, ad_org_id, isactive, created,
    createdby, updated, updatedby, ad_user_id, ad_role_id, is_role_admin) select ${lit(PROBE.id)},
    u.ad_client_id, '0', 'Y', now(), '100', now(), '100', u.ad_user_id, ${lit(ROLE)}, 'N'
    from ad_user u where u.ad_user_id = ${lit(PROBE.id)} and not exists (select 1
    from ad_user_roles x where x.ad_user_id = u.ad_user_id and x.ad_role_id = ${lit(ROLE)})`);
  // Usable solo mientras corre el gate: al montar se abre, en el finally se vuelve a cerrar.
  query(`update ad_user set isactive = 'Y', islocked = 'N' where ad_user_id = ${lit(PROBE.id)}`);
  try {
    return await probe(action, query, pass, fail);
  } finally {
    // Sin esto el gate deja una cuenta activa con la clave del admin en la instancia.
    query(`update ad_user set isactive = 'N', islocked = 'Y'
      where ad_user_id = ${lit(PROBE.id)}`);
  }
}

/** El cuerpo del W8, con la sonda ya abierta y garantia de cierre en el llamador. */
async function probe(action, query, pass, fail) {
  const admin = await call(action);
  const seed = jar(await fetch(`${BASE}/security/Login`, { redirect: 'manual' }));
  const res = await fetch(`${BASE}/secureApp/LoginHandler.html`, {
    method: 'POST', redirect: 'manual',
    headers: { 'content-type': 'application/x-www-form-urlencoded', cookie: seed },
    body: new URLSearchParams({ user: PROBE.name, password: 'admin' }).toString()
  });
  const hit = await fetch(`${BASE}/org.openbravo.client.kernel?_action=${SRC}&limit=200`,
    { headers: { cookie: jar(res) || seed } });
  if (hit.status !== 200) return fail('W8', 'destinatario', `el probe recibio HTTP ${hit.status}`);
  const mine = JSON.parse(await hit.text());
  const kept = ids(mine.rows);
  const lost = admin.rows.filter((r) => !kept.has(r.id));
  const bad = [];
  if (mine.meta.role !== ROLE) bad.push(`la sesion del probe resolvio el rol ${mine.meta.role}`);
  if (!(mine.total < admin.total)) bad.push(`el probe ve ${mine.total} y el admin ${admin.total}`);
  if (!lost.length) bad.push('no perdio ninguna fila, asi que el filtro no se ejercito');
  for (const r of lost) {
    const [[n]] = query(`select count(*) from ad_alert a where a.ad_alert_id = ${lit(r.id)}
      and a.ad_client_id in (${list(mine.meta.scope.clients)})
      and a.ad_org_id in (${list(mine.meta.scope.orgs)})`);
    if (Number(n) !== 1) bad.push(`${r.id} quedo fuera por ambito, no por destinatario`);
  }
  return done(pass, fail, 'W8', 'el filtro de destinatario recorta', bad,
    `${PROBE.name} (rol ${ROLE.slice(0, 8)}, no administrador) ve ${mine.total} de las`
    + ` ${admin.total} del administrador y las ${lost.length} que pierde estan dentro de su`
    + ' ambito, asi que las excluye ad_alertrecipient');
}

/**
 * W9: la escritura llega de verdad a la fila. La fixture se fuerza a NEW y se restaura a su valor
 * original, asi que el gate es repetible. Si, ctx.query esta documentado como ayuda de lectura;
 * es psql, y un gate que no puede montar su fixture no puede afirmar nada.
 */
async function gateWrite({ action, get, query, pass, fail, manifest }) {
  const id = manifest.writes[0].payload.id;
  const tok = await token(get);
  if (!tok) return fail('W9', 'la escritura va y vuelve', 'no pude leer OB.User.csrfToken');
  const [[was]] = query(`select ${ST} from ad_alert a where a.ad_alert_id = ${lit(id)}`);
  const bad = [];
  try {
    query(`update ad_alert set status = 'NEW' where ad_alert_id = ${lit(id)}`);
    const out = await action(ACK, {}, { id, status: 'ACKNOWLEDGED', csrfToken: tok });
    if (out.error) bad.push(`rechazo la transicion permitida: ${out.error.code}`);
    if (out.changed !== true) bad.push(`respondio changed=${out.changed} la primera vez`);
    const [[now]] = query(`select ${ST} from ad_alert a where a.ad_alert_id = ${lit(id)}`);
    if (now !== 'ACKNOWLEDGED') bad.push(`la fila quedo en ${now} y no en ACKNOWLEDGED`);
    const again = await action(ACK, {}, { id, status: 'ACKNOWLEDGED', csrfToken: tok });
    if (again.changed !== false) bad.push('no es idempotente: la repeticion volvio a escribir');
  } finally {
    query(`update ad_alert set status = ${lit(was)} where ad_alert_id = ${lit(id)}`);
  }
  return done(pass, fail, 'W9', 'la escritura va y vuelve', bad,
    `${id.slice(0, 8)} paso de NEW a ACKNOWLEDGED en ad_alert, la repeticion respondio`
    + ` changed:false y la fila quedo restaurada en ${was}`);
}

/** W10: fuera de la whitelist se responde con sobre, HTTP 200 y la fila intacta. */
async function gateWhitelist({ action, get, query, pass, fail, skip }) {
  const all = await call(action);
  const victim = all.rows.find((r) => r.status !== 'NEW');
  if (!victim) return skip('W10', 'transicion prohibida', 'no hay fila no-NEW visible');
  const tok = await token(get);
  if (!tok) return fail('W10', 'transicion prohibida', 'no pude leer OB.User.csrfToken');
  const bad = [];
  // action() lanza con cualquier status que no sea 200, asi que llegar aqui ya prueba que un
  // rechazo de dominio no es un 500.
  const out = await action(ACK, {}, { id: victim.id, status: 'ACKNOWLEDGED', csrfToken: tok });
  if (!out.error) bad.push(`acepto ${victim.status} -> ACKNOWLEDGED`);
  else if (out.error.code !== 'ETDEMO_AlertsBadTransition') bad.push(`codigo ${out.error.code}`);
  else if (!out.error.message.includes(victim.status)) bad.push('el mensaje no nombra el estado');
  const [[now]] = query(`select ${ST} from ad_alert a where a.ad_alert_id = ${lit(victim.id)}`);
  if (now !== victim.status) bad.push(`la fila cambio a ${now} pese al rechazo`);
  // Y lo mismo con una fila que la relectura con ambito no encuentra: un id es una afirmacion.
  const hidden = query(`select a.ad_alert_id from ad_alert a where a.ad_alert_id not in
    (select a.ad_alert_id ${where(all.meta)}) limit 1`).map((r) => r[0])[0];
  if (hidden) {
    const o = await action(ACK, {}, { id: hidden, status: 'ACKNOWLEDGED', csrfToken: tok });
    const code = o.error ? o.error.code : 'sin error';
    if (code !== 'ETDEMO_AlertsNotVisible') bad.push(`una alerta invisible respondio ${code}`);
  }
  return done(pass, fail, 'W10', 'la transicion prohibida se rechaza', bad,
    `${victim.status} -> ACKNOWLEDGED devolvio ETDEMO_AlertsBadTransition con HTTP 200 y la fila`
    + ` intacta${hidden ? ', y una alerta fuera de ambito devolvio ETDEMO_AlertsNotVisible' : ''}`);
}

export default async function (ctx) {
  for (const gate of [gateRail, gateDetail, gateRecipient, gateWrite, gateWhitelist]) {
    await gate(ctx);
  }
}
