<#noparse>
/* ETDEMO_Partner360 -- generado por verify/deploy-view.mjs. No editar en base de datos:
   la fuente son los archivos web/ de los modulos, y este bundle se regenera desde ahi. */
/* com.etendoerp.uikit/web/com.etendoerp.uikit/js/uikit.js */
/*
 * com.etendoerp.uikit runtime.
 *
 * One job: let a module own a rectangle of the DOM inside an Etendo Classic tab, and render it
 * from state with plain strings, without learning SmartClient. Everything here is in service of
 * OB.UIKit.defineView; the rest of the surface exists because defineView needs it.
 *
 * There are two doors into the server and no third one. Reads go through datasource() + fetch(),
 * which GET an action handler. Writes go through defineAction() and are reached only from
 * ctx.run(), which is where the CSRF token is attached and where the double click is stopped.
 *
 * The contract this file implements is documented in docs/ -- L0 for the shape, L2 for the API,
 * L3 for the guides. If they disagree, gate G8 fails the build, so change both or neither.
 */
(function () {
  'use strict';

  if (typeof OB === 'undefined') {
    window.OB = {};
  }
  if (OB.UIKit) {
    return;
  }

  var VERSION = '0.2.0';
  var DATASOURCES = {};
  var ACTIONS = {};
  var LABELS = {};
  var STYLES = {};

  /* ------------------------------------------------------------------ text */

  var ENTITIES = {
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;'
  };

  /**
   * Escapes a value for HTML text or a quoted attribute. Null and undefined become the empty
   * string, so a missing field renders as nothing instead of the word "undefined".
   *
   * @param {*} value
   * @returns {string}
   */
  function esc(value) {
    if (value === null || value === undefined) {
      return '';
    }
    return String(value).replace(/[&<>"']/g, function (c) {
      return ENTITIES[c];
    });
  }

  /**
   * Marks a string as already-safe HTML, so html`` will not escape it again.
   *
   * @param {string} html
   */
  function Raw(html) {
    this.html = html;
  }

  // So a Raw can be concatenated or assigned to innerHTML without unwrapping it by hand.
  Raw.prototype.toString = function () {
    return this.html;
  };

  /**
   * Wraps already-safe HTML. Idempotent, so passing a Raw through it is free and safe.
   *
   * @param {string|Raw} html
   * @returns {Raw}
   */
  function raw(html) {
    return html instanceof Raw ? html : new Raw(html);
  }

  /**
   * Tagged template that escapes every interpolation. Arrays are joined with no separator, so
   * `html`<ul>${items.map(li)}</ul>`` works, and a raw() value passes through untouched.
   *
   * Returns a Raw, which is what makes composition work: the result of one html`` interpolated
   * into another is already-safe HTML and must not be escaped a second time. Do not `.join('')`
   * a list of results -- that flattens them back to a plain string, which the next html`` will
   * escape; interpolate the array itself instead.
   *
   * @param {string[]} strings
   * @param {...*} values
   * @returns {Raw}
   */
  function html(strings) {
    var out = strings[0];
    for (var i = 1; i < arguments.length; i++) {
      out += interpolate(arguments[i]) + strings[i];
    }
    return new Raw(out);
  }

  function interpolate(value) {
    if (value instanceof Raw) {
      return value.html;
    }
    if (Array.isArray(value)) {
      return value.map(interpolate).join('');
    }
    return esc(value);
  }

  /* ---------------------------------------------------------------- labels */

  /**
   * Registers translated strings. Values come from AD_MESSAGE, never from source.
   *
   * @param {Object<string, string>} map
   * @returns {void}
   */
  function labels(map) {
    Object.keys(map).forEach(function (k) {
      LABELS[k] = map[k];
    });
  }

  /**
   * The label for a key, or the key itself, which makes a missing AD_MESSAGE visible on screen.
   *
   * @param {string} key
   * @returns {string}
   */
  function t(key) {
    return LABELS[key] === undefined ? key : LABELS[key];
  }

  /*
   * Interpolates one AD_MESSAGE label: every %{name} in the msgtext is replaced by vars.name.
   *
   * Private on purpose. It returns null -- not the key -- when the row is missing, because the
   * only strings the runtime itself labels are aria-labels, and an aria-label reading
   * "ETUIK_RailAria" is worse for a screen-reader user than the bare numbers. Every caller
   * therefore carries a numeric fallback, and the window keeps working in an instance where the
   * two ETUIK_ rows have not been inserted yet.
   */
  function fill(key, vars) {
    if (LABELS[key] === undefined) {
      return null;
    }
    var text = String(LABELS[key]);
    if (!vars) {
      return text;
    }
    return text.replace(/%\{([A-Za-z_]\w*)\}/g, function (whole, name) {
      return vars[name] === undefined ? whole : String(vars[name]);
    });
  }

  /* ----------------------------------------------------------- datasources */

  /**
   * Maps a logical datasource name to the action handler that answers it. Handlers are reached by
   * fully qualified class name; KernelServlet needs no AD row to publish one.
   *
   * @param {string} name
   * @param {{ action: string }} spec  action is the handler's fully qualified class name
   * @returns {void}
   */
  function datasource(name, spec) {
    DATASOURCES[name] = spec;
  }

  /**
   * GETs one datasource. The callback receives (error, data): exactly one of the two is set, and
   * a server-side error arrives as an Error rather than as data the caller might render.
   *
   * @param {string} name
   * @param {Object<string, *>} params
   * @param {function(Error|null, Object=): void} callback
   * @returns {void}
   */
  function fetch(name, params, callback) {
    var spec = DATASOURCES[name];
    if (!spec) {
      callback(new Error('unknown datasource ' + name));
      return;
    }
    OB.RemoteCallManager.call(
      spec.action,
      null,
      params || {},
      function (response, data) {
        if (!data) {
          callback(new Error('empty response from ' + name));
        } else if (data.error) {
          callback(new Error(data.error.message || String(data.error)));
        } else {
          callback(null, data);
        }
      },
      null,
      function () {
        callback(new Error('request to ' + name + ' failed'));
      }
    );
  }

  /* ---------------------------------------------------------------- styles */

  /**
   * Injects a stylesheet once per key, so a redraw or a second tab cannot duplicate it.
   *
   * @param {string} key
   * @param {string} css
   * @returns {void}
   */
  function style(key, css) {
    if (STYLES[key]) {
      return;
    }
    var el = document.createElement('style');
    el.setAttribute('data-uikit-style', key);
    el.textContent = css;
    document.head.appendChild(el);
    STYLES[key] = true;
  }

  /* ------------------------------------------------------------ formatting */

  /*
   * The default masks, copied from the *Inform / *Relation entries of config/Format.xml, which is
   * where this instance's real masks live. They are defaults, not a guess at the user's locale:
   * OB.Format is generated at runtime by an AD template and is not in the source tree, so the only
   * keys of it read here are the three core itself reads by name -- date, dateTime and
   * defaultGroupingSize. Anything else a caller needs is passed through opts.
   */
  var FMT_MASKS = {
    number: '#,##0.00',
    int: '#,##0',
    qty: '#,##0.###',
    price: '#,##0.00',
    amount: '#,##0.00',
    pct: '#,##0.0'
  };

  /**
   * Formats one value the way the rest of Etendo formats it, and never throws.
   *
   * Delegates to OB.Utilities.Number.JSToOBMasked and OB.Utilities.Date.JSToOB, so a number here
   * reads exactly like the same number in a standard grid. `pct` expects percentage points, not a
   * fraction: 62.5 renders as "62.5%", which is what rail() and every pace calculation produce.
   *
   * There is no session currency in the client, so this function never invents one: pass
   * opts.currency with the symbol or ISO code the datasource returned, next to the amount it
   * belongs to. An amount without its currency is a number, not money.
   *
   * Returns a plain string, not a Raw: the caller decides whether to escape it. When OB.Format is
   * absent -- an early page, a test harness, a stripped instance -- it degrades to String(value)
   * rather than failing, because a screen showing raw numbers is still a working screen.
   *
   * @param {*} value  a number, or an ISO date string, or a Date
   * @param {'number'|'int'|'qty'|'price'|'amount'|'pct'|'date'|'dateTime'} kind
   * @param {Object} [opts]  currency, and mask / dec / group to override the defaults
   * @returns {string}
   */
  function fmt(value, kind, opts) {
    var o = opts || {};
    if (value === null || value === undefined || value === '') {
      return '';
    }
    try {
      if (kind === 'date' || kind === 'dateTime') {
        return fmtDate(value, kind, o);
      }
      return fmtNumber(value, kind, o);
    } catch (e) {
      return String(value);
    }
  }

  function fmtNumber(value, kind, o) {
    var n = typeof value === 'number' ? value : Number(value);
    if (!isFinite(n)) {
      return String(value);
    }
    var mask = o.mask || FMT_MASKS[kind];
    var lib = OB.Utilities && OB.Utilities.Number;
    var out;
    if (!mask || !OB.Format || !lib || typeof lib.JSToOBMasked !== 'function') {
      out = String(n);
    } else {
      // application-js.ftl publishes the session's own separators next to the masks; reading them
      // is what makes a uikit number identical to the same number in a standard grid.
      var dec = o.dec === undefined ? OB.Format.defaultDecimalSymbol : o.dec;
      var group = o.group === undefined ? OB.Format.defaultGroupingSymbol : o.group;
      out = String(
        lib.JSToOBMasked(
          n,
          mask,
          dec === undefined || dec === null ? '.' : dec,
          group === undefined || group === null ? ',' : group,
          OB.Format.defaultGroupingSize || 3
        )
      );
    }
    if (kind === 'pct') {
      return out + '%';
    }
    return o.currency ? out + ' ' + o.currency : out;
  }

  function fmtDate(value, kind, o) {
    var d = toDate(value);
    var lib = OB.Utilities && OB.Utilities.Date;
    var pattern = o.mask;
    if (!pattern && OB.Format) {
      pattern = kind === 'dateTime' ? OB.Format.dateTime : OB.Format.date;
    }
    if (!d || !pattern || !lib || typeof lib.JSToOB !== 'function') {
      return String(value);
    }
    var out = lib.JSToOB(d, pattern);
    return out === null || out === undefined ? String(value) : String(out);
  }

  /*
   * Builds a Date from what UikQuery.date actually emits: yyyy-MM-dd, optionally with a time.
   * The parts are fed to the local-time constructor rather than to Date.parse, which reads a bare
   * yyyy-MM-dd as UTC and so moves a business date by a day for anyone west of Greenwich.
   */
  function toDate(value) {
    if (Object.prototype.toString.call(value) === '[object Date]') {
      return isFinite(value.getTime()) ? value : null;
    }
    var m = /^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2}))?)?/.exec(String(value));
    if (!m) {
      return null;
    }
    return new Date(
      Number(m[1]),
      Number(m[2]) - 1,
      Number(m[3]),
      Number(m[4] || 0),
      Number(m[5] || 0),
      Number(m[6] || 0)
    );
  }

  /* ------------------------------------------------------------ navigation */

  /**
   * Opens the standard window that owns a record, on the tab that shows it.
   *
   * A wrapper over OB.Utilities.openDirectTab, which resolves the window from the tab server-side,
   * so a caller passes a tab id and a record id and nothing else. The tab id must come from SQL --
   * UikQuery.tabFor -- never from a constant in JavaScript: c_order in this instance has six
   * header tabs, and the wrong one opens "Return to vendor" for a sales order.
   *
   * Warns and returns when there is nothing to navigate with, instead of throwing: this is called
   * from a click handler, and an exception there kills the handler for every later click too. A
   * drill-down that does nothing is a smaller failure than a dead window.
   *
   * @param {string} tabId  an AD_TAB id, resolved server-side
   * @param {string} [recordId]  the record to open; without it the tab opens in grid mode
   * @returns {void}
   */
  function nav(tabId, recordId) {
    if (!tabId) {
      console.warn('OB.UIKit.nav: no tab id; nothing to open');
      return;
    }
    if (!OB.Utilities || typeof OB.Utilities.openDirectTab !== 'function') {
      console.warn('OB.UIKit.nav: OB.Utilities.openDirectTab is unavailable; not opening ' + tabId);
      return;
    }
    try {
      OB.Utilities.openDirectTab(tabId, recordId);
    } catch (e) {
      console.warn('OB.UIKit.nav: openDirectTab failed for ' + tabId + ': ' + e.message);
    }
  }

  /* ---------------------------------------------------------------- timing */

  /**
   * Trailing-edge debounce: the wrapped function runs `ms` after the last call, never on the
   * first. The returned function carries a .cancel() that drops a pending run, which is what a
   * view's destroy hook needs so a timer cannot fire into a DOM that is already gone.
   *
   * Trailing rather than leading because the caller is a search box: the useful moment is when
   * typing stops, and a leading edge would fire a request for the first letter every time.
   *
   * @param {Function} fn  the function to defer
   * @param {number} [ms]  the quiet period; 200 by default
   * @returns {Function}
   */
  function debounce(fn, ms) {
    var wait = ms === undefined ? 200 : ms;
    var timer = null;
    var wrapped = function () {
      var args = arguments;
      var self = this;
      if (timer !== null) {
        clearTimeout(timer);
      }
      timer = setTimeout(function () {
        timer = null;
        fn.apply(self, args);
      }, wait);
    };
    wrapped.cancel = function () {
      if (timer !== null) {
        clearTimeout(timer);
        timer = null;
      }
    };
    return wrapped;
  }

  /* ------------------------------------------------------------ components */

  var STATES = { ok: 'ok', risk: 'risk', bad: 'bad', flat: 'flat' };

  /**
   * A small state pill. An unknown state degrades to the neutral one rather than throwing.
   *
   * @param {*} text
   * @param {'ok'|'risk'|'bad'|'flat'} state
   * @returns {Raw}
   */
  function badge(text, state) {
    return raw(
      '<span class="uik-badge uik-' + (STATES[state] || 'flat') + '">' + esc(text) + '</span>'
    );
  }

  /**
   * The pace rail: fill at `progress`, tick at `expected`, colour from the distance between them.
   * Not a progress bar -- a bar at 62% tells the reader nothing until they know what day it is.
   *
   * @param {number} progress  0-100, clamped
   * @param {number} expected  0-100, clamped; where the tick goes
   * @param {'ok'|'risk'|'bad'|'flat'} state
   * @returns {Raw}
   */
  function rail(progress, expected, state) {
    var p = clamp(progress, 0, 100);
    var e = clamp(expected, 0, 100);
    var aria = fill('ETUIK_RailAria', { progress: Math.round(p), expected: Math.round(e) });
    return raw(
      '<span class="uik-rail uik-' +
      (STATES[state] || 'flat') +
      '" style="--uik-p:' +
      p.toFixed(1) +
      '%;--uik-e:' +
      e.toFixed(1) +
      '%" role="img" aria-label="' +
      esc(aria === null ? Math.round(p) + '% / ' + Math.round(e) + '%' : aria) +
      '"></span>'
    );
  }

  /**
   * The score meter: ten cells for a 0.00-1.00 score, filled to `score`, with the cell holding
   * `target` outlined. Answers "will the commitment be met" without comparing two numbers.
   *
   * @param {number} score   0.00-1.00, clamped
   * @param {number} target  0.00-1.00, clamped; the outlined cell
   * @returns {Raw}
   */
  function meter(score, target) {
    var filled = Math.round(clamp(score, 0, 1) * 10);
    var mark = Math.max(1, Math.min(10, Math.ceil(clamp(target, 0, 1) * 10)));
    var shown = Number(score).toFixed(2);
    var goal = Number(target).toFixed(2);
    var aria = fill('ETUIK_MeterAria', { score: shown, target: goal });
    var cells = '';
    for (var i = 1; i <= 10; i++) {
      cells +=
        '<i class="' + (i <= filled ? 'on' : '') + (i === mark ? ' tg' : '') + '"></i>';
    }
    return raw(
      '<span class="uik-meter" role="img" aria-label="' +
      esc(aria === null ? shown + ' / ' + goal : aria) +
      '">' +
      cells +
      '</span>'
    );
  }

  /**
   * A horizontal bar chart, in HTML and CSS rather than SVG.
   *
   * SVG was rejected here deliberately. A cockpit's bar labels are real text -- a bucket name, a
   * count, a document reference -- and text inside an svg element has to be either a foreignObject
   * or hand-measured, so it cannot wrap and cannot be selected or copied. rail() already proves
   * that a bar driven by one custom property is enough, and this is the same trick applied to a
   * list: each bar carries --uik-v and paints its own fill behind ordinary, selectable text.
   *
   * The scale is shared by every bar, so the lengths are comparable: `max` when given, otherwise
   * the largest absolute value in the list. Negative values are drawn at their absolute length and
   * marked data-negative, which is what a month-over-month series needs.
   *
   * @param {Object} spec
   * @param {Object[]} spec.items  one object per bar: label, value, and optionally state and sub
   * @param {number} [spec.max]  the shared scale; the largest absolute value by default
   * @param {Function} [spec.format]  (value) => string for the printed number; String by default
   * @param {string} [spec.label]  an aria-label, which also turns the list into a labelled group
   * @returns {Raw}
   */
  function bars(spec) {
    var items = spec && spec.items ? spec.items : [];
    var show = spec && typeof spec.format === 'function' ? spec.format : String;
    var top = spec && spec.max ? Math.abs(spec.max) : 0;
    items.forEach(function (item) {
      var v = Math.abs(Number(item.value));
      if (isFinite(v) && v > top) {
        top = v;
      }
    });
    var rows = items.map(function (item) {
      var v = Number(item.value);
      var size = !isFinite(v) || top === 0 ? 0 : (Math.abs(v) / top) * 100;
      return (
        '<div class="uik-bar uik-' +
        (STATES[item.state] || 'flat') +
        '"' +
        (v < 0 ? ' data-negative="1"' : '') +
        ' style="--uik-v:' +
        size.toFixed(1) +
        '%"><span class="uik-bar-label">' +
        esc(item.label) +
        (item.sub === undefined || item.sub === null ? '' : '<em>' + esc(item.sub) + '</em>') +
        '</span><span class="uik-bar-value">' +
        esc(show(item.value)) +
        '</span></div>'
      );
    });
    var group = spec && spec.label ? ' role="group" aria-label="' + esc(spec.label) + '"' : '';
    return raw('<div class="uik-bars"' + group + '>' + rows.join('') + '</div>');
  }

  /**
   * A sparkline: one polyline over a series, no axes, no labels, no numbers.
   *
   * SVG here, unlike bars(), because a sparkline is pure geometry -- there is no text in it at
   * all, which is the one case SVG is unambiguously better at than CSS. The shape carries no
   * value a reader can read off it, so it is decorative by default: without `label` it is
   * aria-hidden, and the number it accompanies is what a screen reader announces. Pass `label`
   * only when the trend itself is the information.
   *
   * A single point, or a series where every value is equal, draws a flat line at mid height
   * instead of dividing by a zero range.
   *
   * @param {Object} spec
   * @param {number[]} spec.values  the series, oldest first; non-finite entries are dropped
   * @param {number} [spec.width]  120 by default
   * @param {number} [spec.height]  28 by default
   * @param {'ok'|'risk'|'bad'|'flat'} [spec.state]  the stroke colour
   * @param {boolean} [spec.area]  fill the area under the line
   * @param {string} [spec.label]  an aria-label; without it the graphic is hidden from a reader
   * @returns {Raw}
   */
  function spark(spec) {
    var series = spec && spec.values ? spec.values : [];
    var vals = [];
    series.forEach(function (v) {
      var n = Number(v);
      if (isFinite(n)) {
        vals.push(n);
      }
    });
    var w = spec && spec.width ? spec.width : 120;
    var h = spec && spec.height ? spec.height : 28;
    var pad = 1.5;
    var open =
      '<svg class="uik-spark uik-' +
      (STATES[spec && spec.state] || 'flat') +
      '" viewBox="0 0 ' +
      w +
      ' ' +
      h +
      '" width="' +
      w +
      '" height="' +
      h +
      '" focusable="false" ' +
      (spec && spec.label
        ? 'role="img" aria-label="' + esc(spec.label) + '"'
        : 'role="presentation" aria-hidden="true"') +
      '>';
    if (vals.length === 0) {
      return raw(open + '</svg>');
    }
    var lo = Math.min.apply(null, vals);
    var hi = Math.max.apply(null, vals);
    var span = hi - lo;
    var usable = h - pad * 2;
    var points = vals.map(function (v, i) {
      var x = vals.length === 1 ? 0 : (i / (vals.length - 1)) * w;
      var y = span === 0 ? h / 2 : h - pad - ((v - lo) / span) * usable;
      return x.toFixed(2) + ',' + y.toFixed(2);
    });
    if (vals.length === 1) {
      points.push(w.toFixed(2) + ',' + (h / 2).toFixed(2));
    }
    var line = points.join(' ');
    var body = '';
    if (spec && spec.area) {
      body +=
        '<polygon class="uik-spark-area" points="0,' +
        h.toFixed(2) +
        ' ' +
        line +
        ' ' +
        w.toFixed(2) +
        ',' +
        h.toFixed(2) +
        '"></polygon>';
    }
    body += '<polyline class="uik-spark-line" points="' + line + '"></polyline>';
    return raw(open + body + '</svg>');
  }

  /**
   * Confines n to [lo, hi].
   *
   * @param {number} n
   * @param {number} lo
   * @param {number} hi
   * @returns {number}
   */
  function clamp(n, lo, hi) {
    return Math.min(hi, Math.max(lo, n));
  }

  /* --------------------------------------------------------------- actions */

  /**
   * Registers a write. It is reached only from ctx.run(name, arg, callback) inside a view, which
   * is the whole point: the token, the in-flight guard, the optimistic snapshot and the refetch
   * all live on that path, so an app cannot POST without them by accident.
   *
   * The payload always carries csrfToken from OB.User. When the page has no token the request is
   * not sent at all and the callback receives an Error with code ETUIK_NoCsrf -- the same code
   * UikAction returns when the server rejects a token -- because KernelServlet does not check
   * CSRF itself, so a write that forgets the token is simply rejected by the handler.
   *
   * optimistic(state, arg) mutates state before the request and is repainted immediately, without
   * going through ctx.set, so it never triggers a refetch: a refetch racing an unfinished write
   * would repaint the server's old answer over the user's action. If the request fails, state is
   * restored from a JSON snapshot taken before the mutation. Two consequences, and they constrain
   * every window that writes:
   *
   *   1. state must be JSON-serializable. A Date, a function, a DOM node or a cycle does not
   *      survive the snapshot, so it cannot live in state.
   *   2. optimistic must not touch any key that params(state) reads, or the mutation -- and the
   *      rollback after it -- would change a datasource signature and provoke exactly the refetch
   *      this design exists to avoid.
   *
   * refetch names what to reload after a success: true for everything, or an alias, or a list of
   * aliases. confirm is a question shown before anything happens, as a string or as
   * (state, arg) => string.
   *
   * @param {Object} spec
   * @param {string} spec.name  the name ctx.run uses
   * @param {string} spec.action  the handler's fully qualified class name; it must extend UikAction
   * @param {Function} [spec.payload]  (state, arg) => the request body, before csrfToken
   * @param {Function} [spec.optimistic]  (state, arg) => void, applied before the request
   * @param {boolean|string|string[]} [spec.refetch]  what to reload on success
   * @param {string|Function} [spec.confirm]  a question to ask first
   * @returns {void}
   */
  function defineAction(spec) {
    ACTIONS[spec.name] = spec;
  }

  function actionError(code, message) {
    var err = new Error(message);
    err.code = code;
    return err;
  }

  /*
   * The shape UikAction.execute returns, and nothing else. Success is the handler's own keys plus
   * success:true; a rejection is success:false with error.code and error.message, where the code
   * is ETUIK_NoCsrf for a bad token and ETUIK_Failed for anything the handler threw. The message
   * is written for a user, so it is safe to render; the stack trace stayed in the server log.
   */
  function envelopeError(data, action) {
    if (!data) {
      return actionError('ETUIK_Failed', 'empty response from ' + action);
    }
    if (data.error) {
      return actionError(
        data.error.code || 'ETUIK_Failed',
        data.error.message || String(data.error)
      );
    }
    if (data.success === false) {
      return actionError('ETUIK_Failed', action + ' reported no success');
    }
    return null;
  }

  /*
   * Puts a JSON snapshot back, in place. The state object itself is never replaced, because
   * ctx.state and every handler closure already hold a reference to it; replacing it would leave
   * the app mutating an orphan.
   */
  function restoreState(view, snapshot) {
    var was = JSON.parse(snapshot);
    Object.keys(view.uikState).forEach(function (k) {
      delete view.uikState[k];
    });
    Object.keys(was).forEach(function (k) {
      view.uikState[k] = was[k];
    });
  }

  /*
   * Runs one registered action for one view. Private: ctx.run is the only door, and it returns
   * true only when a request actually left the browser -- false covers an unknown action, a
   * refused confirmation, a missing token, and the duplicate that a double click produces.
   */
  function runAction(view, name, arg, callback) {
    var done = typeof callback === 'function' ? callback : function () {};
    var action = ACTIONS[name];
    if (!action) {
      done(actionError('ETUIK_NoAction', 'unknown action ' + name));
      return false;
    }
    var key = name + ' ' + JSON.stringify(arg === undefined ? null : arg);
    if (view.uikFlight[key]) {
      return false;
    }
    if (action.confirm) {
      var ask =
        typeof action.confirm === 'function' ? action.confirm(view.uikState, arg) : action.confirm;
      if (ask && !window.confirm(String(ask))) {
        return false;
      }
    }
    var user = OB.User;
    var token = user ? user.csrfToken : null;
    if (!token) {
      done(
        actionError(
          'ETUIK_NoCsrf',
          'no CSRF token on OB.User; ' + name + ' was not sent. Reload the window.'
        )
      );
      return false;
    }
    var body = (action.payload ? action.payload(view.uikState, arg) : {}) || {};
    var wire = {};
    Object.keys(body).forEach(function (k) {
      wire[k] = body[k];
    });
    // Last, so a payload cannot overwrite the token with a field of its own.
    wire.csrfToken = token;
    var snapshot = null;
    if (action.optimistic) {
      snapshot = JSON.stringify(view.uikState);
      action.optimistic(view.uikState, arg);
      // Deliberately uikPaint and not uikSync: see the note above about the racing refetch.
      view.uikPaint();
    }
    view.uikFlight[key] = true;
    view.uikBusyDelta(1);
    var settle = function () {
      delete view.uikFlight[key];
      view.uikBusyDelta(-1);
    };
    var rollback = function (err) {
      if (snapshot !== null) {
        restoreState(view, snapshot);
      }
      view.uikPaint();
      done(err);
    };
    OB.RemoteCallManager.call(
      action.action,
      wire,
      {},
      function (response, data) {
        settle();
        var err = envelopeError(data, action.action);
        if (err) {
          rollback(err);
          return;
        }
        if (action.refetch) {
          view.uikInvalidate(action.refetch);
          view.uikLoad();
        } else {
          view.uikPaint();
        }
        done(null, data);
      },
      null,
      function () {
        settle();
        rollback(actionError('ETUIK_Failed', 'request to ' + action.action + ' failed'));
      }
    );
    return true;
  }

  /* -------------------------------------------------------------- the view */

  // focus and blur do not bubble, so a delegated listener on the root never sees them unless it
  // is registered in the capture phase. focusin and focusout do bubble and need nothing special.
  var CAPTURE = { focus: true, blur: true };

  /*
   * Normalises one entry of spec.data. A bare string is the whole-view shape it has always been;
   * the object shape is decision D6 and its four keys are frozen.
   *
   * keep is the odd one out because its default is the safe direction: when when(state) turns
   * false the alias's last value is kept, so flipping a panel closed and open again costs no
   * request. keep:false is the opt-out for a source whose stale answer would mislead.
   */
  function dataEntry(value) {
    if (typeof value === 'string') {
      return { source: value, params: null, when: null, keep: true };
    }
    return {
      source: value.source,
      params: typeof value.params === 'function' ? value.params : null,
      when: typeof value.when === 'function' ? value.when : null,
      keep: value.keep !== false
    };
  }

  /*
   * A selector that finds the focused element again after its region's innerHTML is replaced,
   * built from the element's own data-* attributes. Returns null for an element that carries none,
   * which is why every focusable control in a uikit window has a data-* identifier: without one
   * there is nothing stable to match on across a rewrite.
   */
  function focusKey(el) {
    var attrs = el.attributes;
    var parts = [];
    for (var i = 0; i < attrs.length; i++) {
      if (attrs[i].name.indexOf('data-') === 0) {
        parts.push('[' + attrs[i].name + '="' + String(attrs[i].value).replace(/"/g, '\\"') + '"]');
      }
    }
    return parts.length ? el.tagName.toLowerCase() + parts.join('') : null;
  }

  /**
   * Defines a Classic view that owns its own DOM subtree.
   *
   * Rendering is whole-region strings, and a region is written only when its string changed. That
   * is what keeps the filter bar from flickering when the user clicks a chip inside it. Caret and
   * selection survive a region rewrite, so a search box does not lose a keystroke mid-word.
   *
   * render is called as (state, data, ui). ui carries what the runtime knows and the app does not:
   * ui.first while the first load has not finished, ui.busy while any request is in flight, and
   * ui.errors keyed by data alias -- so a source that failed on a refetch is reported next to the
   * rest of a screen that is still perfectly good, instead of blanking it.
   *
   * Event handlers receive one ctx and nothing else:
   *
   *   ctx.state, ctx.data, ctx.ui        the same three objects render sees
   *   ctx.set(partial)                   merge into state, then reconcile
   *   ctx.toggle(key, id)                flip one id in a set-shaped state key
   *   ctx.run(name, arg, callback)       run a defineAction; false when it did not go out
   *   ctx.later(fn, ms)                  a timer this view owns; returns its cancel function
   *   ctx.refetch(alias)                 drop a cached alias and reload it; no alias means all
   *
   * In the on: map the first matching rule wins and the rest are skipped. That is deliberate and
   * relied upon: a specific 'click [data-row] button' registered before a general
   * 'click [data-row]' shadows it, which is how a row with its own action button works at all.
   * Changing it to run every match would silently break any app already written against it.
   *
   * @param {Object} spec
   * @param {string} spec.name  the view id, matching OBUIAPP_View_Impl.name and isc.<name>
   * @param {string} [spec.title]  label key for the tab title; falls back to the view id
   * @param {Object} spec.state  the initial state object; every key is yours, and JSON-only
   * @param {Object<string, string|Object>} [spec.data]  alias to datasource name, or to a lazy entry
   * @param {function(Object): Object<string, *>} [spec.params]  (state) => request params
   * @param {string[]} spec.regions  region names, in render order; required
   * @param {string} [spec.loading]  region that shows the first-load block; the first region by default
   * @param {string[]} [spec.keepScroll]  region names whose scrollTop survives a redraw
   * @param {function(Object, Object, Object): Object<string, string|Raw>} spec.render  (state, data, ui) => region html
   * @param {Object<string, function(Object, Event, Element): void>} [spec.on]  { 'click [data-x]': handler }
   * @param {function(Object): void} [spec.activate]  the tab became visible
   * @param {function(Object): void} [spec.deactivate]  the tab lost focus to another tab
   * @param {function(Object): void} [spec.destroy]  the tab is closing; drop anything the runtime cannot
   * @returns {Object} the SmartClient class, already registered as isc.<name>
   */
  function defineView(spec) {
    var name = spec.name;
    /*
     * No fallback. This used to default to Object.keys(spec.state.regions || {}), which was never
     * documented and, for every real spec, produced an empty array: the window then drew a root
     * div with no regions in it and rendered nothing at all, with no error in the console and
     * nothing to search for. A loud throw at definition time is the whole fix.
     */
    if (!spec.regions || !spec.regions.length) {
      throw new Error(
        'OB.UIKit.defineView(' + name + '): spec.regions is required and must not be empty'
      );
    }
    var regions = spec.regions;

    isc.ClassFactory.defineClass(name, isc.VLayout);

    isc[name].addProperties({
      // Our subtree is ours. SmartClient must not re-emit the handle contents underneath it.
      redrawOnResize: false,
      overflow: 'auto',
      width: '100%',
      height: '100%',

      isSameTab: function (viewId) {
        return viewId === name;
      },

      /**
       * A lazily fetched view arrives after its tab already exists: ViewManager opens a loading
       * tab titled with the view id, then swaps in the pane without relabelling it. This is the
       * hook core calls once the tab is ours, so it is where the title gets fixed.
       */
      setViewTabId: function (viewTabId) {
        this.viewTabId = viewTabId;
        if (this.tabTitle && OB.MainView && OB.MainView.TabSet) {
          OB.MainView.TabSet.setTabTitle(viewTabId, this.tabTitle);
        }
      },

      // Core spells it getBookMarkParams -- capital M and P. Misname it and the URL silently
      // stops carrying any state, with no error anywhere.
      getBookMarkParams: function () {
        var params = { viewId: name };
        if (spec.params) {
          isc.addProperties(params, spec.params(this.uikState));
        }
        return params;
      },

      initWidget: function () {
        // ViewManager reads tabTitle off the instance right after create(), so it has to be set
        // here -- otherwise the tab is labelled with the raw view id.
        if (!this.tabTitle) {
          this.tabTitle = spec.title ? t(spec.title) : name;
        }
        this.uikState = isc.shallowClone(spec.state);
        this.uikData = {};
        this.uikPainted = {};
        this.uikParams = null;
        this.uikUi = { first: true, busy: false, errors: {} };
        this.uikFlight = {};
        this.uikTimers = [];
        this.uikBusyCount = 0;
        this.uikDead = false;
        // openView passes bookmark params straight into create(), so a restored tab starts where
        // the user left it rather than on the default quarter.
        var self = this;
        Object.keys(spec.state).forEach(function (k) {
          if (self[k] !== undefined && typeof self[k] !== 'function') {
            self.uikState[k] = self[k];
          }
        });
        return this.Super('initWidget', arguments);
      },

      draw: function () {
        var result = this.Super('draw', arguments);
        this.uikMount();
        return result;
      },

      redraw: function () {
        var result = this.Super('redraw', arguments);
        // SmartClient may have replaced the handle contents; rebuild from state, which is cheap
        // because render is pure.
        this.uikRoot = null;
        this.uikPainted = {};
        this.uikMount();
        return result;
      },

      /**
       * Core calls this for us: OBTabSetMain sets destroyPanes:true, so closing the tab destroys
       * the pane. Timers have to die here or they fire into a DOM that no longer exists, and
       * uikDead makes every later paint a no-op, including one an in-flight request will try.
       */
      destroy: function () {
        this.uikDead = true;
        this.uikTimers.forEach(function (id) {
          clearTimeout(id);
        });
        this.uikTimers = [];
        if (spec.destroy) {
          try {
            spec.destroy(this.uikCtx());
          } catch (e) {
            console.warn('OB.UIKit: ' + name + ' destroy hook failed: ' + e.message);
          }
        }
        return this.Super('destroy', arguments);
      },

      // OBTabSetMain redirects its own tabSelected/tabDeselected to the pane when the pane has
      // them, so these are already the lifecycle hooks; core's own panes do not call Super here
      // and neither do we. They arrive with no arguments from the navbar widgets.
      tabSelected: function () {
        if (spec.activate && !this.uikDead) {
          spec.activate(this.uikCtx());
        }
      },

      tabDeselected: function () {
        if (spec.deactivate && !this.uikDead) {
          spec.deactivate(this.uikCtx());
        }
      },

      /** Creates our root element inside the SmartClient handle and paints once. */
      uikMount: function () {
        var handle = this.getHandle();
        if (!handle || this.uikDead) {
          return;
        }
        if (!this.uikRoot || !handle.contains(this.uikRoot)) {
          var root = document.createElement('div');
          root.className = 'uik uik-' + name.toLowerCase();
          handle.appendChild(root);
          root.innerHTML = regions
            .map(function (r) {
              return '<div class="uik-region uik-region-' + r + '" data-region="' + r + '"></div>';
            })
            .join('');
          this.uikRoot = root;
          this.uikBind();
        }
        if (this.uikBusyCount > 0) {
          this.uikRoot.classList.add('uik-busy');
        }
        if (this.uikParams === null) {
          this.uikLoad();
        } else {
          this.uikPaint();
        }
      },

      /** One delegated listener per event type, on our root only, so SmartClient sees nothing. */
      uikBind: function () {
        var self = this;
        var handlers = spec.on || {};
        var byType = {};
        Object.keys(handlers).forEach(function (key) {
          var space = key.indexOf(' ');
          var type = space === -1 ? key : key.slice(0, space);
          var selector = space === -1 ? null : key.slice(space + 1);
          (byType[type] = byType[type] || []).push({ selector: selector, fn: handlers[key] });
        });
        Object.keys(byType).forEach(function (type) {
          self.uikRoot.addEventListener(
            type,
            function (event) {
              var rules = byType[type];
              for (var i = 0; i < rules.length; i++) {
                var el = rules[i].selector ? event.target.closest(rules[i].selector) : event.target;
                if (el && self.uikRoot.contains(el)) {
                  // First match wins. Registration order is the priority order, so a specific
                  // rule placed before a general one shadows it. Documented in defineView.
                  rules[i].fn(self.uikCtx(), event, el);
                  return;
                }
              }
            },
            CAPTURE[type] === true
          );
        });
      },

      /** The context handed to event handlers: the only sanctioned way to change anything. */
      uikCtx: function () {
        var self = this;
        return {
          state: self.uikState,
          data: self.uikData,
          ui: self.uikUi,
          set: function (partial) {
            isc.addProperties(self.uikState, partial);
            self.uikSync();
          },
          toggle: function (key, id) {
            var bag = self.uikState[key] || {};
            if (bag[id]) {
              delete bag[id];
            } else {
              bag[id] = true;
            }
            self.uikState[key] = bag;
            self.uikSync();
          },
          run: function (action, arg, callback) {
            return self.uikDead ? false : runAction(self, action, arg, callback);
          },
          later: function (fn, ms) {
            if (self.uikDead) {
              return function () {};
            }
            var id = setTimeout(function () {
              self.uikForget(id);
              if (!self.uikDead) {
                fn();
              }
            }, ms);
            self.uikTimers.push(id);
            return function () {
              clearTimeout(id);
              self.uikForget(id);
            };
          },
          refetch: function (alias) {
            self.uikInvalidate(alias === undefined ? true : alias);
            self.uikLoad();
          }
        };
      },

      uikForget: function (id) {
        var at = this.uikTimers.indexOf(id);
        if (at !== -1) {
          this.uikTimers.splice(at, 1);
        }
      },

      /**
       * Reconciles after a state change. uikLoad decides per alias whether anything has to be
       * refetched, so this is one call and not a branch: a tab switch repaints, a filter change
       * refetches only the sources whose own params moved.
       */
      uikSync: function () {
        this.uikLoad();
      },

      /**
       * Marks the root busy while requests are outstanding. A counter, not a flag, because a
       * lazy view has several sources and an optimistic write can overlap them.
       */
      uikBusyDelta: function (delta) {
        this.uikBusyCount = Math.max(0, this.uikBusyCount + delta);
        this.uikUi.busy = this.uikBusyCount > 0;
        if (this.uikRoot) {
          if (this.uikUi.busy) {
            this.uikRoot.classList.add('uik-busy');
          } else {
            this.uikRoot.classList.remove('uik-busy');
          }
        }
      },

      /** Forgets the cached params signature of one alias, a list of them, or all of them. */
      uikInvalidate: function (which) {
        if (this.uikParams === null) {
          return;
        }
        if (which === true) {
          this.uikParams = {};
          return;
        }
        var self = this;
        var list = Array.isArray(which) ? which : [which];
        list.forEach(function (alias) {
          delete self.uikParams[alias];
        });
      },

      /**
       * Fetches only what changed.
       *
       * uikParams is a signature per alias plus one for the view, so an alias is requested when
       * its own params moved and not because some other filter did. A source whose when(state) is
       * false is not requested at all and keeps its last value, which is what makes a window with
       * six panels and three sources affordable: opening a panel costs one request the first time
       * and nothing afterwards.
       *
       * Only the first load blanks anything. After that a failure lands in ui.errors[alias] and
       * the screen that is already painted stays painted -- the previous version of this function
       * wrote a loading block into a hardcoded region on every single refetch, which erased a
       * working screen every time a filter moved.
       */
      uikLoad: function () {
        if (this.uikDead) {
          return;
        }
        var self = this;
        var state = this.uikState;
        var viewParams = spec.params ? spec.params(state) : {};
        var first = this.uikParams === null;
        var was = first ? {} : this.uikParams;
        var next = { view: JSON.stringify(viewParams) };
        var wanted = [];
        Object.keys(spec.data || {}).forEach(function (alias) {
          var entry = dataEntry(spec.data[alias]);
          if (entry.when && !entry.when(state)) {
            if (entry.keep) {
              next[alias] = was[alias];
            } else {
              delete self.uikData[alias];
              delete self.uikUi.errors[alias];
            }
            return;
          }
          var params = entry.params ? entry.params(state) : viewParams;
          var sig = JSON.stringify(params);
          next[alias] = sig;
          if (sig !== was[alias] || self.uikData[alias] === undefined) {
            wanted.push({ alias: alias, source: entry.source, params: params });
          }
        });
        this.uikParams = next;
        // These params are what getBookMarkParams publishes, so the URL has to follow them --
        // and only them: a tab or a sort that never reaches the server must not touch history.
        if (this.viewTabId && OB.Layout.HistoryManager && next.view !== was.view) {
          OB.Layout.HistoryManager.updateHistory();
        }
        if (wanted.length === 0) {
          this.uikUi.first = false;
          this.uikPaint();
          return;
        }
        if (first) {
          this.uikSetRegion(
            spec.loading || regions[0],
            '<div class="uik-loading">' + esc(t('ETUIK_Loading')) + '</div>'
          );
        }
        var pending = wanted.length;
        this.uikBusyDelta(wanted.length);
        wanted.forEach(function (job) {
          delete self.uikUi.errors[job.alias];
          fetch(job.source, job.params, function (err, data) {
            self.uikBusyDelta(-1);
            if (err) {
              self.uikUi.errors[job.alias] = err.message;
            } else {
              self.uikData[job.alias] = data;
              delete self.uikUi.errors[job.alias];
            }
            pending -= 1;
            if (pending > 0 || self.uikDead) {
              return;
            }
            var broken = Object.keys(self.uikUi.errors);
            self.uikUi.first = false;
            if (first && broken.length) {
              // Nothing is painted yet, so there is no screen to protect: show the error itself.
              self.uikFail(new Error(self.uikUi.errors[broken[0]]));
              return;
            }
            self.uikPaint();
          });
        });
      },

      uikFail: function (err) {
        this.uikSetRegion(
          regions[0],
          '<div class="uik-error"><b>' +
            esc(t('ETUIK_LoadFailed')) +
            '</b><br>' +
            esc(err.message) +
            '</div>'
        );
      },

      /** Renders every region, writes only the ones whose HTML actually changed. */
      uikPaint: function () {
        if (this.uikDead || !this.uikRoot) {
          return;
        }
        var out;
        try {
          out = spec.render(this.uikState, this.uikData, this.uikUi) || {};
        } catch (e) {
          this.uikFail(e);
          throw e;
        }
        var self = this;
        regions.forEach(function (r) {
          self.uikSetRegion(r, out[r] === undefined ? '' : out[r]);
        });
      },

      /**
       * Writes one region, preserving scroll, focus and text selection across the write.
       *
       * Replacing innerHTML destroys the focused node, so without this a window that repaints
       * while someone is typing loses the caret on every keystroke and an optimistic write moves
       * focus off the button that was just pressed. That would make a uikit screen measurably
       * worse to use than a core grid, which is why this is not optional.
       */
      uikSetRegion: function (region, markup) {
        markup = markup === null || markup === undefined ? '' : String(markup);
        if (this.uikPainted[region] === markup) {
          return;
        }
        var node = this.uikRoot.querySelector('[data-region="' + region + '"]');
        if (!node) {
          return;
        }
        var keep = (spec.keepScroll || []).indexOf(region) !== -1 ? node.scrollTop : null;
        var active = document.activeElement;
        var mark = null;
        if (active && active !== document.body && node.contains(active)) {
          mark = { key: focusKey(active), start: null, end: null };
          try {
            mark.start = active.selectionStart;
            mark.end = active.selectionEnd;
          } catch (e) {
            mark.start = null;
          }
        }
        node.innerHTML = markup;
        this.uikPainted[region] = markup;
        if (keep !== null) {
          node.scrollTop = keep;
        }
        if (mark && mark.key) {
          var again = node.querySelector(mark.key);
          if (again) {
            again.focus();
            if (mark.start !== null && typeof again.setSelectionRange === 'function') {
              try {
                again.setSelectionRange(mark.start, mark.end);
              } catch (e2) {
                // A control that reports a selection but refuses to set one; the focus is enough.
              }
            }
          }
        }
      }
    });

    return isc[name];
  }

  OB.UIKit = {
    version: VERSION,
    esc: esc,
    raw: raw,
    html: html,
    labels: labels,
    t: t,
    datasource: datasource,
    fetch: fetch,
    style: style,
    fmt: fmt,
    nav: nav,
    debounce: debounce,
    badge: badge,
    rail: rail,
    meter: meter,
    bars: bars,
    spark: spark,
    clamp: clamp,
    defineAction: defineAction,
    defineView: defineView
  };
})();


