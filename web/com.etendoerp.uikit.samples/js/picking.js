/*
 * ETDEMO_Picking -- sales order preparation and confirm, built on com.etendoerp.uikit.
 *
 * The only window in the sample kit that mutates a real ERP document. Everything else here reads;
 * this one calls the same ProcessOrderUtil the standard Sales Order window's Book button calls,
 * which is why the whole screen is arranged around not doing that by accident.
 *
 * Two controls, deliberately not one. "Simular" is the primary button and the default in the
 * protocol: the payload carries dryRun and the server treats an absent or malformed flag as a
 * simulation, so a request that loses a field cannot become a write. Executing for real needs
 * arming first, and the armed button is a separate, differently coloured control that also asks
 * for a confirmation and disarms itself afterwards.
 *
 * Section 0 of modules/com.etendoerp.uikit/docs/samples/order-picking.md states what this
 * instance's data really is before anyone reads a number off this screen, and section 3 is the
 * authoritative table of what ignores what.
 *
 * The asymmetry in one line: the status chips count every sales order this role may see, with
 * the search box, the page and the selected order all ignored, and only the order list and the
 * line detail narrow. A counter that moved when the reader clicked an order could not answer
 * "how many drafts are left", which is the only question a preparation screen exists for.
 *
 * Nothing here filters, counts, sorts, pages or decides a permission in the browser. The chips
 * hand two strings to the datasource; the ilike, the order by, the limit/offset, the availability
 * sums and the semaphore are SQL, and the write re-reads its target under scope before touching
 * it -- see fact F6 in docs/guides/actions-and-permissions.md.
 */
