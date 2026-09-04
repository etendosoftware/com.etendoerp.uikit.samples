/*
 * ETOKRS_Review -- the quarterly OKR review, built on com.etendoerp.uikit.
 *
 * This is the reference sample: it exists to be read. Every number on screen is defined in
 * section 5 of modules/com.etendoerp.uikit/docs/samples/okr-review.md, and the two instruments in
 * section 4. If this file and that document disagree, gate G8 fails.
 *
 * The one rule worth restating here: percentage and score are not derived from each other.
 * Percentage measures the metric; score is the owner's judgement that moving the metric moved the
 * business. The gap between them is the conversation the meeting is for.
 */
(function () {
  'use strict';

  var K = OB.UIKit;
  var html = K.html;
  var raw = K.raw;

  K.datasource('ETOKRS_ReviewTree', { action: 'com.etendoerp.uikit.samples.okr.ReviewTree' });
  K.datasource('ETOKRS_Checkins', { action: 'com.etendoerp.uikit.samples.okr.Checkins' });

  var CONFIDENCE = { HIGH: 'alta', MED: 'media', LOW: 'baja' };
  var STATE_LABEL = { ok: 'en ritmo', risk: 'en riesgo', bad: 'fuera de ritmo' };
  var TABS = [
    { id: 'obj', label: 'Objetivos' },
    { id: 'kr', label: 'Resultados clave' },
    { id: 'upd', label: 'Actualizaciones' }
  ];
  var SORTS = [
    { id: 'pace', label: 'desvío de ritmo' },
    { id: 'pct', label: 'avance' },
    { id: 'gap', label: 'brecha de score' }
  ];

  /* ------------------------------------------------- the authoritative maths */

  /**
   * Progress towards the target, 0-100. Works unchanged when lower is better: for churn going
   * 4.1% -> 2.0% both deltas are negative and the quotient comes out positive. Never special-case
   * the direction.
   */
  function progress(kr) {
    var span = kr.target - kr.base;
    if (span === 0) {
      return kr.current >= kr.target ? 100 : 0;
    }
    return K.clamp(((kr.current - kr.base) / span) * 100, 0, 100);
  }

  /** Where the quarter should be today, as a percentage of its length. */
  function pace(cycle) {
    return cycle && cycle.days ? (cycle.day / cycle.days) * 100 : 0;
  }

  /** On pace at or above expected, at risk within 12 points, off pace beyond that. */
  function stateOf(deviation) {
    return deviation >= 0 ? 'ok' : deviation >= -12 ? 'risk' : 'bad';
  }

  /** Weighted mean of a list; weight defaults to 1. Used for every rollup. */
  function rollup(list, value) {
    var weight = 0;
    var total = 0;
    list.forEach(function (item) {
      var w = item.weight || 1;
      weight += w;
      total += value(item) * w;
    });
    return weight === 0 ? 0 : total / weight;
  }

  /* ------------------------------------------------------------- formatting */

  function pct(n) {
    return Math.round(n) + '%';
  }

  /** Drops the trailing zeros a numeric(0,0) column would otherwise show as "520.0". */
  function num(n, unit) {
    if (n === null || n === undefined) {
      return '—';
    }
    var rounded = Math.abs(n) >= 100 ? Math.round(n) : Math.round(n * 100) / 100;
    return unit ? rounded + ' ' + unit : String(rounded);
  }

  function score(n) {
    return n.toFixed(2);
  }

  /* ----------------------------------------------------------------- regions */

  function filtersRegion(s, d) {
    var tree = d.tree;
    var cycle = tree.cycle;
    var quarters = tree.cycles.map(function (c) {
      var current = cycle && c.id === cycle.id;
      return html`<button type="button" class="okr-seg-item" data-cycle="${c.id}"
          aria-pressed="${current ? 'true' : 'false'}" ${raw(c.hasData ? '' : 'data-empty="1"')}
          >${c.name}</button>`;
    });
    var chips = [{ id: 'all', name: 'Todos', lead: '' }].concat(tree.depts).map(function (dept) {
      var current = s.dept === dept.id;
      return html`<button type="button" class="okr-chip" data-dept="${dept.id}"
          aria-pressed="${current ? 'true' : 'false'}">${dept.name}</button>`;
    });
    var elapsed = pace(cycle);
    return html`
      <div class="okr-bar">
        <div class="okr-seg" role="group" aria-label="Trimestre">${quarters}</div>
        <div class="okr-clock">
          <span class="okr-clock-num">${cycle ? 'día ' + cycle.day + ' de ' + cycle.days : '—'}</span>
          <span class="okr-clock-sub">${pct(elapsed)} del trimestre transcurrido</span>
        </div>
      </div>
      <div class="okr-chips" role="group" aria-label="Departamento">${chips}</div>`;
  }

  function railRegion(s, d) {
    var elapsed = pace(d.tree.cycle);
    var stats = {};
    (d.tree.deptStats || []).forEach(function (row) {
      stats[row.id] = row;
    });
    var cards = d.tree.depts.map(function (dept) {
      var st = stats[dept.id] || { pct: 0, score: 0, scoreTarget: 0, objs: 0, krs: 0 };
      var deviation = st.pct - elapsed;
      var flavour = stateOf(deviation);
      var selected = s.dept === dept.id;
      return html`
        <button type="button" class="okr-card${raw(selected ? ' is-on' : '')}"
            data-dept="${dept.id}" aria-pressed="${selected ? 'true' : 'false'}">
          <span class="okr-card-head">
            <span class="okr-card-name">${dept.name}</span>
            ${K.badge(pct(st.pct), flavour)}
          </span>
          ${K.rail(st.pct, elapsed, flavour)}
          <span class="okr-card-foot">
            ${K.meter(st.score, st.scoreTarget)}
            <span class="okr-card-score">${score(st.score)} <em>/ ${score(st.scoreTarget)}</em></span>
          </span>
          <span class="okr-card-meta">${st.objs} objetivos · ${st.krs} KR · ${dept.lead}</span>
        </button>`;
    });
    return html`<div class="okr-rail">${cards}</div>`;
  }

  function agendaRegion(s, d) {
    var elapsed = pace(d.tree.cycle);
    var byObj = index(d.tree.objs);
    var behind = d.tree.krs
      .map(function (kr) {
        return { kr: kr, deviation: progress(kr) - elapsed };
      })
      .sort(function (a, b) {
        return a.deviation - b.deviation;
      })
      .slice(0, 4);
    if (behind.length === 0) {
      return '';
    }
    var items = behind.map(function (item, i) {
      var kr = item.kr;
      var flavour = stateOf(item.deviation);
      var parent = byObj[kr.obj];
      return html`
        <li class="okr-agenda-item">
          <span class="okr-agenda-rank">${i + 1}</span>
          <span class="okr-agenda-body">
            <span class="okr-agenda-title">${kr.title}</span>
            <span class="okr-agenda-meta">${parent ? parent.title : ''} · ${kr.owner}</span>
            ${K.rail(progress(kr), elapsed, flavour)}
          </span>
          <span class="okr-agenda-num">
            ${K.badge(Math.round(item.deviation) + ' pts', flavour)}
            <span class="okr-agenda-sub">${STATE_LABEL[flavour]}</span>
          </span>
        </li>`;
    });
    return html`
      <section class="okr-agenda">
        <h2 class="okr-h2">Lo que hay que discutir<span>los cuatro KR más lejos del ritmo</span></h2>
        <ol class="okr-agenda-list">${items}</ol>
      </section>`;
  }

  function panelRegion(s, d) {
    var tabs = TABS.map(function (tab) {
      return html`<button type="button" class="okr-tab" data-tab="${tab.id}"
          aria-pressed="${s.tab === tab.id ? 'true' : 'false'}">${tab.label}</button>`;
    });
    var sorts =
      s.tab === 'upd'
        ? ''
        : html`<div class="okr-sort">ordenar por ${SORTS.map(function (sort) {
            return html`<button type="button" class="okr-sort-item" data-sort="${sort.id}"
                aria-pressed="${s.sort === sort.id ? 'true' : 'false'}">${sort.label}</button>`;
          })}</div>`;
    var body =
      s.tab === 'obj' ? objectivesTab(s, d) : s.tab === 'kr' ? krTab(s, d) : updatesTab(s, d);
    return html`
      <div class="okr-panel-head">
        <div class="okr-tabs" role="group" aria-label="Vista">${tabs}</div>
        ${sorts}
      </div>
      <div class="okr-panel-body">${body}</div>`;
  }

  /* -------------------------------------------------------------------- tabs */

  function objectivesTab(s, d) {
    var elapsed = pace(d.tree.cycle);
    var byDept = index(d.tree.depts);
    var krsByObj = group(d.tree.krs, 'obj');
    var rows = d.tree.objs.map(function (obj) {
      var children = krsByObj[obj.id] || [];
      var objPct = rollup(children, progress);
      var objScore = rollup(children, function (kr) {
        return kr.score;
      });
      var deviation = objPct - elapsed;
      var flavour = stateOf(deviation);
      return { obj: obj, children: children, pct: objPct, score: objScore, deviation: deviation, state: flavour };
    });
    sortRows(rows, s.sort, function (r) {
      return { pace: r.deviation, pct: r.pct, gap: r.score - r.obj.scoreTarget };
    });
    if (rows.length === 0) {
      return empty('Este trimestre no tiene objetivos cargados.');
    }
    return rows
      .map(function (r) {
        var open = !!s.open[r.obj.id];
        var dept = byDept[r.obj.dept];
        return html`
          <article class="okr-obj${raw(open ? ' is-open' : '')}">
            <button type="button" class="okr-obj-head" data-obj="${r.obj.id}"
                aria-expanded="${open ? 'true' : 'false'}">
              <span class="okr-obj-caret" aria-hidden="true"></span>
              <span class="okr-obj-main">
                <span class="okr-obj-title">${r.obj.title}</span>
                <span class="okr-obj-meta">${dept ? dept.name : ''} · ${r.obj.owner}
                  · ${r.children.length} KR</span>
              </span>
              <span class="okr-obj-nums">
                <span class="okr-obj-pct">${pct(r.pct)}</span>
                ${K.rail(r.pct, elapsed, r.state)}
                <span class="okr-obj-scores">${K.meter(r.score, r.obj.scoreTarget)}
                  <em>${score(r.score)} / ${score(r.obj.scoreTarget)}</em></span>
              </span>
              ${K.badge(STATE_LABEL[r.state], r.state)}
            </button>
            ${open ? krTable(r.children, elapsed) : ''}
          </article>`;
      });
  }

  function krTab(s, d) {
    var elapsed = pace(d.tree.cycle);
    var rows = d.tree.krs.map(function (kr) {
      var p = progress(kr);
      return { kr: kr, pct: p, deviation: p - elapsed, state: stateOf(p - elapsed) };
    });
    sortRows(rows, s.sort, function (r) {
      return { pace: r.deviation, pct: r.pct, gap: r.kr.score - r.kr.scoreTarget };
    });
    return rows.length === 0
      ? empty('Sin resultados clave para este filtro.')
      : krTable(
          rows.map(function (r) {
            return r.kr;
          }),
          elapsed
        );
  }

  function krTable(krs, elapsed) {
    var rows = krs.map(function (kr) {
      var p = progress(kr);
      var flavour = stateOf(p - elapsed);
      return html`
        <tr>
          <td class="okr-t-title">
            <span>${kr.title}</span>
            <em>${kr.owner} · confianza ${CONFIDENCE[kr.confidence] || kr.confidence}${raw(
        kr.weight > 1 ? ' · peso ' + num(kr.weight) : ''
      )}</em>
          </td>
          <td class="okr-t-val">${num(kr.base, kr.unit)}</td>
          <td class="okr-t-val">${num(kr.current, kr.unit)}</td>
          <td class="okr-t-val">${num(kr.target, kr.unit)}</td>
          <td class="okr-t-rail">${K.rail(p, elapsed, flavour)}<em>${pct(p)}</em></td>
          <td class="okr-t-score">${K.meter(kr.score, kr.scoreTarget)}
            <em>${score(kr.score)} / ${score(kr.scoreTarget)}</em></td>
        </tr>`;
    });
    return html`
      <div class="okr-tablewrap">
        <table class="okr-table">
          <thead>
            <tr>
              <th scope="col">Resultado clave</th>
              <th scope="col">Base</th>
              <th scope="col">Actual</th>
              <th scope="col">Meta</th>
              <th scope="col">Avance contra ritmo</th>
              <th scope="col">Score / objetivo</th>
            </tr>
          </thead>
          <tbody>${rows}</tbody>
        </table>
      </div>`;
  }

  function updatesTab(s, d) {
    var feed = (d.updates && d.updates.checkins) || [];
    if (feed.length === 0) {
      return empty('Todavía nadie registró una actualización en este trimestre.');
    }
    var items = feed.map(function (ci) {
      var moved = ci.valueFrom !== null && ci.valueTo !== null && ci.valueFrom !== ci.valueTo;
      return html`
        <li class="okr-upd">
          <span class="okr-upd-date">${ci.date}</span>
          <span class="okr-upd-body">
            <span class="okr-upd-title">${ci.krTitle}</span>
            <span class="okr-upd-move">${ci.author} ·
              ${raw(
                moved
                  ? K.esc(num(ci.valueFrom, ci.unit)) +
                      ' <b>&rarr;</b> ' +
                      K.esc(num(ci.valueTo, ci.unit))
                  : 'sin movimiento'
              )}
              · confianza ${CONFIDENCE[ci.confidence] || ci.confidence}</span>
            <span class="okr-upd-note">${ci.note}</span>
          </span>
        </li>`;
    });
    return html`<ol class="okr-updates">${items}</ol>`;
  }

  /* ----------------------------------------------------------------- helpers */

  function index(list) {
    var out = {};
    (list || []).forEach(function (item) {
      out[item.id] = item;
    });
    return out;
  }

  function group(list, key) {
    var out = {};
    (list || []).forEach(function (item) {
      (out[item[key]] = out[item[key]] || []).push(item);
    });
    return out;
  }

  /** Ascending for deviation and score gap -- worst first, which is the point of the screen. */
  function sortRows(rows, sort, keys) {
    rows.sort(function (a, b) {
      var ka = keys(a);
      var kb = keys(b);
      return sort === 'pct' ? kb.pct - ka.pct : ka[sort] - kb[sort];
    });
  }

  function empty(message) {
    return html`<p class="okr-empty">${message}</p>`;
  }

  /* -------------------------------------------------------------- the view */

  K.defineView({
    name: 'ETOKRS_Review',
    title: 'ETOKRS_ReviewTitle',
    regions: ['filters', 'rail', 'agenda', 'panel'],
    keepScroll: ['panel'],
    state: { cycle: null, dept: 'all', tab: 'obj', sort: 'pace', open: {} },
    data: { tree: 'ETOKRS_ReviewTree', updates: 'ETOKRS_Checkins' },

    // Only these two reach the server, so switching tab or sort never costs a request.
    params: function (s) {
      return { cycle: s.cycle, dept: s.dept };
    },

    render: function (s, d) {
      if (!d.tree || !d.tree.cycle) {
        return { filters: empty('No hay trimestres definidos.') };
      }
      return {
        filters: filtersRegion(s, d),
        rail: railRegion(s, d),
        agenda: agendaRegion(s, d),
        panel: panelRegion(s, d)
      };
    },

    on: {
      'click [data-cycle]': function (ctx, e, el) {
        ctx.set({ cycle: el.dataset.cycle, open: {} });
      },
      'click [data-dept]': function (ctx, e, el) {
        ctx.set({ dept: el.dataset.dept, open: {} });
      },
      'click [data-tab]': function (ctx, e, el) {
        ctx.set({ tab: el.dataset.tab });
      },
      'click [data-sort]': function (ctx, e, el) {
        ctx.set({ sort: el.dataset.sort });
      },
      'click [data-obj]': function (ctx, e, el) {
        ctx.toggle('open', el.dataset.obj);
      }
    }
  });
})();
