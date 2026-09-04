/*
 * Window-specific gates for ETOKRS_Review.
 *
 * check-window.mjs owns the gates every window shares (AD wiring, the bundle on the classpath, the
 * view served from MainLayout/View, the declared datasources answering with the keys they promise,
 * CSRF on the declared writes). Everything below is true of *this* window and of no other, so it
 * lives with the window instead of in the runner: the datasource that has to return the whole tree
 * in one call, the department filter that has to be enforced in SQL, and section 5 of
 * docs/samples/okr-review.md recomputed from the raw ETOKRS_* rows.
 *
 * These three bodies came over unchanged from check-window.mjs's W4/W5/W6; only the plumbing calls
 * were rewired to ctx. See the contract block at the top of check-window.mjs.
 *
 * Ids: W4b, W5 and W6. W4b is the half of the old W4 that is not expressible as "these keys are
 * present" -- that half is now the runner's generic W4, fed by the manifest's datasources[].
 */
import fs from 'node:fs';
import path from 'node:path';

const TREE = 'com.etendoerp.uikit.samples.okr.ReviewTree';
const CHECKINS = 'com.etendoerp.uikit.samples.okr.Checkins';
/* The app bundle part this window ships, resolved from this file so the module can move as a unit. */
const APP_JS = path.resolve(
  import.meta.dirname,
  '../web/com.etendoerp.uikit.samples/js/okr-review.js'
);

const clamp = (n, lo, hi) => Math.min(hi, Math.max(lo, n));

/** W4b: one call returns the whole tree, as the sample's data contract promises. */
async function gateTreeContract({ action, pass, fail, skip }) {
  const tree = await action(TREE, { cycle: 'null', dept: 'all' });
  const problems = [];
  for (const key of ['cycles', 'cycle', 'depts', 'deptStats', 'objs', 'krs']) {
    if (!(key in tree)) problems.push(`falta "${key}" en la respuesta`);
  }
  if (problems.length) return fail('W4b', 'contrato del arbol', problems.join('; '));
  if (!tree.cycle) return skip('W4b', 'contrato del arbol', 'ningun ciclo tiene datos');
  for (const key of ['days', 'day']) {
    if (typeof tree.cycle[key] !== 'number') problems.push(`cycle.${key} no es numero`);
  }
  if (tree.cycle.day < 0 || tree.cycle.day > tree.cycle.days) {
    problems.push(`cycle.day ${tree.cycle.day} fuera de [0, ${tree.cycle.days}]`);
  }
  const kr = tree.krs[0];
  for (const key of ['id', 'obj', 'title', 'base', 'current', 'target', 'score', 'scoreTarget',
    'weight', 'unit', 'confidence']) {
    if (kr && !(key in kr)) problems.push(`falta krs[].${key}`);
  }
  const objIds = new Set(tree.objs.map((o) => o.id));
  const orphans = tree.krs.filter((k) => !objIds.has(k.obj)).length;
  if (orphans) problems.push(`${orphans} KR sin su objetivo en la misma respuesta`);
  const checkins = await action(CHECKINS, { cycle: 'null', dept: 'all' });
  if (!Array.isArray(checkins.checkins)) problems.push('ETOKRS_Checkins no devolvio checkins[]');
  return problems.length
    ? fail('W4b', 'contrato del arbol', problems.join('; '))
    : pass('W4b', 'contrato del arbol',
      `${tree.cycle.name}: dia ${tree.cycle.day}/${tree.cycle.days}, ${tree.depts.length} deptos, ` +
      `${tree.objs.length} objetivos, ${tree.krs.length} KR, ${checkins.checkins.length} check-ins`);
}

/**
 * W5: fact F6 -- ViewComponent never consults OBUIAPP_View_Role_Access, so the department filter
 * has to be enforced by the datasource. A filter that only hid rows in the browser would still
 * ship every department's numbers down the wire.
 */