/* com.etendoerp.uikit/web/com.etendoerp.uikit/css/uikit.css */
OB.UIKit.style("com.etendoerp.uikit", "/*\n * com.etendoerp.uikit base stylesheet.\n *\n * Scoped under .uik so nothing here can reach Classic's own chrome, and so a window can be\n * dropped into any skin without a specificity fight. Only the primitives the runtime ships live\n * here -- regions, badge, rail, meter, loading and error. Everything else belongs to the app.\n */\n\n.uik {\n  --uik-ink: #16202b;\n  --uik-ink-soft: #5b6b7c;\n  --uik-line: #dde3ea;\n  --uik-surface: #ffffff;\n  --uik-ground: #f4f6f9;\n  --uik-brand: #1b5e8c;\n  --uik-ok: #1c7a54;\n  --uik-risk: #a8700d;\n  --uik-bad: #b23a3a;\n  --uik-flat: #7d8b99;\n\n  box-sizing: border-box;\n  padding: 16px 20px 28px;\n  min-height: 100%;\n  background: var(--uik-ground);\n  color: var(--uik-ink);\n  font: 13px/1.45 \"Helvetica Neue\", Helvetica, Arial, sans-serif;\n  -webkit-font-smoothing: antialiased;\n}\n\n.uik *,\n.uik *::before,\n.uik *::after {\n  box-sizing: inherit;\n}\n\n.uik .uik-region + .uik-region {\n  margin-top: 14px;\n}\n\n.uik .uik-region:empty {\n  display: none;\n}\n\n/* --------------------------------------------------------------- feedback */\n\n.uik .uik-loading,\n.uik .uik-error {\n  padding: 18px 20px;\n  border: 1px solid var(--uik-line);\n  border-radius: 6px;\n  background: var(--uik-surface);\n  color: var(--uik-ink-soft);\n}\n\n.uik .uik-error {\n  border-color: color-mix(in srgb, var(--uik-bad) 40%, var(--uik-line));\n  color: var(--uik-bad);\n}\n\n/* ----------------------------------------------------------------- badge */\n\n.uik .uik-badge {\n  display: inline-block;\n  padding: 2px 8px;\n  border-radius: 10px;\n  border: 1px solid currentColor;\n  font-size: 11px;\n  font-weight: 600;\n  letter-spacing: 0.02em;\n  white-space: nowrap;\n}\n\n.uik .uik-ok { color: var(--uik-ok); }\n.uik .uik-risk { color: var(--uik-risk); }\n.uik .uik-bad { color: var(--uik-bad); }\n.uik .uik-flat { color: var(--uik-flat); }\n\n/* -------------------------------------------------------------- pace rail\n * --uik-p is the progress fill, --uik-e the expected mark for today. The gap between them is the\n * whole point of the instrument, so the mark is drawn on top of the fill, never behind it.\n */\n\n.uik .uik-rail {\n  position: relative;\n  display: block;\n  height: 8px;\n  border-radius: 4px;\n  background: #e6ebf1;\n  overflow: hidden;\n}\n\n.uik .uik-rail::before {\n  content: \"\";\n  position: absolute;\n  inset: 0 auto 0 0;\n  width: var(--uik-p, 0%);\n  border-radius: 4px 0 0 4px;\n  background: currentColor;\n}\n\n.uik .uik-rail::after {\n  content: \"\";\n  position: absolute;\n  top: -2px;\n  bottom: -2px;\n  left: var(--uik-e, 0%);\n  width: 2px;\n  margin-left: -1px;\n  background: var(--uik-ink);\n  opacity: 0.72;\n}\n\n/* ------------------------------------------------------------ score meter */\n\n.uik .uik-meter {\n  display: inline-flex;\n  gap: 2px;\n  vertical-align: middle;\n}\n\n.uik .uik-meter i {\n  width: 7px;\n  height: 12px;\n  border-radius: 1px;\n  background: #e6ebf1;\n  box-shadow: inset 0 0 0 1px transparent;\n}\n\n.uik .uik-meter i.on {\n  background: var(--uik-brand);\n}\n\n.uik .uik-meter i.tg {\n  box-shadow: inset 0 0 0 1px var(--uik-ink);\n}\n\n.uik .uik-meter i.tg:not(.on) {\n  background: transparent;\n}\n\n/* ---------------------------------------------------------------- a11y */\n\n.uik :focus-visible {\n  outline: 2px solid var(--uik-brand);\n  outline-offset: 1px;\n}\n\n@media (prefers-reduced-motion: reduce) {\n  .uik * {\n    transition: none !important;\n    animation: none !important;\n  }\n}\n\n/* ------------------------------------------------------------------ bars\n * bars() is HTML and not SVG so that the labels stay real text: they wrap, they are selectable,\n * and a screen reader reads them without a foreignObject. Each bar carries --uik-v and paints\n * its own fill behind that text with a pseudo-element, exactly as .uik-rail does. The state\n * class sets color, and the fill reads currentColor from it.\n */\n\n.uik .uik-bars {\n  display: flex;\n  flex-direction: column;\n  gap: 3px;\n}\n\n.uik .uik-bar {\n  position: relative;\n  display: flex;\n  align-items: baseline;\n  gap: 10px;\n  padding: 5px 8px;\n  border-radius: 3px;\n  background: var(--uik-surface);\n  box-shadow: inset 0 0 0 1px var(--uik-line);\n}\n\n.uik .uik-bar::before {\n  content: \"\";\n  position: absolute;\n  inset: 0 auto 0 0;\n  width: var(--uik-v, 0%);\n  border-radius: 3px;\n  background: currentColor;\n  opacity: 0.16;\n}\n\n.uik .uik-bar[data-negative]::before {\n  /* A negative value is drawn at its absolute length, so the only thing left to distinguish it\n   * is the direction: it grows from the right edge. */\n  inset: 0 0 0 auto;\n  border-style: dashed;\n}\n\n.uik .uik-bar-label {\n  position: relative;\n  flex: 1 1 auto;\n  min-width: 0;\n  color: var(--uik-ink);\n}\n\n.uik .uik-bar-label em {\n  display: block;\n  color: var(--uik-ink-soft);\n  font-size: 11px;\n  font-style: normal;\n}\n\n.uik .uik-bar-value {\n  position: relative;\n  flex: 0 0 auto;\n  font-variant-numeric: tabular-nums;\n  font-weight: 600;\n}\n\n/* ----------------------------------------------------------------- spark */\n\n.uik .uik-spark {\n  display: inline-block;\n  vertical-align: middle;\n  overflow: visible;\n}\n\n.uik .uik-spark-line {\n  fill: none;\n  stroke: currentColor;\n  stroke-width: 1.5;\n  stroke-linecap: round;\n  stroke-linejoin: round;\n  vector-effect: non-scaling-stroke;\n}\n\n.uik .uik-spark-area {\n  fill: currentColor;\n  stroke: none;\n  opacity: 0.14;\n}\n\n/* ------------------------------------------------------------------ busy\n * The root carries .uik-busy while any request is in flight. It must never hide or move what is\n * already painted -- a refetch is not a reload -- so it desaturates slightly and blocks clicks,\n * and nothing else.\n */\n\n.uik.uik-busy {\n  cursor: progress;\n}\n\n.uik.uik-busy .uik-region {\n  opacity: 0.62;\n  transition: opacity 120ms linear;\n  pointer-events: none;\n}\n\n/* ----------------------------------------------------------------- table */\n\n.uik .uik-table {\n  width: 100%;\n  border-collapse: collapse;\n  background: var(--uik-surface);\n  font-variant-numeric: tabular-nums;\n}\n\n.uik .uik-table th,\n.uik .uik-table td {\n  padding: 6px 10px;\n  border-bottom: 1px solid var(--uik-line);\n  text-align: left;\n  vertical-align: top;\n}\n\n.uik .uik-table th {\n  color: var(--uik-ink-soft);\n  font-size: 11px;\n  font-weight: 600;\n  letter-spacing: 0.04em;\n  text-transform: uppercase;\n  white-space: nowrap;\n}\n\n.uik .uik-table td[data-num],\n.uik .uik-table th[data-num] {\n  text-align: right;\n}\n\n.uik .uik-table tbody tr:hover {\n  background: var(--uik-ground);\n}\n\n/* ----------------------------------------------------------------- pager */\n\n.uik .uik-pager {\n  display: flex;\n  align-items: center;\n  gap: 8px;\n  padding: 6px 0;\n  color: var(--uik-ink-soft);\n  font-size: 12px;\n}\n\n.uik .uik-pager button {\n  padding: 3px 9px;\n  border: 1px solid var(--uik-line);\n  border-radius: 3px;\n  background: var(--uik-surface);\n  color: var(--uik-ink);\n  font: inherit;\n  cursor: pointer;\n}\n\n.uik .uik-pager button:disabled {\n  color: var(--uik-flat);\n  cursor: default;\n}\n\n/* ------------------------------------------------------------------ chip */\n\n.uik .uik-chip {\n  display: inline-block;\n  padding: 3px 10px;\n  border: 1px solid var(--uik-line);\n  border-radius: 12px;\n  background: var(--uik-surface);\n  color: var(--uik-ink-soft);\n  font: inherit;\n  font-size: 12px;\n  cursor: pointer;\n  white-space: nowrap;\n}\n\n.uik .uik-chip[aria-pressed=\"true\"],\n.uik .uik-chip.on {\n  border-color: var(--uik-brand);\n  background: color-mix(in srgb, var(--uik-brand) 10%, var(--uik-surface));\n  color: var(--uik-brand);\n  font-weight: 600;\n}\n");

