/*
 * ETDEMO_Alerts -- the administrator's alert inbox, built on com.etendoerp.uikit.
 *
 * The only window in the sample kit that writes, so it is the only one where defineAction, the
 * CSRF token, the optimistic repaint and the in-flight guard are exercised rather than described.
 * Section 0 of modules/com.etendoerp.uikit/docs/samples/alerts-inbox.md says what the data really
 * is before anyone reads a number off this screen, and section 3 is the authoritative table of
 * what ignores what.
 *
 * The asymmetry in one line: the status chips and the rule rail are counted over every alert this
 * role may see, with both filters ignored, and only the detail list narrows. An inbox whose
 * counters only describe what is already on screen cannot answer the one question an inbox exists
 * for -- what am I not looking at.
 *
 * Nothing here filters, counts or sorts in the browser. The chips hand two strings to the
 * datasource and every count, every order by and the limit are SQL, which is also the only place
 * a permission decision is made: see fact F6 in docs/guides/actions-and-permissions.md.
 */
(function () {
  'use strict';

  var K = OB.UIKit;
  var html = K.html;

  K.datasource('ETDEMO_Alerts', { action: 'com.etendoerp.uikit.samples.alerts.AlertInbox' });

  /*
   * The write. No refetch: the optimistic repaint already shows the new status, and reloading the
   * inbox on every acknowledgement would turn a click into a full recount of every rule -- the
   * refetch storm the optimistic path exists to avoid. The next auto-refresh reconciles.
   *
   * The payload sends the status the row is being moved to because the manifest's replayable
   * payload needs a complete body, but AckAlert never reads it: the server re-reads the row under
   * scope and consults its own whitelist. A precondition asserted by the caller is not a check.
   */
  K.defineAction({
    name: 'ack',
    action: 'com.etendoerp.uikit.samples.alerts.AckAlert',
    payload: function (s, arg) {
      return { id: arg.id, status: 'ACKNOWLEDGED' };
    },
    optimistic: function (s, arg) {
      // acked is deliberately outside params(): mutating a param key here would change a
      // datasource signature and provoke exactly the refetch this path avoids.
      s.acked[arg.id] = true;
      s.note = '';
    }
  });

  /* The polling interval, in state rather than in a constant, so the screen can say what it is
   * and the reader can slow it down. 30 s is the honest number for a table that a dictionary job
   * writes to a few times a day: fast enough that a second administrator's acknowledgement shows
   * up while you are still looking, slow enough to cost nothing. */
  var RATES = [15000, 30000, 60000];
  var DEFAULT_RATE = 30000;

  var ROW_LIMIT = 100;

  /** Status to badge colour. NEW is the only one that asks the reader for anything. */
  var TONE = {
    NEW: 'bad',
    ACKNOWLEDGED: 'risk',
    SOLVED: 'ok',
    SUPPRESSED: 'flat'
  };

  /**
   * One pending cancel function per open view, keyed by the state object the runtime creates once
   * per instance. It cannot live in state: state is snapshotted with JSON.stringify before every
   * optimistic write, and a function does not survive that round trip.
   */
  var timers = new WeakMap();

  /* --------------------------------------------------------------- refreshing */

  /**
   * Arms the next refresh, cancelling any pending one first so two arms cannot compound into two
   * timers. The callback re-arms itself, which is how a one-shot ctx.later becomes an interval
   * the runtime still owns and still cancels on destroy.
   */
  function arm(ctx) {
    stop(ctx);
    if (!ctx.state.polling) {
      return;
    }
    var cancel = ctx.later(function () {
      timers.delete(ctx.state);
      if (ctx.state.polling) {
        ctx.refetch('inbox');
        arm(ctx);
      }
    }, ctx.state.refreshMs);
    timers.set(ctx.state, cancel);
  }

  function stop(ctx) {
    var cancel = timers.get(ctx.state);
    if (cancel) {
      cancel();
      timers.delete(ctx.state);
    }
  }

  /* ------------------------------------------------------------------ rendering */

  /**
   * The optimistic correction, and the reason it is computed here and not stored: a row the user
   * just acknowledged still arrives from the server as NEW until the next refresh, so the rail
   * would keep counting it. Correcting at render time means the correction lapses by itself the
   * moment the server agrees, with no cleanup and no second source of truth.
   */
  function pending(s, d) {
    var out = { total: 0, byRule: {} };
    (d.rows || []).forEach(function (r) {
      if (r.status === 'NEW' && s.acked[r.id]) {
        out.total += 1;
        out.byRule[r.rule] = (out.byRule[r.rule] || 0) + 1;
      }
    });
    return out;
  }

  function shown(s, r) {
    return r.status === 'NEW' && s.acked[r.id] ? 'ACKNOWLEDGED' : r.status;
  }

  function count(n, delta) {
    return K.fmt(Math.max(0, n + (delta || 0)), 'int');
  }

  function barRegion(s, d) {
    var rates = RATES.map(function (ms) {
      return html`<button type="button" class="uik-chip" data-rate="${ms}"
        aria-pressed="${s.refreshMs === ms ? 'true' : 'false'}">${ms / 1000}</button>`;
    });
    var toggle = s.polling ? 'ETDEMO_AlertsPause' : 'ETDEMO_AlertsResume';
    return html`<div class="alr-bar">
      <h2 class="alr-title">${K.t('ETDEMO_AlertsTitle')}</h2>
      <p class="alr-source">${K.t('ETDEMO_AlertsSource')}</p>
      <div class="alr-rates">
        <span>${K.t('ETDEMO_AlertsRefreshEvery')}</span>${rates}
        <span>${K.t('ETDEMO_AlertsSeconds')}</span>
        <button type="button" class="uik-chip" data-polling="1">${K.t(toggle)}</button>
        <button type="button" class="uik-chip" data-reload="1">
          ${K.t('ETDEMO_AlertsReloadNow')}</button>
      </div>
      ${s.note ? html`<p class="alr-note uik-bad">${s.note}</p>` : ''}
      <p class="alr-asym">${K.t('ETDEMO_AlertsRailNote')}</p>
    </div>`;
  }

  /** Status chips and the per-rule rail. Both read counts the filter never touched. */
  function railRegion(s, d) {
    var adj = pending(s, d);
    var chips = (d.statuses || []).map(function (b) {
      var delta = b.status === 'NEW' ? -adj.total : b.status === 'ACKNOWLEDGED' ? adj.total : 0;
      return html`<button type="button" class="uik-chip" data-status="${b.status}"
        aria-pressed="${s.status === b.status ? 'true' : 'false'}"
        >${K.t('ETDEMO_Alerts' + b.status)} <b>${count(b.n, delta)}</b></button>`;
    });
    var all = html`<button type="button" class="uik-chip" data-status=""
      aria-pressed="${s.status ? 'false' : 'true'}"
      >${K.t('ETDEMO_AlertsAll')} <b>${K.fmt(d.total || 0, 'int')}</b></button>`;
    var rules = (d.rules || []).map(function (r) {
      var mine = adj.byRule[r.id] || 0;
      return html`<tr>
        <td><button type="button" class="uik-chip" data-rule="${r.id}"
          aria-pressed="${s.rule === r.id ? 'true' : 'false'}">${r.name}</button></td>
        <td data-num>${count(r.NEW, -mine)}</td>
        <td data-num>${count(r.ACKNOWLEDGED, mine)}</td>
        <td data-num>${count(r.SOLVED)}</td>
        <td data-num>${count(r.SUPPRESSED)}</td>
        <td>${r.tab
          ? html`<a href="javascript:void(0)" data-grid="${r.tab}"
              >${K.t('ETDEMO_AlertsOpen')}</a>`
          : html`<span class="uik-flat">${K.t('ETDEMO_AlertsNoTab')}</span>`}</td>
      </tr>`;
    });
    if (!rules.length) {
      return html`<p class="alr-empty">${K.t('ETDEMO_AlertsNoRules')}</p>`;
    }
    return html`<div class="alr-rail">
      <div class="alr-chips">${all}${chips}</div>
      <table class="uik-table">
        <thead><tr>
          <th>${K.t('ETDEMO_AlertsRuleHead')}</th>
          <th data-num>${K.t('ETDEMO_AlertsNEW')}</th>
          <th data-num>${K.t('ETDEMO_AlertsACKNOWLEDGED')}</th>
          <th data-num>${K.t('ETDEMO_AlertsSOLVED')}</th>
          <th data-num>${K.t('ETDEMO_AlertsSUPPRESSED')}</th>
          <th></th>
        </tr></thead>
        <tbody>${rules}</tbody>
      </table>
    </div>`;
  }

  /** The detail list, and the only region the filters reach. */
  function listRegion(s, d) {
    var rows = (d.rows || []).map(function (r) {
      var st = shown(s, r);
      var link = r.tab && r.refkey
        ? html`<a href="javascript:void(0)" data-open="${r.refkey}" data-tab="${r.tab}"
            >${r.description || r.refkey}</a>`
        : html`<span>${r.description || r.refkey}</span>`;
      return html`<tr>
        <td>${link}</td>
        <td>${r.ruleName}</td>
        <td>${r.org}</td>
        <td>${K.fmt(r.created, 'date')}</td>
        <td>${K.badge(K.t('ETDEMO_Alerts' + st), TONE[st] || 'flat')}</td>
        <td>${st === 'NEW'
          ? html`<button type="button" class="uik-chip" data-ack="${r.id}"
              >${K.t('ETDEMO_AlertsAck')}</button>`
          : html`<span class="uik-flat">${K.t('ETDEMO_AlertsAcked')}</span>`}</td>
      </tr>`;
    });
    if (!rows.length) {
      return html`<p class="alr-empty">${K.t('ETDEMO_AlertsEmpty')}</p>`;
    }
    var note = d.meta && d.meta.truncated
      ? html`<p class="alr-note">${K.t('ETDEMO_AlertsTruncated')}</p>`
      : '';
    return html`<div class="alr-list">
      <table class="uik-table">
        <thead><tr>
          <th>${K.t('ETDEMO_AlertsColAlert')}</th>
          <th>${K.t('ETDEMO_AlertsRuleHead')}</th>
          <th>${K.t('ETDEMO_AlertsColOrg')}</th>
          <th>${K.t('ETDEMO_AlertsColCreated')}</th>
          <th>${K.t('ETDEMO_AlertsStatusHead')}</th>
          <th>${K.t('ETDEMO_AlertsColAction')}</th>
        </tr></thead>
        <tbody>${rows}</tbody>
      </table>
      ${note}
    </div>`;
  }

  /* ---------------------------------------------------------------- the view */

  K.defineView({
    name: 'ETDEMO_Alerts',
    title: 'ETDEMO_AlertsTitle',
    regions: ['bar', 'rail', 'list'],
    loading: 'list',
    keepScroll: ['list'],
    state: {
      status: '',
      rule: '',
      limit: ROW_LIMIT,
      acked: {},
      refreshMs: DEFAULT_RATE,
      polling: true,
      note: ''
    },
    data: { inbox: 'ETDEMO_Alerts' },

    // Only the three keys the server needs. acked, refreshMs, polling and note are presentation
    // and must stay out: acked is mutated optimistically, and a signature change there would
    // refetch on every click and again on every rollback.
    params: function (s) {
      return { status: s.status, rule: s.rule, limit: s.limit };
    },

    render: function (s, d) {
      var inbox = d.inbox || {};
      return {
        bar: barRegion(s, inbox),
        rail: railRegion(s, inbox),
        list: listRegion(s, inbox)
      };
    },

    on: {
      // Registered before [data-rule] and [data-status] have any chance to collide; the first
      // matching rule wins, so the row button must come before anything matching its ancestors.
      'click [data-ack]': function (ctx, e, el) {
        var id = el.dataset.ack;
        // No disabled state, no flag, no guard of our own: ctx.run returns false when the same
        // (name, arg) is already in flight, so the second click of a double click never leaves
        // the browser. See docs/guides/actions-and-permissions.md section 2.
        ctx.run('ack', { id: id }, function (err, data) {
          if (err) {
            ctx.set({ note: K.t('ETDEMO_AlertsAckFailed') + ' ' + err.message });
            return;
          }
          if (data && data.changed === false) {
            ctx.set({ note: '' });
          }
        });
      },
      'click [data-status]': function (ctx, e, el) {
        ctx.set({ status: el.dataset.status });
      },
      'click [data-rule]': function (ctx, e, el) {
        ctx.set({ rule: ctx.state.rule === el.dataset.rule ? '' : el.dataset.rule });
      },
      'click [data-rate]': function (ctx, e, el) {
        ctx.set({ refreshMs: parseInt(el.dataset.rate, 10) });
        arm(ctx);
      },
      'click [data-polling]': function (ctx) {
        ctx.set({ polling: !ctx.state.polling });
        arm(ctx);
      },
      'click [data-reload]': function (ctx) {
        ctx.refetch('inbox');
        arm(ctx);
      },
      // Both drill-downs use a tab id the datasource resolved in SQL. A row without one is
      // rendered as plain text, so the only ids that reach nav() came from the dictionary.
      'click [data-open]': function (ctx, e, el) {
        K.nav(el.dataset.tab, el.dataset.open);
      },
      'click [data-grid]': function (ctx, e, el) {
        K.nav(el.dataset.grid);
      }
    },

    // activate is tabSelected, so the inbox polls only while its own tab is the visible one --
    // which is the behaviour worth having anyway. deactivate cancels; destroy needs nothing,
    // because the runtime clears every ctx.later timer itself before calling the hook.
    activate: function (ctx) {
      arm(ctx);
    },
    deactivate: function (ctx) {
      stop(ctx);
    },
    destroy: function (ctx) {
      timers.delete(ctx.state);
    }
  });
})();
