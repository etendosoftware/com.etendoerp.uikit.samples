/*
 * ETDEMO_Cash -- the receivable/payable portfolio, built on com.etendoerp.uikit.
 *
 * Everything on screen is defined in modules/com.etendoerp.uikit/docs/samples/cash-portfolio.md:
 * section 0 for why the payables side is the default, section 4 for the reference date, section 5
 * for the buckets and section 6 for the data contract. If this file and that document disagree,
 * the document is the specification.
 *
 * Three rules are worth restating here, because breaking any of them turns a cockpit into a lie:
 *
 *   1. No number is derived in the client. The buckets, the total, the exclusion count and the
 *      twelve-month series all arrive computed, because they are computed over the whole side
 *      while the table is narrowed -- which the client cannot do from the rows it was sent.
 *   2. One currency at a time, and the symbol comes from the datasource. Two currencies added
 *      together is not money.
 *   3. The reference date is on screen with its provenance. A cockpit that invents its own today
 *      is worse than one that shows you which day it is talking about.
 */
(function () {
  'use strict';

  var K = OB.UIKit;
  var html = K.html;
  var raw = K.raw;
  var t = K.t;

  K.datasource('ETDEMO_CashPortfolio', {
    action: 'com.etendoerp.uikit.samples.cash.Portfolio'
  });

  var SIDES = [
    { id: 'AP', label: 'ETDEMO_CashAP' },
    { id: 'AR', label: 'ETDEMO_CashAR' }
  ];
  var BUCKETS = [
    { id: 'cur', label: 'ETDEMO_CashBucketCur', state: 'ok' },
    { id: 'd30', label: 'ETDEMO_CashBucketD30', state: 'flat' },
    { id: 'd60', label: 'ETDEMO_CashBucketD60', state: 'risk' },
    { id: 'd90', label: 'ETDEMO_CashBucketD90', state: 'risk' },
    { id: 'd90p', label: 'ETDEMO_CashBucketD90p', state: 'bad' }
  ];
  var SOURCE_LABEL = {
    param: 'ETDEMO_CashFromParam',
    data: 'ETDEMO_CashFromData',
    today: 'ETDEMO_CashFromToday'
  };

  /* ------------------------------------------------------------------------ formatting */

  /** Money always carries the symbol the datasource returned next to the amount. */
  function money(value, cur) {
    return K.fmt(value, 'amount', { currency: cur ? cur.symbol : '' });
  }

  function day(iso) {
    return iso ? K.fmt(iso, 'date') : '—';
  }

  function count(n) {
    return K.fmt(n || 0, 'int');
  }

  /** Age in days, read out rather than left as a bare signed number. */
  function age(days) {
    return days < 0 ? t('ETDEMO_CashNotDue') : count(days) + ' ' + t('ETDEMO_CashDaysOverdue');
  }

  function bucketOf(id) {
    for (var i = 0; i < BUCKETS.length; i++) {
      if (BUCKETS[i].id === id) {
        return BUCKETS[i];
      }
    }
    return BUCKETS[BUCKETS.length - 1];
  }

  function sideOf(d, id) {
    var list = d.sides || [];
    for (var i = 0; i < list.length; i++) {
      if (list[i].id === id) {
        return list[i];
      }
    }
    return { id: id, docs: 0, partners: 0, currencies: 0, oldest: null, newest: null };
  }

  function note(text) {
    return html`<p class="cash-note">${text}</p>`;
  }

  /* --------------------------------------------------------------------------- regions */

  /**
   * The side switch, the reference-date chip and the currency switch.
   *
   * The chip is not decoration. This dataset ends in 2021, so a portfolio aged against the real
   * today would read as five years overdue everywhere; the datasource takes the reference date
   * from the data instead and says so, and the chip is where it says it.
   */
  function filtersRegion(s, d) {
    var cur = d.currency;
    var sides = SIDES.map(function (side) {
      var st = sideOf(d, side.id);
      var on = d.side === side.id;
      return html`<button type="button" class="cash-seg-item" data-side="${side.id}"
          aria-pressed="${on ? 'true' : 'false'}"><span>${t(side.label)}</span>
          <em>${count(st.docs)} ${t('ETDEMO_CashDocsWord')}</em></button>`;
    });
    var currencies = (d.currencies || []).map(function (c) {
      var on = cur && cur.id === c.id;
      return html`<button type="button" class="uik-chip" data-cur="${c.id}"
          aria-pressed="${on ? 'true' : 'false'}">${c.iso} <em>${count(c.docs)}</em></button>`;
    });
    return html`
      <div class="cash-bar">
        <div class="cash-seg" role="group" aria-label="${t('ETDEMO_CashSideGroup')}">${sides}</div>
        <span class="uik-chip cash-asof">${t('ETDEMO_CashAsOf')}
          <strong>${day(d.asOf)}</strong>
          <em>${t(SOURCE_LABEL[d.asOfSource] || d.asOfSource)}</em></span>
        <div class="cash-chips" role="group" aria-label="${t('ETDEMO_CashCurrency')}">
          ${currencies}</div>
      </div>
      ${imbalance(d)}
      ${exclusion(d)}`;
  }

  /** The imbalance, in visible text. The screen states what the dataset is, it does not hide it. */
  function imbalance(d) {
    var lines = SIDES.map(function (side) {
      var st = sideOf(d, side.id);
      return html`<li${raw(d.side === side.id ? ' class="is-on"' : '')}>
          <b>${t(side.label)}</b> ${count(st.docs)} ${t('ETDEMO_CashDocsWord')} ·
          ${count(st.partners)} ${t('ETDEMO_CashPartnersWord')} ·
          ${count(st.currencies)} ${t('ETDEMO_CashCurrenciesWord')} ·
          ${t('ETDEMO_CashDueRange')} ${day(st.oldest)} – ${day(st.newest)}</li>`;
    });
    return html`
      <div class="cash-why">
        <p>${t('ETDEMO_CashWhySide')}</p>
        <ul class="cash-why-list">${lines}</ul>
      </div>`;
  }

  function exclusion(d) {
    var out = d.excluded || { docs: 0, currencies: [] };
    if (!out.docs) {
      return note(t('ETDEMO_CashOneCurrency'));
    }
    var isos = (out.currencies || []).map(function (c) {
      return c.iso + ' (' + count(c.docs) + ')';
    });
    return note(
      count(out.docs) + ' ' + t('ETDEMO_CashExcludedNote') + ': ' + isos.join(', ')
    );
  }

  /**
   * The aging rail: five bars over the whole side, and the chips that narrow the table below.
   *
   * The bars are drawn from d.buckets, which the datasource computes over the entire side and
   * currency, ignoring the selected bucket. That asymmetry is the point of the region: the reader
   * has to keep seeing the tramos they are not looking at, or narrowing the table would quietly
   * redefine what "the portfolio" means.
   */
  function railRegion(s, d) {
    var cur = d.currency;
    var items = (d.buckets || []).map(function (b) {
      var meta = bucketOf(b.id);
      return {
        label: t(meta.label),
        value: b.amount,
        state: meta.state,
        sub: count(b.docs) + ' ' + t('ETDEMO_CashDocsWord')
      };
    });
    var picks = [{ id: 'all', label: 'ETDEMO_CashBucketAll' }].concat(BUCKETS).map(function (b) {
      var on = b.id === 'all' ? !s.bucket : s.bucket === b.id;
      return html`<button type="button" class="uik-chip" data-bucket="${b.id}"
          aria-pressed="${on ? 'true' : 'false'}">${t(b.label)}</button>`;
    });
    var total = d.total || { docs: 0, amount: 0 };
    return html`
      <section class="cash-panel">
        <h2 class="cash-h2">${t('ETDEMO_CashAging')}<span>${t('ETDEMO_CashAgingNote')}</span></h2>
        ${K.bars({
          items: items,
          label: t('ETDEMO_CashAgingAria'),
          format: function (v) {
            return money(v, cur);
          }
        })}
        <p class="cash-total"><span>${t('ETDEMO_CashTotalLabel')}</span>
          <strong>${money(total.amount, cur)}</strong>
          <em>${count(total.docs)} ${t('ETDEMO_CashDocsWord')}</em></p>
        <div class="cash-chips" role="group" aria-label="${t('ETDEMO_CashAging')}">${picks}</div>
      </section>`;
  }

  /**
   * Twelve months of settled cash. The series arrives with every month present, including the
   * empty ones: a sparkline over a gapped series draws the last step months early, so the gaps are
   * filled server-side and counted here.
   */
  function seriesRegion(s, d) {
    var months = d.series || [];
    if (months.length === 0) {
      return '';
    }
    var values = months.map(function (m) {
      return m.amount;
    });
    var empty = months.filter(function (m) {
      return !m.docs;
    }).length;
    var heading = d.side === 'AR' ? 'ETDEMO_CashSeriesAR' : 'ETDEMO_CashSeriesAP';
    return html`
      <section class="cash-panel cash-serieswrap">
        <h2 class="cash-h2">${t(heading)}<span>${t('ETDEMO_CashSeriesNote')}</span></h2>
        <div class="cash-spark">
          ${K.spark({
            values: values,
            width: 420,
            height: 56,
            area: true,
            state: 'flat',
            label: t('ETDEMO_CashSeriesAria')
          })}
        </div>
        <p class="cash-axis"><span>${months[0].month}</span>
          <em>${count(empty)} / ${count(months.length)}</em>
          <span>${months[months.length - 1].month}</span></p>
      </section>`;
  }

  /** Partner totals, each expandable into the documents behind it. */
  function detailRegion(s, d) {
    var cur = d.currency;
    var partners = d.partners || [];
    if (partners.length === 0) {
      return html`
        <section class="cash-panel">
          <h2 class="cash-h2">${t('ETDEMO_CashDetail')}</h2>
          ${note(sideOf(d, d.side).docs ? t('ETDEMO_CashEmpty') : t('ETDEMO_CashEmptySide'))}
        </section>`;
    }
    var byPartner = {};
    (d.rows || []).forEach(function (row) {
      (byPartner[row.partner] = byPartner[row.partner] || []).push(row);
    });
    var body = partners.map(function (p) {
      var open = !!s.open[p.id];
      var head = html`
        <tr class="cash-prow${raw(open ? ' is-open' : '')}">
          <td><button type="button" class="cash-pbtn" data-partner="${p.id}"
              aria-expanded="${open ? 'true' : 'false'}">
            <span class="cash-caret" aria-hidden="true"></span>${p.name}</button></td>
          <td data-num>${count(p.docs)}</td>
          <td data-num>${money(p.amount, cur)}</td>
          <td>${day(p.oldest)} <em>${age(p.maxDays)}</em></td>
        </tr>`;
      if (!open) {
        return head;
      }
      return html`${head}
        <tr class="cash-drow"><td colspan="4">${docTable(byPartner[p.id] || [], d, cur)}</td></tr>`;
    });
    return html`
      <section class="cash-panel">
        <h2 class="cash-h2">${t('ETDEMO_CashDetail')}</h2>
        <div class="cash-tablewrap">
          <table class="uik-table">
            <thead>
              <tr>
                <th scope="col">${t('ETDEMO_CashColPartner')}</th>
                <th scope="col" data-num>${t('ETDEMO_CashColDocs')}</th>
                <th scope="col" data-num>${t('ETDEMO_CashColOutstanding')}</th>
                <th scope="col">${t('ETDEMO_CashColOldest')}</th>
              </tr>
            </thead>
            <tbody>${body}</tbody>
          </table>
        </div>
      </section>`;
  }

  /**
   * The documents of one partner. The drill-down target is d.meta.invoiceTab, resolved in SQL by
   * UikQuery.tabFor: c_invoice is shown by several tabs in this instance, so a tab id in a JS
   * constant would open the wrong document type on the right record. When it did not resolve, the
   * reference renders as plain text -- an unavailable link is a smaller failure than a wrong one.
   */
  function docTable(rows, d, cur) {
    var tab = d.meta ? d.meta.invoiceTab : null;
    var body = rows.map(function (r) {
      var ref = tab
        ? html`<a href="javascript:void(0)" data-invoice="${r.invoice}">${r.doc}</a>`
        : html`<span title="${t('ETDEMO_CashNoTab')}">${r.doc}</span>`;
      return html`
        <tr>
          <td>${ref} <em>${t(bucketOf(r.bucket).label)}</em></td>
          <td>${day(r.invoiced)}</td>
          <td>${day(r.due)} <em>${age(r.days)}</em></td>
          <td data-num>${money(r.amount, cur)}</td>
        </tr>`;
    });
    return html`
      <table class="uik-table cash-docs">
        <thead>
          <tr>
            <th scope="col">${t('ETDEMO_CashColDoc')}</th>
            <th scope="col">${t('ETDEMO_CashColInvoiced')}</th>
            <th scope="col">${t('ETDEMO_CashColDue')}</th>
            <th scope="col" data-num>${t('ETDEMO_CashColOutstanding')}</th>
          </tr>
        </thead>
        <tbody>${body}</tbody>
      </table>`;
  }

  /* ------------------------------------------------------------------------- the view */

  K.defineView({
    name: 'ETDEMO_Cash',
    title: 'ETDEMO_CashTitle',
    regions: ['filters', 'rail', 'series', 'detail'],
    // The first-load block goes in the rail: the filter bar is the one piece of chrome worth
    // painting before the numbers arrive, and the rail is where the numbers land.
    loading: 'rail',
    keepScroll: ['detail'],
    state: { side: 'AP', asOf: null, cur: null, bucket: null, open: {} },
    data: { pf: 'ETDEMO_CashPortfolio' },

    // All four reach the server, because all four change what has to be recomputed in SQL --
    // including bucket, which narrows the table while the rail above it must not move.
    params: function (s) {
      return { side: s.side, asOf: s.asOf, cur: s.cur, bucket: s.bucket };
    },

    render: function (s, d) {
      if (!d.pf || !d.pf.asOf) {
        return { filters: note(t('ETDEMO_CashEmptySide')) };
      }
      return {
        filters: filtersRegion(s, d.pf),
        rail: railRegion(s, d.pf),
        series: seriesRegion(s, d.pf),
        detail: detailRegion(s, d.pf)
      };
    },

    on: {
      // Registered before [data-partner]: the first matching rule wins, and a document link lives
      // inside the same table as the partner rows.
      'click [data-invoice]': function (ctx, e, el) {
        var meta = ctx.data.pf ? ctx.data.pf.meta : null;
        K.nav(meta ? meta.invoiceTab : null, el.getAttribute('data-invoice'));
      },
      'click [data-side]': function (ctx, e, el) {
        // Currency and bucket belong to the side that was showing, so both are dropped: the
        // datasource picks the new side's dominant currency and every bucket comes back.
        ctx.set({ side: el.getAttribute('data-side'), cur: null, bucket: null, open: {} });
      },
      'click [data-cur]': function (ctx, e, el) {
        ctx.set({ cur: el.getAttribute('data-cur'), open: {} });
      },
      'click [data-bucket]': function (ctx, e, el) {
        var id = el.getAttribute('data-bucket');
        ctx.set({ bucket: id === 'all' ? null : id, open: {} });
      },
      'click [data-partner]': function (ctx, e, el) {
        ctx.toggle('open', el.getAttribute('data-partner'));
      }
    }
  });
})();