/* com.etendoerp.uikit.samples/web/com.etendoerp.uikit.samples/css/partner-360.css */
OB.UIKit.style("com.etendoerp.uikit.samples.partner360", "/*\n * ETDEMO_Partner360 stylesheet. Every rule is scoped under .uik-etdemo_partner360, the class the\n * runtime puts on this window's root, so nothing here can reach Classic's chrome or the other\n * sample windows.\n *\n * The primitives -- .uik-table, .uik-pager, .uik-chip, .uik-bars -- are styled by uikit.css and\n * are not restyled here; that file is frozen and shared. What lives here is this window's own\n * layout: a directory rail beside a file, which is the shape that makes the lazy sources legible\n * (the rail never reloads while the file changes). Colours come from the --uik-* tokens only.\n */\n\n.uik-etdemo_partner360 {\n  --p360-radius: 7px;\n  --p360-shadow: 0 1px 2px rgba(22, 32, 43, 0.06);\n}\n\n/* ------------------------------------------------------------------- shell\n * Regions are siblings of the root, so the grid is declared on the root and the framework's\n * vertical stacking margin is neutralised here rather than in uikit.css. Below 900px the regions\n * fall back to that stack, which is the right reading order: directory, partner, tabs, documents.\n */\n\n@media (min-width: 900px) {\n  .uik-etdemo_partner360 {\n    display: grid;\n    grid-template-columns: minmax(0, 320px) minmax(0, 1fr);\n    gap: 14px;\n    align-items: start;\n  }\n\n  .uik-etdemo_partner360 > .uik-region + .uik-region {\n    margin-top: 0;\n  }\n\n  .uik-etdemo_partner360 > .uik-region-dir {\n    grid-column: 1;\n    grid-row: 1 / span 3;\n    position: sticky;\n    top: 0;\n  }\n\n  .uik-etdemo_partner360 > .uik-region-head,\n  .uik-etdemo_partner360 > .uik-region-tabs,\n  .uik-etdemo_partner360 > .uik-region-docs {\n    grid-column: 2;\n  }\n}\n\n/* ------------------------------------------------------------------ panels */\n\n.uik-etdemo_partner360 .p360-panel {\n  padding: 12px 14px;\n  border: 1px solid var(--uik-line);\n  border-radius: var(--p360-radius);\n  background: var(--uik-surface);\n  box-shadow: var(--p360-shadow);\n}\n\n.uik-etdemo_partner360 .p360-h2 {\n  margin: 0 0 10px;\n  display: flex;\n  align-items: baseline;\n  justify-content: space-between;\n  gap: 10px;\n  flex-wrap: wrap;\n  font-size: 12px;\n  font-weight: 700;\n  letter-spacing: 0.06em;\n  text-transform: uppercase;\n  color: var(--uik-ink-soft);\n}\n\n.uik-etdemo_partner360 .p360-h2 span {\n  font-weight: 400;\n  letter-spacing: 0;\n  text-transform: none;\n}\n\n/* --------------------------------------------------------------- directory */\n\n.uik-etdemo_partner360 .p360-input {\n  width: 100%;\n  margin-bottom: 8px;\n  padding: 5px 10px;\n  border: 1px solid var(--uik-line);\n  border-radius: var(--p360-radius);\n  background: var(--uik-surface);\n  color: var(--uik-ink);\n  font: inherit;\n}\n\n.uik-etdemo_partner360 .p360-input:focus {\n  outline: 2px solid var(--uik-brand);\n  outline-offset: -1px;\n}\n\n.uik-etdemo_partner360 .p360-dir tbody tr {\n  cursor: pointer;\n}\n\n/* The selected row has to stay obvious while the reader looks at the file on the right. */\n.uik-etdemo_partner360 .p360-dir tbody tr.p360-on > td {\n  background: color-mix(in srgb, var(--uik-brand) 10%, transparent);\n  box-shadow: inset 3px 0 0 var(--uik-brand);\n}\n\n.uik-etdemo_partner360 .p360-name span {\n  display: block;\n  color: var(--uik-ink-soft);\n  font-size: 11px;\n}\n\n.uik-etdemo_partner360 .p360-mark {\n  margin-left: 6px;\n  font-style: normal;\n  color: var(--uik-brand);\n}\n\n/* -------------------------------------------------------------------- head */\n\n.uik-etdemo_partner360 .p360-title {\n  margin: 0;\n  font-size: 18px;\n  font-weight: 600;\n}\n\n.uik-etdemo_partner360 .p360-title a {\n  color: var(--uik-brand);\n  text-decoration: none;\n}\n\n.uik-etdemo_partner360 .p360-title a:hover {\n  text-decoration: underline;\n}\n\n.uik-etdemo_partner360 .p360-meta {\n  margin: 2px 0 0;\n  color: var(--uik-ink-soft);\n}\n\n.uik-etdemo_partner360 .p360-marks {\n  margin: 8px 0 0;\n  display: flex;\n  gap: 6px;\n  flex-wrap: wrap;\n}\n\n/* A chip that only labels: it is not a control, so it must not look pressable. */\n.uik-etdemo_partner360 .p360-static {\n  cursor: default;\n}\n\n.uik-etdemo_partner360 .p360-note {\n  margin: 8px 0 0;\n  color: var(--uik-ink-soft);\n  font-size: 11px;\n}\n\n.uik-etdemo_partner360 .p360-pick {\n  padding: 18px 20px;\n  border: 1px dashed var(--uik-line);\n  border-radius: var(--p360-radius);\n  background: var(--uik-surface);\n  color: var(--uik-ink-soft);\n}\n\n.uik-etdemo_partner360 .p360-pick span {\n  display: block;\n  margin-top: 4px;\n  font-size: 11px;\n}\n\n/* -------------------------------------------------------------------- tabs */\n\n.uik-etdemo_partner360 .p360-tabs {\n  display: flex;\n  gap: 6px;\n  flex-wrap: wrap;\n}\n\n.uik-etdemo_partner360 .p360-tabs b {\n  margin-left: 6px;\n  font-variant-numeric: tabular-nums;\n}\n\n/* --------------------------------------------------------------- documents */\n\n.uik-etdemo_partner360 .p360-docs {\n  table-layout: auto;\n}\n\n.uik-etdemo_partner360 .p360-docs a {\n  color: var(--uik-brand);\n  text-decoration: none;\n}\n\n.uik-etdemo_partner360 .p360-docs a:hover {\n  text-decoration: underline;\n}\n\n.uik-etdemo_partner360 .p360-st {\n  margin-left: 6px;\n  font-style: normal;\n  color: var(--uik-ink-soft);\n  font-size: 11px;\n}\n\n.uik-etdemo_partner360 .p360-range {\n  color: var(--uik-ink-soft);\n}\n\n.uik-etdemo_partner360 .p360-empty {\n  margin: 0;\n  padding: 14px 2px;\n  color: var(--uik-ink-soft);\n}\n");