(function () {
  'use strict';

  var K = OB.UIKit;
  var html = K.html;
  var raw = K.raw;

  K.datasource('ETDEMO_Picking', {
    action: 'com.etendoerp.uikit.samples.picking.PickList'
  });

  /* How long the search box waits after the last keystroke before it becomes a query. */
  var SEARCH_MS = 250;

  var PAGE_SIZE = 25;

  /** Document status to badge colour. Only a draft asks the reader for anything. */
  var STATUS_TONE = { DR: 'risk', CO: 'ok', CL: 'flat', VO: 'bad' };

  /**
   * Line semaphore to badge colour. The tones themselves are computed in SQL, not here: a gate
   * has to be able to recompute them from c_orderline and m_storage_detail without running
   * JavaScript, and a rule that lives in two languages is a rule that will disagree with itself.
   */
  var TONE = { ok: 'ok', partial: 'risk', short: 'bad', done: 'flat', na: 'flat' };

  /**
   * One debounced setter per open view, keyed by the state object the runtime creates once per
   * instance. A single module-level debounce would be shared by two tabs of the same window and
   * the second typist would cancel the first one's pending search.
   */
  var searchers = new WeakMap();

  function searcher(ctx) {
    var fn = searchers.get(ctx.state);
    if (!fn) {
      fn = K.debounce(function (text) {
        ctx.set({ q: text, page: 1 });
      }, SEARCH_MS);
      searchers.set(ctx.state, fn);
    }
    return fn;
  }

  /* ----------------------------------------------------------------- helpers */

  function count(n) {
    return K.fmt(n || 0, 'int');
  }

  function qty(value, unit) {
    var text = K.fmt(value || 0, 'qty');
    return unit ? text + ' ' + unit : text;
  }

  function statusBadge(status) {
    return K.badge(K.t('ETDEMO_Picking' + status), STATUS_TONE[status] || 'flat');
  }

  /** Only stocked lines can be short of anything, so only they are counted for the light. */
  function semaphore(lines) {
    var out = { stocked: 0, services: 0, ok: 0, partial: 0, short: 0, done: 0 };
    lines.forEach(function (l) {
      if (l.tone === 'na') {
        out.services += 1;
        return;
      }
      out.stocked += 1;
      out[l.tone] += 1;
    });
    return out;
  }

  /* ---------------------------------------------------------------- the write */

  /*
   * The write. No declared refetch: a simulation changed nothing, so reloading the list after one
   * would be a recount of 721 orders to redraw the same screen. The callback refetches only when
   * the server reports that something actually moved.
   *
   * The payload carries orderId from state and never from the clicked element, and it carries
   * action so the server can refuse a mismatch -- ConfirmOrder checks it against its own
   * whitelist and never obeys it. A precondition asserted by the caller is not a check.
   */
  K.defineAction({
    name: 'confirm',
    action: 'com.etendoerp.uikit.samples.picking.ConfirmOrder',
    payload: function (s, arg) {
      return { orderId: s.order, action: arg.action, dryRun: arg.dryRun !== false };
    },
    // Only for the real run. A confirmation dialog on every simulation would teach the reader to
    // dismiss it without reading, which is exactly the habit that makes the real one useless.
    confirm: function (s, arg) {
      return arg.dryRun === false ? K.t('ETDEMO_PickingAsk') : '';
    },
    // last is presentation and deliberately outside params(): mutating a param key here would
    // change a datasource signature and provoke a refetch on every click and every rollback.
    optimistic: function (s, arg) {
      s.last = {
        phase: 'sending',
        action: arg.action,
        dryRun: arg.dryRun !== false
      };
    }
  });

  /* ------------------------------------------------------------------ the bar */

  function controls(s, order) {
    var next = order.nextAction || '';
    if (!next) {
      return html`<p class="pck-none">${K.t('ETDEMO_PickingNoAction')}</p>`;
    }
    var label = K.t('ETDEMO_PickingAct' + next);
    var dry = html`<button type="button" class="uik-chip pck-dry" data-dry="${next}"
      >${K.t('ETDEMO_PickingDry')} · ${label}</button>`;
    if (!s.armed) {
      return html`<div class="pck-controls">
        ${dry}
        <button type="button" class="uik-chip" data-arm="1"
          >${K.t('ETDEMO_PickingArm')}</button>
        <span class="pck-hint uik-flat">${K.t('ETDEMO_PickingDryHint')}</span>
      </div>`;
    }
    return html`<div class="pck-controls pck-live">
      ${dry}
      <button type="button" class="pck-danger" data-go="${next}"
        >${K.t('ETDEMO_PickingGo')} · ${label}</button>
      <button type="button" class="uik-chip" data-disarm="1"
        >${K.t('ETDEMO_PickingDisarm')}</button>
      <span class="pck-armed uik-bad">${K.t('ETDEMO_PickingArmed')}</span>
    </div>`;
  }

  /**
   * The result of the last attempt, and the one place the ERP speaks for itself. A rejected
   * confirm prints OBError.getMessage() as core wrote it -- "The order cannot be booked because
   * it has no lines" -- with no prefix, no rewrite and no translation of our own. The window's
   * opinion of what went wrong would be a guess; core's is the answer.
   */
  function verdict(s) {
    var l = s.last;
    if (!l) {
      return html`<p class="pck-verdict uik-flat">${K.t('ETDEMO_PickingIdle')}</p>`;
    }
    if (l.phase === 'sending') {
      return html`<p class="pck-verdict">${K.t('ETDEMO_PickingSending')}</p>`;
    }
    if (l.phase === 'error') {
      return html`<div class="pck-verdict pck-fail">
        ${K.badge(K.t('ETDEMO_PickingRejected'), 'bad')}
        <span class="pck-erp">${K.t('ETDEMO_PickingErpSaid')}:</span>
        <q class="pck-msg">${l.message}</q>
      </div>`;
    }
    var tone = l.dryRun ? 'flat' : l.applied ? 'ok' : 'risk';
    var head = l.dryRun ? 'ETDEMO_PickingSimulated'
      : l.applied ? 'ETDEMO_PickingApplied' : 'ETDEMO_PickingUnchanged';
    var allowed = (l.allowed || []).join(' ');
    return html`<div class="pck-verdict">
      ${K.badge(K.t(head), tone)}
      <span>${l.documentNo} · ${l.action}</span>
      <span class="pck-delta">${K.t('ETDEMO_PickingBefore')} ${statusBadge(l.before)}
        → ${K.t('ETDEMO_PickingAfter')} ${statusBadge(l.after)}</span>
      ${allowed ? html`<span class="pck-allowed uik-flat"
        >${K.t('ETDEMO_PickingCoreAllows')}: ${allowed}</span>` : ''}
      ${l.message ? html`<q class="pck-msg">${l.message}</q>` : ''}
    </div>`;
  }

  function barRegion(s, d) {
    var order = d.order;
    var meta = d.meta || {};
    return html`<div class="pck-bar">
      <h2 class="pck-title">${K.t('ETDEMO_PickingTitle')}</h2>
      <p class="pck-intro">${K.t('ETDEMO_PickingIntro')}</p>
      <p class="pck-asof uik-flat">${K.t('ETDEMO_PickingAsOf')}
        ${K.fmt(meta.asOf, 'date')} (${meta.asOfSource || ''})</p>
      ${order
        ? html`<div class="pck-target">
            <b>${order.documentNo}</b> ${statusBadge(order.status)}
            <span>${order.bp}</span>
          </div>${controls(s, order)}`
        : html`<p class="pck-none">${s.order
            ? K.t('ETDEMO_PickingGone') : K.t('ETDEMO_PickingChoose')}</p>`}
      <h3 class="pck-result">${K.t('ETDEMO_PickingResult')}</h3>
      ${verdict(s)}
    </div>`;
  }

  /* ----------------------------------------------------------------- the list */

  function chips(s, d) {
    var buckets = (d.statuses || []).map(function (b) {
      return html`<button type="button" class="uik-chip" data-status="${b.status}"
        aria-pressed="${s.status === b.status ? 'true' : 'false'}"
        >${K.t('ETDEMO_Picking' + b.status)} <b>${count(b.n)}</b></button>`;
    });
    var all = html`<button type="button" class="uik-chip" data-status=""
      aria-pressed="${s.status ? 'false' : 'true'}"
      >${K.t('ETDEMO_PickingAll')} <b>${count(d.total)}</b></button>`;
    return html`<div class="pck-chips">${all}${buckets}</div>`;
  }

  function pager(s, d) {
    var p = d.page || {};
    var limit = p.limit || PAGE_SIZE;
    var page = Math.floor((p.offset || 0) / limit) + 1;
    var pages = Math.max(1, Math.ceil((p.matched || 0) / limit));
    return html`<div class="uik-pager">
      <button type="button" data-page="${page - 1}" ${raw(page <= 1 ? 'disabled' : '')}
        >${K.t('ETDEMO_PickingPrev')}</button>
      <span>${count(page)} / ${count(pages)}</span>
      <button type="button" data-page="${page + 1}" ${raw(page >= pages ? 'disabled' : '')}
        >${K.t('ETDEMO_PickingNext')}</button>
      <span class="pck-matched">${count(p.matched)} ${K.t('ETDEMO_PickingMatched')}</span>
    </div>`;
  }

  function listRegion(s, d) {
    var rows = (d.orders || []).map(function (o) {
      return html`<tr aria-selected="${s.order === o.id ? 'true' : 'false'}">
        <td><button type="button" class="pck-pick" data-order="${o.id}"
          >${o.documentNo}</button></td>
        <td>${o.bp}</td>
        <td>${K.fmt(o.date, 'date')}</td>
        <td data-num>${K.fmt(o.total, 'amount')}</td>
        <td data-num>${count(o.lines)}</td>
        <td>${statusBadge(o.status)}</td>
        <td>${o.nextAction
          ? html`<span class="pck-next">${K.t('ETDEMO_PickingAct' + o.nextAction)}</span>`
          : html`<span class="uik-flat">—</span>`}</td>
      </tr>`;
    });
    return html`<div class="pck-list">
      ${chips(s, d)}
      <input type="search" class="pck-input" data-q="1" value="${s.q}"
        placeholder="${K.t('ETDEMO_PickingSearch')}"
        aria-label="${K.t('ETDEMO_PickingSearch')}">
      ${rows.length
        ? html`<table class="uik-table">
            <thead><tr>
              <th>${K.t('ETDEMO_PickingOrders')}</th>
              <th>${K.t('ETDEMO_PickingCustomer')}</th>
              <th>${K.t('ETDEMO_PickingDate')}</th>
              <th data-num>${K.t('ETDEMO_PickingTotal')}</th>
              <th data-num>${K.t('ETDEMO_PickingLines')}</th>
              <th>${K.t('ETDEMO_PickingStatus')}</th>
              <th>${K.t('ETDEMO_PickingWouldRun')}</th>
            </tr></thead>
            <tbody>${rows}</tbody>
          </table>`
        : html`<p class="pck-none">${K.t('ETDEMO_PickingNoOrders')}</p>`}
      ${pager(s, d)}
    </div>`;
  }

  /* --------------------------------------------------------------- the detail */

  function summary(sem) {
    if (!sem.stocked) {
      return html`<p class="pck-sem uik-flat">${count(sem.services)}
        ${K.t('ETDEMO_PickingServices')}</p>`;
    }
    var covered = sem.ok + sem.done;
    return html`<div class="pck-sem">
      ${K.meter(covered / sem.stocked, 1)}
      <span>${count(covered)} / ${count(sem.stocked)}
        ${K.t('ETDEMO_PickingStocked')}</span>
      ${sem.partial ? K.badge(count(sem.partial) + ' ' + K.t('ETDEMO_PickingTonePartial'),
        'risk') : ''}
      ${sem.short ? K.badge(count(sem.short) + ' ' + K.t('ETDEMO_PickingToneShort'), 'bad') : ''}
      ${sem.services ? html`<span class="uik-flat">${count(sem.services)}
        ${K.t('ETDEMO_PickingServices')}</span>` : ''}
    </div>`;
  }

  function detailRegion(s, d) {
    var order = d.order;
    if (!order) {
      return html`<p class="pck-none">${s.order
        ? K.t('ETDEMO_PickingGone') : K.t('ETDEMO_PickingChoose')}</p>`;
    }
    var lines = d.lines || [];
    var tab = (d.meta || {}).orderTab;
    var rows = lines.map(function (l) {
      return html`<tr data-tone="${l.tone}">
        <td data-num>${count(l.line)}</td>
        <td>${l.code}</td>
        <td>${l.product}</td>
        <td data-num>${qty(l.ordered, l.uom)}</td>
        <td data-num>${qty(l.delivered, l.uom)}</td>
        <td data-num>${qty(l.pending, l.uom)}</td>
        <td data-num>${l.tone === 'na'
          ? html`<span class="uik-flat">—</span>` : qty(l.onHand, l.uom)}</td>
        <td>${K.badge(K.t('ETDEMO_PickingTone' + l.tone.charAt(0).toUpperCase()
          + l.tone.slice(1)), TONE[l.tone] || 'flat')}</td>
      </tr>`;
    });
    return html`<div class="pck-detail">
      <div class="pck-head">
        <b>${order.documentNo}</b> ${statusBadge(order.status)}
        <span>${order.docType}</span>
        <span>${K.t('ETDEMO_PickingWarehouse')}: ${order.warehouse}</span>
        <span>${K.t('ETDEMO_PickingTotal')}: ${K.fmt(order.total, 'amount')}</span>
        ${tab
          ? html`<a href="javascript:void(0)" data-open="${order.id}" data-tab="${tab}"
              >${K.t('ETDEMO_PickingOpenOrder')}</a>`
          : ''}
      </div>
      ${summary(semaphore(lines))}
      ${rows.length
        ? html`<table class="uik-table pck-lines">
            <thead><tr>
              <th data-num>${K.t('ETDEMO_PickingLine')}</th>
              <th>${K.t('ETDEMO_PickingProduct')}</th>
              <th></th>
              <th data-num>${K.t('ETDEMO_PickingOrdered')}</th>
              <th data-num>${K.t('ETDEMO_PickingDelivered')}</th>
              <th data-num>${K.t('ETDEMO_PickingPending')}</th>
              <th data-num>${K.t('ETDEMO_PickingOnHand')}</th>
              <th></th>
            </tr></thead>
            <tbody>${rows}</tbody>
          </table>`
        : html`<p class="pck-none">${K.t('ETDEMO_PickingNoLines')}</p>`}
    </div>`;
  }

  /* ------------------------------------------------------------------ the view */

  /**
   * Sends one attempt and records what came back. Shared by the simulation and the real run,
   * because the only difference between them is one boolean in the payload -- which is the point
   * the screen is trying to make.
   *
   * No disabled attribute and no flag of our own: ctx.run returns false when the same (name, arg)
   * is already in flight, so the second click of a double click never leaves the browser. See
   * docs/guides/actions-and-permissions.md section 2.
   */
  function attempt(ctx, action, dryRun) {
    ctx.run('confirm', { action: action, dryRun: dryRun }, function (err, data) {
      if (err) {
        // The runtime restored the pre-click state before calling this, so setting last here
        // wins over the rollback rather than racing it.
        ctx.set({
          armed: false,
          last: { phase: 'error', code: err.code, message: err.message, action: action }
        });
        return;
      }
      ctx.set({
        armed: false,
        last: {
          phase: 'done',
          documentNo: data.documentNo,
          action: data.action,
          dryRun: data.dryRun,
          applied: data.applied,
          before: data.before,
          after: data.after,
          allowed: data.allowed,
          message: data.message || ''
        }
      });
      // Only a real change is worth 721 recounted orders.
      if (data.applied) {
        ctx.refetch('pick');
      }
    });
  }

  K.defineView({
    name: 'ETDEMO_Picking',
    title: 'ETDEMO_PickingTitle',
    regions: ['bar', 'list', 'detail'],
    loading: 'detail',
    keepScroll: ['list'],
    state: {
      status: '',
      q: '',
      page: 1,
      limit: PAGE_SIZE,
      order: '',
      armed: false,
      last: null
    },
    data: { pick: 'ETDEMO_Picking' },

    // Only the five keys the server needs. armed and last are presentation and must stay out:
    // last is mutated optimistically, and a signature change there would refetch on every click
    // and again on every rollback.
    params: function (s) {
      return {
        status: s.status,
        q: s.q,
        order: s.order,
        page: s.page,
        limit: s.limit
      };
    },

    render: function (s, d) {
      var pick = d.pick || {};
      return {
        bar: barRegion(s, pick),
        list: listRegion(s, pick),
        detail: detailRegion(s, pick)
      };
    },

    on: {
      'click [data-order]': function (ctx, e, el) {
        // Selecting a different order disarms: an arm belongs to the document it was armed for.
        ctx.set({ order: el.dataset.order, armed: false });
      },
      'click [data-status]': function (ctx, e, el) {
        ctx.set({ status: el.dataset.status, page: 1 });
      },
      'input [data-q]': function (ctx, e, el) {
        searcher(ctx)(el.value);
      },
      'click [data-page]': function (ctx, e, el) {
        var page = parseInt(el.dataset.page, 10);
        if (page >= 1) {
          ctx.set({ page: page });
        }
      },
      'click [data-arm]': function (ctx) {
        ctx.set({ armed: true });
      },
      'click [data-disarm]': function (ctx) {
        ctx.set({ armed: false });
      },
      'click [data-dry]': function (ctx, e, el) {
        attempt(ctx, el.dataset.dry, true);
      },
      // The only path that can mutate anything, and it re-checks the arm: an element left over
      // from a previous paint cannot fire a real run on a disarmed screen.
      'click [data-go]': function (ctx, e, el) {
        if (!ctx.state.armed) {
          return;
        }
        attempt(ctx, el.dataset.go, false);
      },
      'click [data-open]': function (ctx, e, el) {
        // The tab id was resolved in SQL by the datasource. A null one never gets a link, so the
        // only ids that reach nav() came from the dictionary.
        K.nav(el.dataset.tab, el.dataset.open);
      }
    }
  });
})();
