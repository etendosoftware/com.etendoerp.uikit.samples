/*
 * ETDEMO_Partner360 -- a business partner file: a directory, a header of per-tab totals and a
 * document list, built on com.etendoerp.uikit.
 *
 * This is the window the runtime's lazy aliases were added for. Its three datasources are fetched
 * under three different conditions -- the directory always, the header only while a partner is
 * selected, the document list only while a partner is selected and the active tab is not the
 * summary -- so opening the payments tab costs exactly one request instead of reloading the
 * directory and the header with it. Section 3 of
 * modules/com.etendoerp.uikit/docs/samples/partner-360.md is the authoritative table of what
 * ignores what, and section 5 explains the keep semantics that make a revisited tab free.
 *
 * Nothing on this screen is filtered, counted or paged in the browser. The search box debounces
 * and hands the text to the datasource; the ilike, the limit/offset, the per-tab counts and the
 * per-document-type tab ids are all SQL.
 */
(function () {
  'use strict';

  var K = OB.UIKit;
  var html = K.html;
  var raw = K.raw;

  K.datasource('ETDEMO_P360List', {
    action: 'com.etendoerp.uikit.samples.partner360.Directory'
  });
  K.datasource('ETDEMO_P360Head', {
    action: 'com.etendoerp.uikit.samples.partner360.PartnerHead'
  });
  K.datasource('ETDEMO_P360Docs', {
    action: 'com.etendoerp.uikit.samples.partner360.PartnerDocs'
  });

  /* Trailing edge, so the request goes out when typing stops rather than once per letter. */
  var SEARCH_MS = 300;
  var DIR_LIMIT = 12;
  var DOC_LIMIT = 20;
  var SUMMARY = 'sum';

  /* The tab strip. The six keys after the summary are the six keys of Partner360.KINDS. */
  var TABS = [
    { id: SUMMARY, label: 'ETDEMO_P360Summary' },
    { id: 'so', label: 'ETDEMO_P360TabSO' },
    { id: 'po', label: 'ETDEMO_P360TabPO' },
    { id: 'si', label: 'ETDEMO_P360TabSI' },
    { id: 'pi', label: 'ETDEMO_P360TabPI' },
    { id: 'rc', label: 'ETDEMO_P360TabRC' },
    { id: 'pm', label: 'ETDEMO_P360TabPM' }
  ];

  /* Document status codes to the four badge states. An unlisted code degrades to neutral. */
  var STATES = {
    CO: 'ok', CL: 'flat', DR: 'risk', VO: 'bad',
    RPPC: 'ok', RPVOID: 'bad', RDNC: 'risk', RPAP: 'risk', RPR: 'risk',
    PPM: 'risk', PWNC: 'risk'
  };

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

  function count(value) {
    return K.fmt(value, 'int');
  }

  /** Money reads as money only next to the currency the datasource sent with it. */
  function money(value, currency) {
    if (value === null || value === undefined) {
      return '—';
    }
    return K.fmt(value, 'amount', { currency: currency });
  }

  function when(value) {
    return value ? K.fmt(value, 'date') : '—';
  }

  function chip(attr, value, pressed, label) {
    return html`<button type="button" class="uik-chip" ${raw(attr)}="${value}"
        aria-pressed="${pressed ? 'true' : 'false'}">${label}</button>`;
  }

  function tabLabel(id) {
    for (var i = 0; i < TABS.length; i++) {
      if (TABS[i].id === id) {
        return K.t(TABS[i].label);
      }
    }
    return id;
  }

  function byTab(totals) {
    var out = {};
    (totals || []).forEach(function (row) {
      out[row.tab] = row;
    });
    return out;
  }

  function documents(totals) {
    return (totals || []).reduce(function (sum, row) {
      return sum + row.count;
    }, 0);
  }

  function failed(ui, alias) {
    return ui.errors && ui.errors[alias]
      ? html`<p class="uik-error">${K.t('ETUIK_LoadFailed')}</p>`
      : null;
  }

  /* ----------------------------------------------------------------- regions */

  function dirRegion(s, d, ui) {
    var broken = failed(ui, 'list');
    if (broken) {
      return broken;
    }
    var list = d.list;
    var rows = list.rows.map(function (row) {
      var marks = [];
      if (row.customer) {
        marks.push(html`<em class="p360-mark">${K.t('ETDEMO_P360Customer')}</em>`);
      }
      if (row.vendor) {
        marks.push(html`<em class="p360-mark">${K.t('ETDEMO_P360Vendor')}</em>`);
      }
      return html`
        <tr data-bp="${row.id}" ${raw(row.id === s.bp ? 'class="p360-on"' : '')}
            aria-selected="${row.id === s.bp ? 'true' : 'false'}">
          <td class="p360-name">${row.name}<span>${row.code} ${marks}</span></td>
          <td data-num="1">${count(row.docs)}</td>
        </tr>`;
    });
    var body = list.rows.length === 0
      ? html`<p class="p360-empty">${K.t('ETDEMO_P360DirEmpty')}</p>`
      : html`
        <table class="uik-table p360-dir">
          <thead>
            <tr>
              <th scope="col">${K.t('ETDEMO_P360Partner')}</th>
              <th scope="col" data-num="1">${K.t('ETDEMO_P360Documents')}</th>
            </tr>
          </thead>
          <tbody>${rows}</tbody>
        </table>`;
    return html`
      <div class="p360-panel">
        <h2 class="p360-h2">${K.t('ETDEMO_P360Directory')}
          <span>${count(list.page.total)} ${K.t('ETDEMO_P360Partners')}</span></h2>
        <input type="search" class="p360-input" data-q="1" value="${s.q}"
            placeholder="${K.t('ETDEMO_P360Search')}" aria-label="${K.t('ETDEMO_P360Search')}">
        ${body}
        ${pager('data-page', list.page, K.t('ETDEMO_P360Partners'))}
      </div>`;
  }

  function headRegion(s, d, ui) {
    if (!s.bp) {
      return html`<p class="p360-pick">${K.t('ETDEMO_P360Pick')}
        <span>${K.t('ETDEMO_P360LazyNote')}</span></p>`;
    }
    var broken = failed(ui, 'head');
    if (broken) {
      return broken;
    }
    var head = d.head;
    if (!head || !head.partner) {
      return html`<p class="p360-pick">${K.t('ETDEMO_P360Pick')}</p>`;
    }
    var p = head.partner;
    var tab = head.meta.partnerTab;
    var name = tab
      ? html`<a href="javascript:void(0)" data-partner="${p.id}"
            title="${K.t('ETDEMO_P360OpenPartner')}">${p.name}</a>`
      : html`<span>${p.name}</span>`;
    var marks = [];
    if (p.customer) {
      marks.push(html`<span class="uik-chip p360-static">${K.t('ETDEMO_P360Customer')}</span>`);
    }
    if (p.vendor) {
      marks.push(html`<span class="uik-chip p360-static">${K.t('ETDEMO_P360Vendor')}</span>`);
    }
    return html`
      <div class="p360-panel p360-head">
        <h1 class="p360-title">${name}</h1>
        <p class="p360-meta">${p.code}
          ${p.taxId ? html`· ${K.t('ETDEMO_P360TaxId')} ${p.taxId}` : ''}
          ${p.group ? html`· ${p.group}` : ''}</p>
        <p class="p360-marks">${marks}</p>
        <p class="p360-note">${count(documents(head.totals))} ${K.t('ETDEMO_P360Docs')} ·
          ${K.t('ETDEMO_P360TotalsNote')} ${K.t('ETDEMO_P360ScopeNote')}</p>
      </div>`;
  }

  /**
   * The tab strip, with the count of every kind on it.
   *
   * The counts come from `head`, which was computed over all of the partner's documents ignoring
   * the active tab -- so the strip is complete the moment a partner is picked, before any document
   * list has been fetched. That is the whole point of splitting `head` from `docs`.
   */
  function tabsRegion(s, d, ui) {
    if (!s.bp || !d.head || !d.head.partner || (ui.errors && ui.errors.head)) {
      return '';
    }
    var totals = byTab(d.head.totals);
    var chips = TABS.map(function (entry) {
      var n = entry.id === SUMMARY
        ? documents(d.head.totals)
        : (totals[entry.id] ? totals[entry.id].count : 0);
      return chip('data-tab', entry.id, s.tab === entry.id,
        raw(K.esc(K.t(entry.label)) + ' <b>' + K.esc(count(n)) + '</b>'));
    });
    return html`<div class="p360-tabs" role="group"
        aria-label="${K.t('ETDEMO_P360Tabs')}">${chips}</div>`;
  }

  /** The summary panel: the same six totals as bars, so the file reads without opening a tab. */
  function summaryPanel(head) {
    var items = head.totals.map(function (row) {
      return {
        label: tabLabel(row.tab),
        value: row.count,
        state: row.count === 0 ? 'flat' : 'ok',
        sub: (row.amount === null || row.amount === undefined
          ? K.t('ETDEMO_P360Mixed')
          : money(row.amount, row.currency))
          + (row.last ? ' · ' + K.t('ETDEMO_P360Last') + ' ' + when(row.last) : '')
      };
    });
    return html`
      <div class="p360-panel">
        <h2 class="p360-h2">${K.t('ETDEMO_P360Summary')}</h2>
        ${K.bars({ items: items, format: count, label: K.t('ETDEMO_P360Documents') })}
      </div>`;
  }

  function docsRegion(s, d, ui) {
    if (!s.bp || !d.head || !d.head.partner) {
      return '';
    }
    if (s.tab === SUMMARY) {
      return summaryPanel(d.head);
    }
    var broken = failed(ui, 'docs');
    if (broken) {
      return broken;
    }
    var docs = d.docs;
    if (!docs) {
      return '';
    }
    if (docs.rows.length === 0) {
      return html`<div class="p360-panel"><p class="p360-empty"
        >${K.t('ETDEMO_P360DocsEmpty')}</p></div>`;
    }
    var tab = docs.meta.tabId;
    var rows = docs.rows.map(function (row) {
      // The tab id was resolved in SQL for this document type. A null one never gets a link, so
      // the only way into the click handler is with a tab the dictionary actually returned.
      var no = tab
        ? html`<a href="javascript:void(0)" data-doc="${row.id}"
              title="${K.t('ETDEMO_P360OpenDoc')}">${row.docNo}</a>`
        : html`<span>${row.docNo}</span>`;
      return html`
        <tr>
          <td>${no}</td>
          <td>${when(row.date)}</td>
          <td data-num="1">${money(row.amount, row.currency)}</td>
          <td>${K.badge(row.status, STATES[row.status] || 'flat')}
            <em class="p360-st">${row.statusName}</em></td>
        </tr>`;
    });
    return html`
      <div class="p360-panel">
        <h2 class="p360-h2">${tabLabel(s.tab)}
          <span>${count(docs.page.total)} ${K.t('ETDEMO_P360Docs')}</span></h2>
        <table class="uik-table p360-docs">
          <thead>
            <tr>
              <th scope="col">${K.t('ETDEMO_P360DocNo')}</th>
              <th scope="col">${K.t('ETDEMO_P360Date')}</th>
              <th scope="col" data-num="1">${K.t('ETDEMO_P360Amount')}</th>
              <th scope="col">${K.t('ETDEMO_P360Status')}</th>
            </tr>
          </thead>
          <tbody>${rows}</tbody>
        </table>
        ${pager('data-dpage', docs.page, K.t('ETDEMO_P360Docs'))}
      </div>`;
  }

  /** One pager markup for both lists; the attribute name is what tells them apart. */
  function pager(attr, page, noun) {
    var first = page.total === 0 ? 0 : page.offset + 1;
    var last = Math.min(page.total, page.offset + page.limit);
    return html`
      <div class="uik-pager">
        <button type="button" ${raw(attr)}="${page.page - 1}"
            ${raw(page.page <= 1 ? 'disabled' : '')}>${K.t('ETDEMO_P360Prev')}</button>
        <span>${K.t('ETDEMO_P360Page')} ${count(page.page)} ${K.t('ETDEMO_P360Of')}
          ${count(page.pages)}</span>
        <button type="button" ${raw(attr)}="${page.page + 1}"
            ${raw(page.page >= page.pages ? 'disabled' : '')}>${K.t('ETDEMO_P360Next')}</button>
        <span class="p360-range">${count(first)}–${count(last)} ${K.t('ETDEMO_P360Of')}
          ${count(page.total)} ${noun}</span>
      </div>`;
  }

  /* --------------------------------------------------------------- the view */

  K.defineView({
    name: 'ETDEMO_Partner360',
    title: 'ETDEMO_P360Title',
    regions: ['dir', 'head', 'tabs', 'docs'],
    loading: 'dir',
    keepScroll: ['dir', 'docs'],
    state: { q: '', page: 1, bp: '', tab: SUMMARY, dpage: 1 },

    /*
     * Three aliases, three conditions. `keep` is left at its default -- true -- so when a when()
     * turns false the alias holds its last value: going back to a tab, or reselecting the partner
     * that is already loaded, costs no round trip. The directory's params never mention bp or tab,
     * which is why picking a partner does not refetch it.
     */
    data: {
      list: {
        source: 'ETDEMO_P360List',
        params: function (s) {
          return { q: s.q, page: s.page, limit: DIR_LIMIT };
        }
      },
      head: {
        source: 'ETDEMO_P360Head',
        params: function (s) {
          return { bp: s.bp };
        },
        when: function (s) {
          return !!s.bp;
        }
      },
      docs: {
        source: 'ETDEMO_P360Docs',
        params: function (s) {
          return { bp: s.bp, tab: s.tab, page: s.dpage, limit: DOC_LIMIT };
        },
        when: function (s) {
          return !!s.bp && s.tab !== SUMMARY;
        }
      }
    },

    // What getBookMarkParams publishes: a bookmark of the payments tab of one partner, on page 2
    // of a filtered directory, reopens as exactly that.
    params: function (s) {
      return { q: s.q, page: s.page, bp: s.bp, tab: s.tab, dpage: s.dpage };
    },

    render: function (s, d, ui) {
      if (!d.list || !d.list.rows) {
        return { dir: html`<p class="p360-empty">${K.t('ETDEMO_P360DirEmpty')}</p>` };
      }
      return {
        dir: dirRegion(s, d, ui),
        head: headRegion(s, d, ui),
        tabs: tabsRegion(s, d, ui),
        docs: docsRegion(s, d, ui)
      };
    },

    on: {
      'input [data-q]': function (ctx, e, el) {
        searcher(ctx)(el.value);
      },
      'click [data-bp]': function (ctx, e, el) {
        // A different partner resets the tab and the document page; the directory is untouched,
        // so its own page and search survive the selection.
        ctx.set({ bp: el.getAttribute('data-bp'), tab: SUMMARY, dpage: 1 });
      },
      'click [data-tab]': function (ctx, e, el) {
        ctx.set({ tab: el.getAttribute('data-tab'), dpage: 1 });
      },
      'click [data-page]': function (ctx, e, el) {
        var page = parseInt(el.getAttribute('data-page'), 10);
        if (page >= 1) {
          ctx.set({ page: page });
        }
      },
      'click [data-dpage]': function (ctx, e, el) {
        var page = parseInt(el.getAttribute('data-dpage'), 10);
        if (page >= 1) {
          ctx.set({ dpage: page });
        }
      },
      'click [data-partner]': function (ctx, e, el) {
        K.nav(ctx.data.head.meta.partnerTab, el.getAttribute('data-partner'));
      },
      'click [data-doc]': function (ctx, e, el) {
        K.nav(ctx.data.docs.meta.tabId, el.getAttribute('data-doc'));
      }
    },

    // The pending search must not fire into a DOM that is already gone.
    //
    // The hook receives the ctx, not the state, and uikCtx() builds a fresh object on every
    // call -- so the WeakMap has to be keyed on ctx.state, the one identity that survives. Read
    // with the ctx as the key this returned undefined and the debounce was never cancelled.
    destroy: function (ctx) {
      var fn = searchers.get(ctx.state);
      if (fn) {
        fn.cancel();
        searchers.delete(ctx.state);
      }
    }
  });
})();