async function gateFilterInDatasource({ action, pass, fail, skip }) {
  const all = await action(TREE, { cycle: 'null', dept: 'all' });
  if (!all.cycle || all.depts.length < 2) {
    return skip('W5', 'filtro en el datasource', 'hacen falta dos departamentos con datos');
  }
  const problems = [];
  for (const dept of all.depts) {
    const one = await action(TREE, { cycle: 'null', dept: dept.id });
    const foreign = one.objs.filter((o) => o.dept !== dept.id);
    if (foreign.length) {
      problems.push(`dept=${dept.name} devolvio ${foreign.length} objetivo(s) de otro departamento`);
    }
    const kept = new Set(one.objs.map((o) => o.id));
    const foreignKrs = one.krs.filter((k) => !kept.has(k.obj));
    if (foreignKrs.length) problems.push(`dept=${dept.name} devolvio ${foreignKrs.length} KR ajeno(s)`);
    if (one.objs.length >= all.objs.length) {
      problems.push(`dept=${dept.name} no estrecho nada (${one.objs.length} de ${all.objs.length})`);
    }
    // The rail draws every department, so the rollups must survive the filter.
    if (one.deptStats.length !== all.deptStats.length) {
      problems.push(
        `dept=${dept.name} perdio deptStats (${one.deptStats.length} de ${all.deptStats.length})`
      );
    }
  }
  // And the UI must not be re-filtering what the server already narrowed.
  const app = fs.readFileSync(APP_JS, 'utf8').replace(/\s+/g, ' ');
  if (/\.(objs|krs) ?\.filter\(/.test(app)) {
    problems.push('okr-review.js filtra objs/krs en el cliente');
  }
  return problems.length
    ? fail('W5', 'filtro en el datasource', problems.join('; '))
    : pass('W5', 'filtro en el datasource',
      `${all.depts.length} departamentos, cada uno estrechado en SQL`);
}

/**
 * W6: section 5 of the sample, recomputed here from the raw rows and compared with what the
 * datasource returned. Independent arithmetic is the whole point -- reusing the datasource's own
 * SQL would only prove it agrees with itself.
 */
async function gateFormulas({ action, query, pass, fail, skip }) {
  const tree = await action(TREE, { cycle: 'null', dept: 'all' });
  if (!tree.cycle) return skip('W6', 'formulas de la seccion 5', 'ningun ciclo tiene datos');
  const rows = query(`select o.etokrs_department_id, o.etokrs_objective_id, o.weight, k.weight,
      k.basevalue, k.currentvalue, k.targetvalue, k.score, k.scoretarget
    from etokrs_keyresult k
      join etokrs_objective o on o.etokrs_objective_id = k.etokrs_objective_id
    where k.isactive = 'Y' and o.isactive = 'Y' and o.etokrs_cycle_id = '${String(tree.cycle.id).replace(/'/g, "''")}'`);
  if (rows.length === 0) return fail('W6', 'formulas de la seccion 5', 'el ciclo no tiene KR');

  // avance = (actual - base) / (meta - base), acotado a [0, 1]; sirve igual cuando menos es mejor.
  const byObj = new Map();
  for (const [dept, obj, owgt, kwgt, base, cur, target, score, scoreTarget] of rows) {
    const span = Number(target) - Number(base);
    const frac = span === 0
      ? (Number(cur) >= Number(target) ? 1 : 0)
      : clamp((Number(cur) - Number(base)) / span, 0, 1);
    if (!byObj.has(obj)) byObj.set(obj, { dept, weight: Number(owgt), krs: [] });
    byObj.get(obj).krs.push({
      weight: Number(kwgt), frac, score: Number(score), scoreTarget: Number(scoreTarget)
    });
  }
  // Both rollup levels are weighted means: KR into objective, objective into department.
  const mean = (list, get) => {
    const w = list.reduce((a, x) => a + x.weight, 0);
    return w === 0 ? 0 : list.reduce((a, x) => a + get(x) * x.weight, 0) / w;
  };
  const byDept = new Map();
  for (const objective of byObj.values()) {
    const roll = {
      weight: objective.weight,
      frac: mean(objective.krs, (k) => k.frac),
      score: mean(objective.krs, (k) => k.score),
      scoreTarget: mean(objective.krs, (k) => k.scoreTarget),
      krs: objective.krs.length
    };
    if (!byDept.has(objective.dept)) byDept.set(objective.dept, []);
    byDept.get(objective.dept).push(roll);
  }

  const problems = [];
  for (const stat of tree.deptStats) {
    const objs = byDept.get(stat.id);
    if (!objs) {
      problems.push(`deptStats trae ${stat.id}, que no existe en la base`);
      continue;
    }
    const expected = {
      pct: mean(objs, (o) => o.frac) * 100,
      score: mean(objs, (o) => o.score),
      scoreTarget: mean(objs, (o) => o.scoreTarget),
      objs: objs.length,
      krs: objs.reduce((a, o) => a + o.krs, 0)
    };
    for (const [key, tol] of [['pct', 0.05], ['score', 0.005], ['scoreTarget', 0.005],
      ['objs', 0], ['krs', 0]]) {
      if (Math.abs(Number(stat[key]) - expected[key]) > tol) {
        problems.push(
          `${stat.id}.${key}: datasource ${stat[key]}, seccion 5 da ${expected[key].toFixed(4)}`
        );
      }
    }
  }
  if (byDept.size !== tree.deptStats.length) {
    problems.push(`deptStats devolvio ${tree.deptStats.length} filas, la base tiene ${byDept.size}`);
  }
  // ritmo esperado = dia / dias del ciclo; el dia va acotado al ciclo, no puede pasarse.
  const days =
    Math.round((Date.parse(tree.cycle.dateto) - Date.parse(tree.cycle.datefrom)) / 86400000) + 1;
  if (tree.cycle.days !== days) problems.push(`cycle.days ${tree.cycle.days}, el rango da ${days}`);

  // Every KR the UI draws must produce an avance the rail can actually place.
  for (const kr of tree.krs) {
    const span = kr.target - kr.base;
    const p = span === 0
      ? (kr.current >= kr.target ? 100 : 0)
      : clamp(((kr.current - kr.base) / span) * 100, 0, 100);
    if (!Number.isFinite(p)) problems.push(`el KR "${kr.title}" da un avance no finito`);
    if (kr.score < 0 || kr.score > 1 || kr.scoreTarget < 0 || kr.scoreTarget > 1) {
      problems.push(`el KR "${kr.title}" tiene score fuera de [0, 1]`);
    }
  }

  return problems.length
    ? fail('W6', 'formulas de la seccion 5', problems.join('; '))
    : pass('W6', 'formulas de la seccion 5',
      `${tree.deptStats.length} rollups, el ritmo del ciclo y ${tree.krs.length} avances ` +
      'coinciden con el calculo independiente');
}

export default async function (ctx) {
  await gateTreeContract(ctx);
  await gateFilterInDatasource(ctx);
  await gateFormulas(ctx);
}
