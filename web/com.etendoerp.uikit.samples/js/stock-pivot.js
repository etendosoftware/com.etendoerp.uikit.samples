/*
 * ETDEMO_Stock -- quantity on hand as a product x warehouse pivot, built on com.etendoerp.uikit.
 *
 * The window is a reading surface over m_storage_detail. What it is really here to demonstrate is
 * an asymmetry, and section 3 of modules/com.etendoerp.uikit/docs/samples/stock-pivot.md is its
 * authoritative table: the warehouse axis is computed ignoring the search box and the page, the
 * column totals are computed over the whole filtered set rather than over the visible page, and
 * only the row detail honours every key of the state.
 *
 * Nothing on this screen is filtered, sorted or paged in the browser. The search box debounces and
 * then hands the text to the datasource; the ilike, the order by and the limit/offset are SQL.
 * That is not an optimisation on 255 rows -- it is the only version of the screen that keeps
 * working when the table is not 255 rows, and the gates in verify/etdemo-stock.checks.mjs prove
 * the work really happens on the server.
 */
(function () {
  'use strict';

  var K = OB.UIKit;
  var html = K.html;
  var raw = K.raw;

  K.datasource('ETDEMO_Stock', { action: 'com.etendoerp.uikit.samples.stock.StockPivot' });

  /* Trailing edge, so the request goes out when typing stops rather than once per letter. */
  var SEARCH_MS = 300;
  var SIZES = [10, 25, 50];
  var SORTS = [
    { id: 'code', label: 'ETDEMO_StockSortCode' },
    { id: 'name', label: 'ETDEMO_StockSortName' },
    { id: 'qty', label: 'ETDEMO_StockSortQty' }
  ];

  /**
   * One debounced setter per open view, keyed by the state object -- which the runtime creates
   * once per instance and never replaces. A single module-level debounce would be shared by two
   * tabs of the same window, and the second typist would cancel the first one's pending search.
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

  /* -------------------------------------------------------------- formatting */

  /** A quantity reads exactly as it would in a standard grid, with the row's own unit. */
  function qty(value, unit) {
    if (value === null || value === undefined) {
      return '—';
    }
    var text = K.fmt(value, 'qty');
    return unit ? text + ' ' + unit : text;
  }

  function count(value) {
    return K.fmt(value, 'int');
  }

  function chip(attr, value, pressed, label) {
    return html`<button type="button" class="uik-chip" ${raw(attr)}="${value}"
        aria-pressed="${pressed ? 'true' : 'false'}">${label}</button>`;
  }

  /* ----------------------------------------------------------------- regions */

  function filtersRegion(s) {
    var sorts = SORTS.map(function (sort) {
      return chip('data-sort', sort.id, s.sort === sort.id, K.t(sort.label));
    });
    var sizes = SIZES.map(function (size) {
      return chip('data-limit', String(size), s.limit === size, count(size));
    });
    return html`
      <div class="stk-bar">
        <input type="search" class="stk-input" data-q="1" value="${s.q}"
            placeholder="${K.t('ETDEMO_StockSearch')}" aria-label="${K.t('ETDEMO_StockSearch')}">
        <div class="stk-group" role="group" aria-label="${K.t('ETDEMO_StockSort')}">
          <span class="stk-group-label">${K.t('ETDEMO_StockSort')}</span>${sorts}
        </div>
        <div class="stk-group">
          ${chip('data-zeros', s.zeros === 'Y' ? 'N' : 'Y', s.zeros === 'Y',
            K.t('ETDEMO_StockZeros'))}
        </div>
        <div class="stk-group" role="group" aria-label="${K.t('ETDEMO_StockPageSize')}">
          <span class="stk-group-label">${K.t('ETDEMO_StockPageSize')}</span>${sizes}
        </div>
      </div>`;
  }

  function summaryRegion(s, d) {
    var stock = d.stock;
    return html`
      <div class="stk-sum">
        <span class="stk-stat"><b>${count(stock.page.total)}</b>
          <em>${K.t('ETDEMO_StockProducts')}</em></span>
        <span class="stk-stat"><b>${count(stock.warehouses.length)}</b>
          <em>${K.t('ETDEMO_StockWarehouses')}</em></span>
        <span class="stk-stat"><b>${qty(stock.summary.grand, '')}</b>
          <em>${K.t('ETDEMO_StockGrand')}</em></span>
        <p class="stk-note">${K.t('ETDEMO_StockAxisNote')} ${K.t('ETDEMO_StockScopeNote')}</p>
      </div>`;
  }

  /** The product cell: a link only when the datasource resolved a tab for it. */
  function productCell(row, tab) {
    var name = tab
      ? html`<a href="javascript:void(0)" data-product="${row.id}"
            title="${K.t('ETDEMO_StockOpenProduct')}">${row.name}</a>`
      : html`<span>${row.name}</span>`;
    return html`<td class="stk-prod">${name}<em>${row.code}</em></td>`;
  }

  function pivotRegion(s, d) {
    var stock = d.stock;
    var axis = stock.warehouses;
    var tab = stock.meta.productTab;
    if (stock.rows.length === 0) {
      return html`<p class="stk-empty">${K.t('ETDEMO_StockEmpty')}</p>`;
    }
    var head = axis.map(function (wh) {
      return html`<th scope="col" data-num="1" title="${wh.code}">${wh.name}</th>`;
    });
    var body = stock.rows.map(function (row) {
      var cells = axis.map(function (wh) {
        var value = row.cells[wh.id];
        return html`<td data-num="1">${value === undefined ? '—' : qty(value, '')}</td>`;
      });
      return html`
        <tr>
          ${productCell(row, tab)}
          <td class="stk-uom">${row.uom}</td>
          ${cells}
          <td data-num="1" class="stk-rowtotal">${qty(row.total, row.uom)}</td>
        </tr>`;
    });
    var totals = index(stock.colTotals);
    var foot = axis.map(function (wh) {
      var value = totals[wh.id];
      return html`<td data-num="1">${value === undefined ? '—' : qty(value, '')}</td>`;
    });
    return html`
      <div class="stk-wrap">
        <table class="uik-table stk-pivot">
          <thead>
            <tr>
              <th scope="col">${K.t('ETDEMO_StockProduct')}</th>
              <th scope="col">${K.t('ETDEMO_StockUom')}</th>
              ${head}
              <th scope="col" data-num="1">${K.t('ETDEMO_StockTotal')}</th>
            </tr>
          </thead>
          <tbody>${body}</tbody>
          <tfoot>
            <tr>
              <th scope="row" colspan="2">${K.t('ETDEMO_StockColTotals')}</th>
              ${foot}
              <td data-num="1" class="stk-rowtotal">${qty(stock.summary.grand, '')}</td>
            </tr>
          </tfoot>
        </table>
      </div>`;
  }

  function pagerRegion(s, d) {
    var p = d.stock.page;
    var first = p.total === 0 ? 0 : p.offset + 1;
    var last = Math.min(p.total, p.offset + d.stock.rows.length);
    return html`
      <div class="uik-pager">
        <button type="button" data-page="${p.page - 1}" ${raw(p.page <= 1 ? 'disabled' : '')}
            >${K.t('ETDEMO_StockPrev')}</button>
        <span>${K.t('ETDEMO_StockPage')} ${count(p.page)} ${K.t('ETDEMO_StockOf')}
          ${count(p.pages)}</span>
        <button type="button" data-page="${p.page + 1}"
            ${raw(p.page >= p.pages ? 'disabled' : '')}>${K.t('ETDEMO_StockNext')}</button>
        <span class="stk-range">${count(first)}–${count(last)} ${K.t('ETDEMO_StockOf')}
          ${count(p.total)} ${K.t('ETDEMO_StockProducts')}</span>
      </div>`;
  }

  /* ----------------------------------------------------------------- helpers */

  function index(list) {
    var out = {};
    (list || []).forEach(function (item) {
      out[item.id] = item.total;
    });
    return out;
  }

  /* --------------------------------------------------------------- the view */

  K.defineView({
    name: 'ETDEMO_Stock',
    title: 'ETDEMO_StockTitle',
    regions: ['filters', 'summary', 'pivot', 'pager'],
    // The filter bar is the one piece of chrome worth painting before the data lands, so the
    // first-load block goes into the pivot instead of into the first region.
    loading: 'pivot',
    keepScroll: ['pivot'],
    state: { q: '', page: 1, limit: 25, zeros: 'N', sort: 'code' },
    data: { stock: 'ETDEMO_Stock' },

    // All five keys reach the server, which is also what getBookMarkParams publishes: a bookmark
    // of page 3 of "cola" sorted by quantity comes back as page 3 of "cola" sorted by quantity.
    params: function (s) {
      return { q: s.q, page: s.page, limit: s.limit, zeros: s.zeros, sort: s.sort };
    },

    render: function (s, d) {
      if (!d.stock || !d.stock.warehouses) {
        return { pivot: html`<p class="stk-empty">${K.t('ETDEMO_StockEmpty')}</p>` };
      }
      return {
        filters: filtersRegion(s),
        summary: summaryRegion(s, d),
        pivot: pivotRegion(s, d),
        pager: pagerRegion(s, d)
      };
    },

    on: {
      'input [data-q]': function (ctx, e, el) {
        searcher(ctx)(el.value);
      },
      'click [data-sort]': function (ctx, e, el) {
        ctx.set({ sort: el.dataset.sort, page: 1 });
      },
      'click [data-zeros]': function (ctx, e, el) {
        ctx.set({ zeros: el.dataset.zeros, page: 1 });
      },
      'click [data-limit]': function (ctx, e, el) {
        ctx.set({ limit: parseInt(el.dataset.limit, 10), page: 1 });
      },
      'click [data-page]': function (ctx, e, el) {
        var page = parseInt(el.dataset.page, 10);
        if (page >= 1) {
          ctx.set({ page: page });
        }
      },
      'click [data-product]': function (ctx, e, el) {
        // The tab id was resolved in SQL by the datasource. A null one never gets a link, so the
        // only way into here is with a tab the dictionary actually returned.
        K.nav(ctx.data.stock.meta.productTab, el.dataset.product);
      }
    },

    // The pending search must not fire into a DOM that is already gone.
    destroy: function (s) {
      var fn = searchers.get(s);
      if (fn) {
        fn.cancel();
        searchers.delete(s);
      }
    }
  });
})();