/* AD_MESSAGE */
OB.UIKit.labels({"ETDEMO_AlertsAck":"Revisar","ETDEMO_AlertsAcked":"Revisada","ETDEMO_AlertsAckFailed":"No se pudo revisar la alerta; se ha restaurado el estado anterior.","ETDEMO_AlertsACKNOWLEDGED":"Revisadas","ETDEMO_AlertsAll":"Todas","ETDEMO_AlertsBadTransition":"Solo se puede revisar una alerta nueva. Estado actual:","ETDEMO_AlertsColAction":"Accion","ETDEMO_AlertsColAlert":"Alerta","ETDEMO_AlertsColCreated":"Creada","ETDEMO_AlertsColOrg":"Organizacion","ETDEMO_AlertsDetailHead":"Detalle","ETDEMO_AlertsEmpty":"No hay alertas con este filtro.","ETDEMO_AlertsNEW":"Nuevas","ETDEMO_AlertsNoRules":"Este rol no tiene ninguna alerta visible.","ETDEMO_AlertsNoTab":"Sin ventana asociada","ETDEMO_AlertsNotVisible":"La alerta no existe o no es visible para este rol.","ETDEMO_AlertsOpen":"Abrir registro","ETDEMO_AlertsPause":"Pausar refresco","ETDEMO_AlertsRailNote":"Los recuentos por estado y por regla se calculan sobre todas las alertas visibles, sin mirar el filtro activo.","ETDEMO_AlertsRefreshEvery":"Refresco automatico cada","ETDEMO_AlertsReloadNow":"Actualizar ahora","ETDEMO_AlertsResume":"Reanudar refresco","ETDEMO_AlertsRuleHead":"Regla","ETDEMO_AlertsSeconds":"segundos","ETDEMO_AlertsSOLVED":"Resueltas","ETDEMO_AlertsSource":"Alertas generadas por reglas del diccionario, no por la operacion diaria.","ETDEMO_AlertsStatusHead":"Estado","ETDEMO_AlertsSUPPRESSED":"Silenciadas","ETDEMO_AlertsTitle":"Bandeja de alertas del administrador","ETDEMO_AlertsTotal":"Alertas visibles","ETDEMO_AlertsTruncated":"Lista recortada al limite de filas; ajusta el filtro para ver el resto.","ETDEMO_CashAging":"Antiguedad de la cartera","ETDEMO_CashAgingAria":"Antiguedad de la cartera por tramo","ETDEMO_CashAgingNote":"Los totales por tramo se calculan sobre toda la cartera del lado, sin mirar el tramo seleccionado.","ETDEMO_CashAP":"Pagos a proveedores","ETDEMO_CashAR":"Cobros de clientes","ETDEMO_CashAsOf":"Fecha de referencia","ETDEMO_CashBucketAll":"Todos los tramos","ETDEMO_CashBucketCur":"Sin vencer","ETDEMO_CashBucketD30":"1 a 30 dias","ETDEMO_CashBucketD60":"31 a 60 dias","ETDEMO_CashBucketD90":"61 a 90 dias","ETDEMO_CashBucketD90p":"Mas de 90 dias","ETDEMO_CashColDays":"Dias","ETDEMO_CashColDoc":"Documento","ETDEMO_CashColDocs":"Docs.","ETDEMO_CashColDue":"Vencimiento","ETDEMO_CashColInvoiced":"Fecha de factura","ETDEMO_CashColOldest":"Vencimiento mas antiguo","ETDEMO_CashColOutstanding":"Pendiente","ETDEMO_CashColPartner":"Tercero","ETDEMO_CashCurrenciesWord":"monedas","ETDEMO_CashCurrency":"Moneda","ETDEMO_CashDaysOverdue":"dias vencido","ETDEMO_CashDetail":"Detalle por tercero","ETDEMO_CashDocsWord":"documentos","ETDEMO_CashDueRange":"vencimientos","ETDEMO_CashEmpty":"No hay documentos pendientes con este filtro.","ETDEMO_CashEmptySide":"Esta cartera no tiene ningun documento pendiente dentro del ambito del rol.","ETDEMO_CashExcludedNote":"documento(s) en otras monedas no se muestran","ETDEMO_CashFromData":"ultimo vencimiento del dato","ETDEMO_CashFromParam":"indicada en la peticion","ETDEMO_CashFromToday":"hoy del servidor","ETDEMO_CashNoTab":"sin ventana de factura resoluble","ETDEMO_CashNotDue":"sin vencer","ETDEMO_CashOneCurrency":"Una sola moneda a la vez: sumar monedas distintas da un numero sin significado.","ETDEMO_CashPartnersWord":"terceros","ETDEMO_CashSeriesAP":"Pagos liquidados, 12 meses","ETDEMO_CashSeriesAR":"Cobros liquidados, 12 meses","ETDEMO_CashSeriesAria":"Serie mensual de caja de los ultimos doce meses","ETDEMO_CashSeriesNote":"fin_payment es la unica serie densa de esta instancia; los meses sin pagos se rellenan en Java.","ETDEMO_CashSideGroup":"Cartera","ETDEMO_CashTitle":"Cartera de cobros y pagos","ETDEMO_CashTotalLabel":"Total de la cartera","ETDEMO_CashWhySide":"El encargo original pedia un cuadro de cobros. En esta instancia los cobros estan muertos y los pagos vivos, asi que la pantalla abre en pagos y lo dice en vez de esconderlo: el conmutador cambia de lado en un clic.","ETDEMO_P360Amount":"Importe","ETDEMO_P360Count":"Nº","ETDEMO_P360Customer":"Cliente","ETDEMO_P360Date":"Fecha","ETDEMO_P360Directory":"Directorio","ETDEMO_P360DirEmpty":"Ningún tercero coincide con la búsqueda.","ETDEMO_P360DocNo":"Nº documento","ETDEMO_P360Docs":"documentos","ETDEMO_P360DocsEmpty":"Este tercero no tiene documentos de este tipo.","ETDEMO_P360Documents":"Documentos","ETDEMO_P360Last":"Último","ETDEMO_P360LazyNote":"El directorio se carga una vez; la ficha y la lista de documentos solo cuando hacen falta.","ETDEMO_P360Mixed":"varias monedas","ETDEMO_P360Next":"Siguiente","ETDEMO_P360Of":"de","ETDEMO_P360OpenDoc":"Abrir el documento","ETDEMO_P360OpenPartner":"Abrir la ficha del tercero","ETDEMO_P360Page":"Página","ETDEMO_P360Partner":"Tercero","ETDEMO_P360Partners":"terceros","ETDEMO_P360Pick":"Elige un tercero del directorio para ver su ficha.","ETDEMO_P360Prev":"Anterior","ETDEMO_P360ScopeNote":"Solo documentos de las organizaciones que tu rol puede leer.","ETDEMO_P360Search":"Buscar tercero","ETDEMO_P360Status":"Estado","ETDEMO_P360Summary":"Resumen","ETDEMO_P360TabPI":"Facturas de compra","ETDEMO_P360TabPM":"Pagos","ETDEMO_P360TabPO":"Pedidos de compra","ETDEMO_P360TabRC":"Cobros","ETDEMO_P360Tabs":"Tipos de documento","ETDEMO_P360TabSI":"Facturas de venta","ETDEMO_P360TabSO":"Pedidos de venta","ETDEMO_P360TaxId":"NIF","ETDEMO_P360Title":"Tercero 360","ETDEMO_P360Total":"Total","ETDEMO_P360TotalsNote":"Los totales por pestaña se calculan sobre todos los documentos del tercero, sin mirar la pestaña activa.","ETDEMO_P360Vendor":"Proveedor","ETDEMO_StockAxisNote":"El eje de almacenes ignora la búsqueda y la paginación.","ETDEMO_StockColTotals":"Total por almacén","ETDEMO_StockEmpty":"Ningún producto coincide con la búsqueda.","ETDEMO_StockGrand":"Total general","ETDEMO_StockNext":"Siguiente","ETDEMO_StockOf":"de","ETDEMO_StockOpenProduct":"Abrir la ficha del producto","ETDEMO_StockPage":"Página","ETDEMO_StockPageSize":"por página","ETDEMO_StockPrev":"Anterior","ETDEMO_StockProduct":"Producto","ETDEMO_StockProducts":"productos","ETDEMO_StockScopeNote":"Los totales por almacén cubren todo el conjunto filtrado, no solo la página visible.","ETDEMO_StockSearch":"Buscar por código o nombre de producto","ETDEMO_StockSort":"Ordenar por","ETDEMO_StockSortCode":"código","ETDEMO_StockSortName":"nombre","ETDEMO_StockSortQty":"cantidad","ETDEMO_StockTitle":"Stock por producto y almacén","ETDEMO_StockTotal":"Total","ETDEMO_StockUom":"UdM","ETDEMO_StockWarehouses":"almacenes","ETDEMO_StockZeros":"Incluir total cero","ETUIK_LoadFailed":"No se pudieron cargar los datos","ETUIK_Loading":"Cargando…","ETUIK_MeterAria":"Puntuacion %{score} sobre un objetivo de %{target}","ETUIK_RailAria":"Avance %{progress}%, esperado %{expected}%"});

/* com.etendoerp.uikit.samples/web/com.etendoerp.uikit.samples/js/partner-360.js */
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
    destroy: function (s) {
      var fn = searchers.get(s);
      if (fn) {
        fn.cancel();
        searchers.delete(s);
      }
    }
  });
})();

</#noparse>
