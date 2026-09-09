<#noparse>
/* ETDEMO_Product360 -- generado por verify/deploy-view.mjs. No editar en base de datos:
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

  var VERSION = '0.3.0';
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
   * A private, per-instance copy of the declared state.
   *
   * isc.shallowClone copies the top level only, so a nested literal -- `open: {}`, `acked: {}` --
   * would be one object shared by the spec and by every instance of the class. That is reachable
   * from the menu without any trick: closing a tab and reopening it builds a new instance, which
   * would then start with the previous one's expanded rows -- and in an inbox whose state holds
   * optimistic acknowledgements, with a previous instance's writes, including ones that were
   * rolled back.
   *
   * A JSON round trip is the right depth and asks nothing new of the app: defineAction already
   * requires that state survive exactly this, because that is how the rollback snapshot works.
   * A key declared undefined is dropped, which reads the same as never declaring it.
   */
  function initialState(spec) {
    return spec.state ? JSON.parse(JSON.stringify(spec.state)) : {};
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
        this.uikState = initialState(spec);
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

/* com.etendoerp.uikit.samples/web/com.etendoerp.uikit.samples/css/product-360.css */
OB.UIKit.style("com.etendoerp.uikit.samples.product360", "/*\n * ETDEMO_Product360 -- one product, every dimension of its stock.\n *\n * Everything is scoped with .uik-etdemo_product360, which is the root class the runtime puts on\n * this window and nowhere else: it writes `uik uik-<view id lowercased>`, so nothing here can\n * reach Classic's chrome, the Modern Skin's own surfaces or another demo of this module.\n *\n * No colour is written literally. The blue of action and focus is --uik-brand, cards are\n * --uik-surface on --uik-ground, borders are --uik-line, and the states borrow --uik-ok /\n * --uik-risk / --uik-bad. When the Modern Skin repaints those tokens, this window repaints with\n * it -- which is the whole reason the skin and the kit agree on a token vocabulary.\n *\n * The window's own vocabulary is prefixed pr360-, and its own tokens --pr360-*, because\n * ETDEMO_Partner360 already owns p360-. .uik-table, .uik-pager and .uik-bars come from uikit.css;\n * what is here is only what this screen needs and a plain list does not.\n */\n\n.uik-etdemo_product360 {\n  --pr360-radius: 8px;\n  --pr360-radius-sm: 6px;\n  --pr360-gap: 16px;\n  --pr360-gap-sm: 8px;\n  --pr360-tap: 36px; /* alto minimo de cualquier control */\n}\n\n/* --------------------------------------------------------------- cabecera */\n\n.uik-etdemo_product360 .pr360-head {\n  display: flex;\n  flex-wrap: wrap;\n  align-items: baseline;\n  gap: var(--pr360-gap-sm) var(--pr360-gap);\n  padding-bottom: 12px;\n  border-bottom: 2px solid var(--uik-brand);\n}\n\n.uik-etdemo_product360 .pr360-title {\n  margin: 0;\n  font-size: 20px;\n  font-weight: 600;\n  line-height: 1.2;\n  color: var(--uik-ink);\n}\n\n.uik-etdemo_product360 .pr360-subtitle {\n  flex: 1 1 260px;\n  margin: 0;\n  color: var(--uik-ink-soft);\n}\n\n.uik-etdemo_product360 .pr360-brand {\n  margin-left: auto;\n  padding: 2px 10px;\n  border: 1px solid var(--uik-line);\n  border-radius: 999px;\n  background: var(--uik-surface);\n  color: var(--uik-brand);\n  font-size: 11px;\n  font-weight: 600;\n  letter-spacing: 0.04em;\n  text-transform: uppercase;\n  white-space: nowrap;\n}\n\n/*\n * Auto-fit rather than a fixed column count: the tiles reflow on their own from a phone-width pane\n * to a wide desk without a media query deciding for them.\n */\n.uik-etdemo_product360 .pr360-tiles {\n  display: grid;\n  grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));\n  gap: var(--pr360-gap-sm);\n}\n\n.uik-etdemo_product360 .pr360-tile {\n  padding: 14px 16px;\n  border: 1px solid var(--uik-line);\n  border-left: 3px solid var(--uik-brand);\n  border-radius: var(--pr360-radius);\n  background: var(--uik-surface);\n}\n\n.uik-etdemo_product360 .pr360-tile-label {\n  margin: 0 0 4px;\n  font-size: 11px;\n  font-weight: 600;\n  letter-spacing: 0.03em;\n  text-transform: uppercase;\n  color: var(--uik-ink-soft);\n}\n\n.uik-etdemo_product360 .pr360-tile-value {\n  margin: 0;\n  font-size: 26px;\n  font-weight: 600;\n  line-height: 1.1;\n  font-variant-numeric: tabular-nums;\n  color: var(--uik-ink);\n}\n\n.uik-etdemo_product360 .pr360-tile-hint {\n  margin: 6px 0 0;\n  font-size: 11px;\n  color: var(--uik-ink-soft);\n}\n\n.uik-etdemo_product360 .pr360-asof {\n  margin: var(--pr360-gap-sm) 0 0;\n  font-size: 12px;\n  font-weight: 600;\n  color: var(--uik-brand);\n}\n\n.uik-etdemo_product360 .pr360-note {\n  margin: var(--pr360-gap-sm) 0 0;\n  max-width: 78ch;\n  font-size: 12px;\n  color: var(--uik-ink-soft);\n}\n\n/* ------------------------------------------------------- barra de filtros */\n\n/* Envuelve por defecto; si algo se desplaza, se desplaza dentro de su region, no el shell. */\n.uik-etdemo_product360 .pr360-bar {\n  display: flex;\n  flex-wrap: wrap;\n  align-items: flex-end;\n  gap: var(--pr360-gap-sm) var(--pr360-gap);\n  margin: var(--pr360-gap) 0 var(--pr360-gap-sm);\n  max-width: 100%;\n}\n\n/*\n * El ancho vive en el envoltorio, no en el input: .pr360-field es un contenedor flex en columna, y\n * un flex-basis puesto sobre el input se aplicaria a su ALTO -- que es exactamente lo que pasaba,\n * un campo de busqueda de 260 px de alto.\n */\n.uik-etdemo_product360 .pr360-field {\n  display: flex;\n  flex-direction: column;\n  gap: 3px;\n  flex: 0 1 260px;\n  min-width: 170px;\n}\n\n.uik-etdemo_product360 .pr360-field-label,\n.uik-etdemo_product360 .pr360-chips-label {\n  font-size: 11px;\n  font-weight: 600;\n  letter-spacing: 0.03em;\n  text-transform: uppercase;\n  color: var(--uik-ink-soft);\n}\n\n.uik-etdemo_product360 .pr360-input {\n  min-height: var(--pr360-tap);\n  padding: 4px 10px;\n  border: 1px solid var(--uik-line);\n  border-radius: var(--pr360-radius-sm);\n  background: var(--uik-surface);\n  color: var(--uik-ink);\n  font: inherit;\n}\n\n.uik-etdemo_product360 .pr360-input {\n  width: 100%;\n}\n\n.uik-etdemo_product360 .pr360-chips {\n  display: flex;\n  flex-wrap: wrap;\n  align-items: center;\n  gap: 6px;\n}\n\n.uik-etdemo_product360 .pr360-chip {\n  min-height: var(--pr360-tap);\n  padding: 0 12px;\n  border: 1px solid var(--uik-line);\n  border-radius: 999px;\n  background: var(--uik-surface);\n  color: var(--uik-ink-soft);\n  font: inherit;\n  font-size: 12px;\n  cursor: pointer;\n}\n\n.uik-etdemo_product360 .pr360-chip:hover {\n  border-color: var(--uik-brand);\n  color: var(--uik-ink);\n}\n\n/* El activo no depende solo del color: cambia el peso y gana el relleno de marca. */\n.uik-etdemo_product360 .pr360-chip.on {\n  border-color: var(--uik-brand);\n  background: var(--uik-brand);\n  color: var(--uik-surface);\n  font-weight: 700;\n}\n\n/* ----------------------------------------------------------------- tabla */\n\n/* El scroll horizontal, cuando hace falta, es de la tabla y no del shell. */\n.uik-etdemo_product360 .pr360-scroll {\n  max-width: 100%;\n  overflow-x: auto;\n  border: 1px solid var(--uik-line);\n  border-radius: var(--pr360-radius);\n  background: var(--uik-surface);\n}\n\n.uik-etdemo_product360 .pr360-table {\n  width: 100%;\n  border-collapse: collapse;\n  font-size: 13px;\n}\n\n.uik-etdemo_product360 .pr360-table th,\n.uik-etdemo_product360 .pr360-table td {\n  padding: 7px 10px;\n  border-bottom: 1px solid var(--uik-line);\n  text-align: left;\n  white-space: nowrap;\n}\n\n.uik-etdemo_product360 .pr360-table thead th {\n  position: sticky;\n  top: 0;\n  z-index: 1;\n  background: var(--uik-ground);\n  font-size: 11px;\n  font-weight: 700;\n  letter-spacing: 0.03em;\n  text-transform: uppercase;\n  color: var(--uik-ink-soft);\n}\n\n.uik-etdemo_product360 .pr360-table tbody tr:last-child td {\n  border-bottom: 0;\n}\n\n.uik-etdemo_product360 .pr360-table tbody tr:hover {\n  background: var(--uik-ground);\n}\n\n/* La fila abierta se marca por borde y peso, no solo por tono. */\n.uik-etdemo_product360 .pr360-table tbody tr.on {\n  background: var(--uik-ground);\n  box-shadow: inset 3px 0 0 var(--uik-brand);\n}\n\n.uik-etdemo_product360 .pr360-num {\n  text-align: right;\n  font-variant-numeric: tabular-nums;\n}\n\n.uik-etdemo_product360 .pr360-cell-key {\n  font-weight: 600;\n}\n\n.uik-etdemo_product360 .pr360-uom {\n  color: var(--uik-ink-soft);\n  font-size: 11px;\n}\n\n.uik-etdemo_product360 .pr360-dash {\n  color: var(--uik-flat);\n}\n\n/* Un boton que se lee como enlace: no hay URL que seguir, abre el detalle en estado. */\n.uik-etdemo_product360 .pr360-link {\n  padding: 0;\n  border: 0;\n  background: none;\n  color: var(--uik-brand);\n  font: inherit;\n  font-weight: 600;\n  text-align: left;\n  cursor: pointer;\n}\n\n.uik-etdemo_product360 .pr360-link:hover {\n  text-decoration: underline;\n}\n\n/* ----------------------------------------------------------------- pager */\n\n.uik-etdemo_product360 .pr360-pager {\n  display: flex;\n  flex-wrap: wrap;\n  align-items: center;\n  gap: var(--pr360-gap-sm);\n  margin-top: var(--pr360-gap-sm);\n}\n\n.uik-etdemo_product360 .pr360-page {\n  min-height: var(--pr360-tap);\n  padding: 0 14px;\n  border: 1px solid var(--uik-line);\n  border-radius: var(--pr360-radius-sm);\n  background: var(--uik-surface);\n  color: var(--uik-brand);\n  font: inherit;\n  font-weight: 600;\n  cursor: pointer;\n}\n\n.uik-etdemo_product360 .pr360-page[disabled] {\n  color: var(--uik-flat);\n  cursor: default;\n}\n\n.uik-etdemo_product360 .pr360-page-of {\n  font-size: 12px;\n  color: var(--uik-ink-soft);\n  font-variant-numeric: tabular-nums;\n}\n\n.uik-etdemo_product360 .pr360-close {\n  min-height: var(--pr360-tap);\n  padding: 0 12px;\n  border: 1px solid var(--uik-line);\n  border-radius: var(--pr360-radius-sm);\n  background: var(--uik-surface);\n  color: var(--uik-ink-soft);\n  font: inherit;\n  font-size: 12px;\n  cursor: pointer;\n}\n\n.uik-etdemo_product360 .pr360-close:hover {\n  border-color: var(--uik-brand);\n  color: var(--uik-ink);\n}\n\n/* ------------------------------------------------- estados de presentacion */\n\n.uik-etdemo_product360 .pr360-state {\n  padding: 20px 24px;\n  border: 1px solid var(--uik-line);\n  border-radius: var(--pr360-radius);\n  background: var(--uik-surface);\n}\n\n.uik-etdemo_product360 .pr360-state-title {\n  margin: 0 0 6px;\n  font-size: 15px;\n  font-weight: 600;\n  color: var(--uik-ink);\n}\n\n.uik-etdemo_product360 .pr360-state-body {\n  margin: 0;\n  max-width: 62ch;\n  color: var(--uik-ink-soft);\n}\n\n.uik-etdemo_product360 .pr360-state-empty {\n  border-left: 3px solid var(--uik-flat);\n}\n\n/* ------------------------------------------------------- foco y accesibilidad */\n\n/* El foco se ve siempre: la navegacion por teclado es criterio de aceptacion, no un extra. */\n.uik-etdemo_product360 :focus-visible {\n  outline: 2px solid var(--uik-brand);\n  outline-offset: 2px;\n}\n\n/* -------------------------------------------------------------- responsive */\n\n/*\n * Un solo corte, para tablet y para el zoom alto: la marca deja de empujarse a la derecha, los\n * campos ocupan la fila entera y los paddings se achican. La grilla de tiles y las barras de\n * filtros ya envuelven solas, asi que no necesitan reglas propias.\n */\n@media (max-width: 820px) {\n  .uik-etdemo_product360 .pr360-brand {\n    margin-left: 0;\n  }\n\n  .uik-etdemo_product360 .pr360-field {\n    flex: 1 1 100%;\n  }\n\n  .uik-etdemo_product360 .pr360-state {\n    padding: 16px;\n  }\n\n  .uik-etdemo_product360 .pr360-table th,\n  .uik-etdemo_product360 .pr360-table td {\n    padding: 6px 8px;\n  }\n\n  \n  \n\n  \n\n  \n  \n\n  \n  \n}\n\n/* ==========================================================================\n * Propuestas de lectura: Console, Locate y Flow\n *\n * Tres apuestas distintas sobre como se lee un almacen, montadas sobre los mismos read models que\n * las cinco ventanas de arriba. Comparten este archivo a proposito: los tokens, la tabla, el pager\n * y los estados ya estan resueltos, y una hoja aparte por propuesta las dejaria divergir justo\n * mientras se estan comparando.\n *\n * Lo unico que cada propuesta aporta es su reparto del espacio. Todo lo demas -- colores, foco,\n * alturas de control, tipografia -- lo hereda de las reglas anteriores sin redefinir nada.\n * ========================================================================== */\n\n/* ------------------------------------------------------- vocabulario comun */\n\n/* Un dato secundario que acompana al principal en la misma celda o en el mismo renglon. */\n.uik-etdemo_product360 .pr360-sub {\n  display: block;\n  font-style: normal;\n  font-size: 11px;\n  color: var(--uik-ink-soft);\n}\n\n/* Un panel: la caja con la que Console y Locate agrupan algo que no es una tabla suelta. */\n.uik-etdemo_product360 .pr360-panel {\n  padding: 14px 16px;\n  border: 1px solid var(--uik-line);\n  border-radius: var(--pr360-radius);\n  background: var(--uik-surface);\n}\n\n.uik-etdemo_product360 .pr360-panel-head {\n  display: flex;\n  flex-wrap: wrap;\n  align-items: center;\n  gap: var(--pr360-gap-sm);\n  margin-bottom: var(--pr360-gap-sm);\n}\n\n.uik-etdemo_product360 .pr360-panel-title {\n  flex: 1 1 auto;\n  margin: 0 0 var(--pr360-gap-sm);\n  font-size: 13px;\n  font-weight: 700;\n  letter-spacing: 0.03em;\n  text-transform: uppercase;\n  color: var(--uik-ink-soft);\n}\n\n/* El titulo dentro de una cabecera de panel ya lleva el margen de la cabecera. */\n.uik-etdemo_product360 .pr360-panel-head .pr360-panel-title {\n  margin-bottom: 0;\n}\n\n/*\n * Un dato que esta pero no reclama nada: el pedido sin lineas pendientes dice cuantas tiene y lo\n * dice en voz baja, para que el contraste lo siga guardando quien si tiene trabajo esperando.\n */\n.uik-etdemo_product360 .pr360-quiet {\n  color: var(--uik-flat);\n}\n\n/*\n * Barras con grupos de pastillas: se alinean ARRIBA. Con align-items:flex-end -- el valor de\n * .pr360-bar, correcto cuando todos los campos son inputs de la misma altura -- un grupo de tres\n * filas de pastillas estira su linea y el buscador queda pegado al fondo de ella: 84px de hueco\n * encima del campo en Product 360, y otros 92 encima del tamano de pagina.\n */\n.uik-etdemo_product360 .pr360-bar-p360 {\n  align-items: flex-start;\n}\n\n.uik-etdemo_product360 .pr360-field-wide {\n  flex: 1 1 320px;\n}\n\n/* ============================================================= Product 360\n *\n * La propuesta D no reparte una pantalla en paneles: pone un producto en el centro y alrededor\n * todos los ejes que la base sabe cruzar. Por eso el reparto es de dos columnas y no de cuatro\n * cuadrantes -- a la izquierda el carril desde el que se elige, a la derecha una pila de paneles\n * que se lee de arriba abajo -- y por eso la columna izquierda es estrecha y fija: elegir el\n * producto es un gesto que se repite, y leerlo es lo que ocupa el tiempo.\n *\n * Dos reglas de esta hoja mandan aqui y explican casi todo lo que sigue: la region es el nodo que\n * desplaza (uikSetRegion lee su scrollTop, no el de un hijo) y ninguna clase escribe un color,\n * solo tokens. La segunda tiene una consecuencia de diseno en el grafico: entrada y salida NO son\n * verde y rojo. Una salida de almacen no es un error -- es un albaran cumplido -- asi que la\n * direccion se distingue por el lado del eje del que crece la barra, y el tono solo separa las\n * dos series: la marca para lo que entra, la tinta suave para lo que sale.\n */\n\n/*\n * El reparto. Las regiones son hijos directos de la raiz, asi que la rejilla se monta sobre\n * ellas sin envoltorio propio.\n *\n * Tres columnas y no dos: una pila de diez paneles de 784px medía 4.506px, con cinco paneles\n * cortos -- almacen 243, lote 163, mezcla 261, pares 613, cartera 633 -- ocupando un ancho que no\n * necesitan mientras la columna izquierda estaba vacia desde y=1138. Los cortos van emparejados\n * en dos parejas que dicen lo mismo cada una: DONDE ESTA (almacen | lote) y CON QUE SE COMPARA\n * (los pares de su categoria | la cartera abierta). Los que llevan una tabla o el grafico se\n * quedan a ancho completo, porque ahi el ancho es el dibujo.\n *\n * El carril y su pager comparten el area de las ocho filas de la derecha y se PEGAN: elegir el\n * siguiente producto es el gesto que mas se repite, y sin pegarlos pedia volver 4.000px arriba.\n * El area se declara 3/11 y no 3/-1 a proposito: la rejilla no declara grid-template-rows, asi\n * que no hay rejilla explicita y -1 resuelve a la primera linea. Hay que actualizar el 11 si\n * cambia el numero de regiones de la derecha (hoy ocho: filas 3 a 10).\n *\n * Que el carril se estire sobre filas vacias ya no importa -- align-items:start no lo estira y su\n * max-height manda -- que es lo que hacia imposible abarcarlas cuando el pager iba en su\n * propia fila.\n */\n.uik-etdemo_product360 {\n  /*\n   * Un solo numero para el alto del carril: lo usa su max-height, el hueco que el pager reserva\n   * debajo y el top al que el pager se pega. 48vh y no 64: con la barra en tres lineas el carril\n   * empieza sobre y=353, y a 48vh de 900 (432px) acaba en 785 con su pager dentro del pliegue.\n   */\n  --pr360-rail: clamp(320px, 48vh, 720px);\n}\n\n@media (min-width: 1200px) {\n  .uik-etdemo_product360 {\n    display: grid;\n    grid-template-columns: minmax(280px, 340px) minmax(0, 1fr) minmax(0, 1fr);\n    gap: var(--pr360-gap-sm) var(--pr360-gap);\n    align-items: start;\n  }\n\n  /* La separacion entre regiones la pone el gap de la rejilla; el margen apilado sobraria. */\n  .uik-etdemo_product360 > .uik-region + .uik-region {\n    margin-top: 0;\n  }\n\n  .uik-etdemo_product360 > .uik-region-head,\n  .uik-etdemo_product360 > .uik-region-bar {\n    grid-column: 1 / -1;\n  }\n\n  .uik-etdemo_product360 > .uik-region-rail {\n    grid-column: 1;\n    grid-row: 3 / 11;\n    align-self: start;\n    position: sticky;\n    top: var(--pr360-gap);\n  }\n\n  /*\n   * El pager comparte el area del carril y se coloca bajo su ALTO MAXIMO, no bajo sus filas: asi\n   * no se le monta encima ni cuando el carril viene corto -- una busqueda con dos resultados --\n   * y se pega justo debajo de el. El precio es un hueco entre los dos en ese caso, que es mejor\n   * que escribir aqui el alto del pager.\n   *\n   * El selector repite .uik-region a proposito. El reset de arriba (> .uik-region + .uik-region)\n   * suma cuatro clases y este solo tres, asi que ganaba por especificidad y ponia el margen a\n   * cero: el pager se quedaba en la linea de la fila 3, y su sticky lo empujaba a 556px, encima\n   * del carril. Medido: pager [556, 612] dentro de un carril [355, 787].\n   */\n  .uik-etdemo_product360 > .uik-region.uik-region-pager {\n    grid-column: 1;\n    grid-row: 3 / 11;\n    align-self: start;\n    margin-top: calc(var(--pr360-rail) + var(--pr360-gap-sm));\n    position: sticky;\n    top: calc(var(--pr360-gap) + var(--pr360-rail) + var(--pr360-gap-sm));\n  }\n\n  /* Ancho completo de la derecha: la ficha, el libro, la mezcla, los sitios y el rastro. */\n  .uik-etdemo_product360 > .uik-region-hero {\n    grid-column: 2 / -1;\n    grid-row: 3;\n  }\n\n  .uik-etdemo_product360 > .uik-region-ledger {\n    grid-column: 2 / -1;\n    grid-row: 4;\n  }\n\n  .uik-etdemo_product360 > .uik-region-mix {\n    grid-column: 2 / -1;\n    grid-row: 5;\n  }\n\n  .uik-etdemo_product360 > .uik-region-locators {\n    grid-column: 2 / -1;\n    grid-row: 7;\n  }\n\n  .uik-etdemo_product360 > .uik-region-trail {\n    grid-column: 2 / -1;\n    grid-row: 9;\n  }\n\n  .uik-etdemo_product360 > .uik-region-tpager {\n    grid-column: 2 / -1;\n    grid-row: 10;\n  }\n\n  /* Las dos parejas. Si falta un miembro -- sin lotes, sin cartera -- el otro se queda en su\n   * columna y la casilla vecina queda en blanco: .uik-region:empty no se dibuja. */\n  .uik-etdemo_product360 > .uik-region-warehouses {\n    grid-column: 2;\n    grid-row: 6;\n  }\n\n  .uik-etdemo_product360 > .uik-region-lots {\n    grid-column: 3;\n    grid-row: 6;\n  }\n\n  .uik-etdemo_product360 > .uik-region-peers {\n    grid-column: 2;\n    grid-row: 8;\n  }\n\n  .uik-etdemo_product360 > .uik-region-pending {\n    grid-column: 3;\n    grid-row: 8;\n  }\n}\n\n/*\n * Apilado, la ficha va delante del carril.\n *\n * Su estado vacio ES la instruccion (\"elige un producto\"), asi que la respuesta aparece donde\n * estaba la pregunta. Sin esto, en una pantalla de 768 lo unico que cambiaba al pulsar un\n * producto era el borde azul de su renglon: la ficha quedaba 500px por debajo del pliegue. Es el\n * mismo arreglo que Console acepto en la ronda 3, y solo cambia el orden VISUAL -- el DOM sigue\n * con el carril antes, que es el orden en que se tabula.\n */\n@media (max-width: 1199px) {\n  .uik-etdemo_product360 {\n    display: flex;\n    flex-direction: column;\n  }\n\n  .uik-etdemo_product360 > .uik-region-head {\n    order: -3;\n  }\n\n  .uik-etdemo_product360 > .uik-region-bar {\n    order: -2;\n  }\n\n  .uik-etdemo_product360 > .uik-region-hero {\n    order: -1;\n  }\n}\n\n/*\n * El carril desplaza, y desplaza la region: 'rail' esta declarado en keepScroll, que lee el\n * scrollTop del nodo de la region. Con el overflow en la lista de dentro ese numero seria siempre\n * 0 y elegir un producto -- que repinta el carril para marcar el elegido -- devolveria la lista al\n * principio, que es exactamente lo que no puede pasar en la region con la que se elige.\n */\n.uik-etdemo_product360 > .uik-region-rail {\n  max-height: var(--pr360-rail);\n  overflow-y: auto;\n  border: 1px solid var(--uik-line);\n  border-radius: var(--pr360-radius);\n  background: var(--uik-surface);\n}\n\n/* El marco paso a la region, asi que el panel de dentro no lleva el suyo. */\n.uik-etdemo_product360 > .uik-region-rail .pr360-panel {\n  border: 0;\n  border-radius: 0;\n  background: none;\n}\n\n/* La cabecera se queda arriba: si no, el titulo y el contador se van al bajar por el carril. */\n.uik-etdemo_product360 > .uik-region-rail .pr360-panel-head {\n  position: sticky;\n  top: 0;\n  z-index: 1;\n  margin: -14px -16px var(--pr360-gap-sm);\n  padding: 14px 16px 0;\n  background: var(--uik-surface);\n}\n\n/*\n * La tabla de sitios, por lo mismo: 'locators' tambien esta en keepScroll. Es la unica otra\n * region que desplaza, y es a proposito -- prometer scroll conservado en una region que crece\n * libremente es letra muerta, porque no hay scrollTop que conservar.\n */\n.uik-etdemo_product360 > .uik-region-locators {\n  max-height: clamp(240px, 46vh, 560px);\n  overflow-y: auto;\n  border: 1px solid var(--uik-line);\n  border-radius: var(--pr360-radius);\n  background: var(--uik-surface);\n}\n\n.uik-etdemo_product360 > .uik-region-locators .pr360-panel {\n  border: 0;\n  border-radius: 0;\n  background: none;\n}\n\n.uik-etdemo_product360 > .uik-region-locators .pr360-panel-head {\n  position: sticky;\n  top: 0;\n  z-index: 2;\n  margin: -14px -16px var(--pr360-gap-sm);\n  padding: 14px 16px 0;\n  background: var(--uik-surface);\n}\n\n/*\n * La cabecera de la tabla se pega bajo la del panel. El fondo es obligatorio: sin el, las filas\n * pasan por debajo del texto y se lee una cifra encima de su rotulo.\n */\n.uik-etdemo_product360 > .uik-region-locators .pr360-table thead th {\n  position: sticky;\n  top: 34px;\n  z-index: 1;\n  background: var(--uik-surface);\n}\n\n/*\n * El rastro lleva su tabla dentro de un .pr360-scroll, y el marco general de ese envoltorio sobra\n * aqui: el panel ya tiene el suyo, asi que dibujarlo otra vez pone dos rectangulos concentricos a\n * dos pixeles uno del otro. Queda solo el eje horizontal, que es lo unico que se le pedia: a 768px\n * de ancho la tabla mide 573 contra 468 de region y sin desplazamiento propio el shell le cortaba\n * la columna del documento sin dejar gesto para alcanzarla.\n */\n.uik-etdemo_product360 > .uik-region-trail .pr360-scroll {\n  border: 0;\n  border-radius: 0;\n  background: none;\n}\n\n/* ------------------------------------------------- vocabulario de la propuesta */\n\n/* El dato de la derecha de una cabecera de panel: cuantos hay, en que unidad, de cuantos. */\n.uik-etdemo_product360 .pr360-panel-aside {\n  flex: 0 0 auto;\n  font-size: 11px;\n  font-weight: 600;\n  letter-spacing: 0.03em;\n  color: var(--uik-ink-soft);\n  font-variant-numeric: tabular-nums;\n}\n\n/* Un titulo de segundo nivel dentro de un panel, para un bloque que no merece panel propio. */\n.uik-etdemo_product360 .pr360-panel-sub {\n  margin: 0 0 var(--pr360-gap-sm);\n  font-size: 11px;\n  font-weight: 700;\n  letter-spacing: 0.03em;\n  text-transform: uppercase;\n  color: var(--uik-ink-soft);\n}\n\n/* Chips que estan pero no compiten: tamano de pagina, grano del libro. */\n.uik-etdemo_product360 .pr360-chips-quiet .pr360-chip {\n  min-height: 28px;\n  padding: 0 10px;\n  font-size: 11px;\n}\n\n/*\n * Una barra proporcional dentro de un renglon o de una celda. No es .uik-spark, que es un SVG de\n * serie temporal: esto es una sola cifra comparada con el maximo de lo que se esta viendo, y por\n * eso el ancho llega en --uik-v como en las barras del kit.\n */\n.uik-etdemo_product360 .pr360-spark {\n  position: relative;\n  display: block;\n  height: 4px;\n  border-radius: 2px;\n  background: var(--uik-ground);\n  overflow: hidden;\n}\n\n/*\n * El piso: un valor que no es cero se ve, y un cero no se ve.\n *\n * min(v * 100000, Npx) vale exactamente 0 cuando --uik-v es 0% -- que es lo que emiten K.bars y\n * pickBar para una fila a cero -- y N pixeles en cuanto hay dato. Sin el, 15.000 sobre un maximo\n * de 1.005.000 son 11px de relleno a opacidad 0,16 que arrancan debajo del padding y del rotulo\n * del kit: no era ancho cero, era ancho enterrado, y la fila se leia igual que una vacia.\n */\n.uik-etdemo_product360 .pr360-spark::before {\n  content: \"\";\n  position: absolute;\n  inset: 0 auto 0 0;\n  width: max(var(--uik-v, 0%), min(calc(var(--uik-v, 0%) * 100000), 6px));\n  border-radius: 2px;\n  background: var(--uik-brand);\n  opacity: 0.55;\n}\n\n/*\n * Lo mismo para las barras del kit dentro de esta ventana. Es un matiz al pintado de\n * com.etendoerp.uikit, cualificado dentro de la raiz del modulo y por un motivo concreto: el kit\n * resuelve la geometria, y el modulo solo garantiza que \"hay dato\" y \"no hay dato\" no coincidan.\n * Los 18px son los 8 de padding del kit mas 10 visibles.\n */\n.uik-etdemo_product360 .uik-bars .uik-bar::before {\n  width: max(var(--uik-v, 0%), min(calc(var(--uik-v, 0%) * 100000), 18px));\n}\n\n/* Un texto que sigue en el DOM para que su hueco mida igual, pero que no se lee. */\n.uik-etdemo_product360 .pr360-mute {\n  visibility: hidden;\n}\n\n/* ------------------------------------------------------------------ carril */\n\n.uik-etdemo_product360 .pr360-rail-list {\n  margin: 0;\n  padding: 0;\n  list-style: none;\n}\n\n.uik-etdemo_product360 .pr360-rail-item + .pr360-rail-item {\n  border-top: 1px solid var(--uik-line);\n}\n\n/*\n * El renglon entero es el boton, no un enlace dentro del renglon: la diana es lo que se ve, que\n * es la unica manera de que elegir el producto siguiente no pida apuntar.\n */\n.uik-etdemo_product360 .pr360-rail-pick {\n  display: block;\n  width: 100%;\n  padding: 8px 6px;\n  border: 0;\n  border-left: 3px solid transparent;\n  border-radius: 0;\n  background: none;\n  color: inherit;\n  font: inherit;\n  text-align: left;\n  cursor: pointer;\n}\n\n.uik-etdemo_product360 .pr360-rail-pick:hover {\n  background: var(--uik-ground);\n}\n\n/* El elegido no depende solo del tono: gana el borde de marca y el peso del codigo. */\n.uik-etdemo_product360 .pr360-rail-pick.on {\n  border-left-color: var(--uik-brand);\n  background: var(--uik-ground);\n}\n\n.uik-etdemo_product360 .pr360-rail-top {\n  display: flex;\n  align-items: baseline;\n  gap: var(--pr360-gap-sm);\n}\n\n.uik-etdemo_product360 .pr360-rail-code {\n  flex: 1 1 auto;\n  min-width: 0;\n  overflow: hidden;\n  text-overflow: ellipsis;\n  white-space: nowrap;\n  font-weight: 700;\n  font-variant-numeric: tabular-nums;\n  color: var(--uik-ink);\n}\n\n.uik-etdemo_product360 .pr360-rail-qty {\n  flex: 0 0 auto;\n  font-weight: 600;\n  font-variant-numeric: tabular-nums;\n  color: var(--uik-ink);\n}\n\n.uik-etdemo_product360 .pr360-rail-name {\n  display: block;\n  overflow: hidden;\n  text-overflow: ellipsis;\n  white-space: nowrap;\n  font-size: 12px;\n  color: var(--uik-ink-soft);\n}\n\n.uik-etdemo_product360 .pr360-rail-pick .pr360-spark {\n  margin: 5px 0 4px;\n}\n\n/* Categoria, movimientos y fecha: el tercero se va a la derecha para caer siempre igual. */\n.uik-etdemo_product360 .pr360-rail-foot {\n  display: flex;\n  align-items: baseline;\n  gap: var(--pr360-gap-sm);\n  font-style: normal;\n  font-size: 11px;\n  color: var(--uik-ink-soft);\n}\n\n.uik-etdemo_product360 .pr360-rail-foot > span:first-child {\n  flex: 1 1 auto;\n  min-width: 0;\n  overflow: hidden;\n  text-overflow: ellipsis;\n  white-space: nowrap;\n}\n\n.uik-etdemo_product360 .pr360-rail-foot > span + span {\n  flex: 0 0 auto;\n  font-variant-numeric: tabular-nums;\n}\n\n/* ------------------------------------------------------------- la ficha */\n\n/*\n * La ficha en dos columnas cuando hay sitio: identidad a la izquierda, cifras a la derecha. La\n * identidad no crece -- es texto y se lee de una vez -- y las cifras se llevan el resto.\n */\n.uik-etdemo_product360 .pr360-hero {\n  display: grid;\n  gap: var(--pr360-gap-sm) var(--pr360-gap);\n}\n\n/*\n * Las areas. Las ocho cifras iban en una sola caja y el reparto reservado cruzaba la ficha entera\n * debajo, asi que entre la columna de identidad (que acaba donde acaba su texto) y el bloque de\n * valor quedaban unos 185px de blanco. Partidas en dos -- las tres CANTIDADES arriba a la derecha\n * y los cinco CONTEOS a lo ancho debajo -- el reparto reservado cae justo bajo las cantidades que\n * reparte, y la identidad ocupa las dos filas.\n */\n@media (min-width: 900px) {\n  .uik-etdemo_product360 .pr360-hero {\n    grid-template-columns: minmax(220px, 300px) minmax(0, 1fr);\n    grid-template-areas:\n      \"id qty\"\n      \"id split\"\n      \"counts counts\"\n      \"worth worth\"\n      \"asof asof\";\n    align-content: start;\n  }\n\n  .uik-etdemo_product360 .pr360-hero .pr360-hero-id {\n    grid-area: id;\n  }\n\n  .uik-etdemo_product360 .pr360-hero .pr360-hero-qty {\n    grid-area: qty;\n    align-content: start;\n  }\n\n  .uik-etdemo_product360 .pr360-hero .pr360-split {\n    grid-area: split;\n  }\n\n  .uik-etdemo_product360 .pr360-hero .pr360-hero-counts {\n    grid-area: counts;\n  }\n\n  .uik-etdemo_product360 .pr360-hero .pr360-worth-block {\n    grid-area: worth;\n  }\n\n  .uik-etdemo_product360 .pr360-hero .pr360-asof {\n    grid-area: asof;\n  }\n}\n\n/* La identidad es la primera celda de la rejilla, y sin esto el nombre largo no puede recortarse. */\n.uik-etdemo_product360 .pr360-hero-id {\n  min-width: 0;\n}\n\n.uik-etdemo_product360 .pr360-hero-code {\n  margin: 0;\n  font-size: 22px;\n  font-weight: 700;\n  line-height: 1.15;\n  font-variant-numeric: tabular-nums;\n  color: var(--uik-ink);\n}\n\n.uik-etdemo_product360 .pr360-hero-name {\n  margin: 4px 0 0;\n  font-size: 15px;\n  color: var(--uik-ink);\n}\n\n.uik-etdemo_product360 .pr360-hero-desc {\n  margin: 6px 0 0;\n  max-width: 46ch;\n  font-size: 12px;\n  color: var(--uik-ink-soft);\n}\n\n.uik-etdemo_product360 .pr360-hero-tags {\n  display: flex;\n  flex-wrap: wrap;\n  align-items: center;\n  gap: 6px;\n  margin: var(--pr360-gap-sm) 0 0;\n}\n\n/*\n * Ocho cifras, no cuatro: caben mas estrechas y la cifra baja de 26px a 20px. A 26px las ocho\n * pedian dos filas de cuatro y la ficha se comia el pliegue entera.\n */\n.uik-etdemo_product360 .pr360-hero-tiles {\n  grid-template-columns: repeat(auto-fit, minmax(124px, 1fr));\n  gap: 6px;\n}\n\n.uik-etdemo_product360 .pr360-hero-tiles .pr360-tile {\n  padding: 8px 10px;\n}\n\n/* Las partes de una casilla son spans aqui, asi que el margen necesita que sean bloque. */\n.uik-etdemo_product360 .pr360-hero-tiles .pr360-tile-label,\n.uik-etdemo_product360 .pr360-hero-tiles .pr360-tile-value,\n.uik-etdemo_product360 .pr360-hero-tiles .pr360-tile-hint {\n  display: block;\n}\n\n.uik-etdemo_product360 .pr360-hero-tiles .pr360-tile-value {\n  font-size: 20px;\n}\n\n.uik-etdemo_product360 .pr360-hero-tiles .pr360-tile-hint {\n  margin-top: 4px;\n}\n\n/*\n * El reparto reservado. Una sola cifra -- el porcentaje reservado -- porque el otro es su\n * complemento y escribir los dos invita a sumarlos con la cantidad en mano.\n *\n * Lo dibuja .pr360-spark y no .uik-rail. El carril del kit es un carril de RITMO: su relleno\n * (--uik-p) es lo consumido y su marca (--uik-e) es donde deberia ir, semantica que este dato no\n * tiene. Y estaba dibujado al reves de lo que decia: el relleno llevaba el porcentaje DISPONIBLE\n * mientras el texto al lado nombraba el RESERVADO, asi que en esta base -- donde solo 1 de las\n * 255 filas de existencias tiene reserva -- la barra salia llena junto a un \"0,0% Reserved\".\n * Ahora el relleno es el reservado, que es lo que la cifra nombra, y el piso de .pr360-spark deja\n * marca en cuanto la reserva no es cero.\n */\n.uik-etdemo_product360 .pr360-split {\n  display: flex;\n  flex-wrap: wrap;\n  align-items: center;\n  gap: var(--pr360-gap-sm);\n  padding-top: var(--pr360-gap-sm);\n  border-top: 1px solid var(--uik-line);\n}\n\n.uik-etdemo_product360 .pr360-split-label {\n  flex: 0 0 auto;\n  font-size: 11px;\n  font-weight: 600;\n  letter-spacing: 0.03em;\n  text-transform: uppercase;\n  color: var(--uik-ink-soft);\n}\n\n.uik-etdemo_product360 .pr360-split-rail {\n  flex: 1 1 200px;\n  min-width: 160px;\n  height: 8px;\n  border-radius: 4px;\n}\n\n.uik-etdemo_product360 .pr360-split-rail::before {\n  border-radius: 4px;\n}\n\n.uik-etdemo_product360 .pr360-split-value {\n  flex: 0 0 auto;\n  font-size: 12px;\n  font-weight: 600;\n  font-variant-numeric: tabular-nums;\n  color: var(--uik-ink);\n}\n\n.uik-etdemo_product360 .pr360-worth-block {\n  padding-top: var(--pr360-gap-sm);\n  border-top: 1px solid var(--uik-line);\n}\n\n/* Cuatro columnas cortas: no necesita el ancho de la ficha para leerse. */\n.uik-etdemo_product360 .pr360-worth {\n  max-width: 62ch;\n  font-size: 12px;\n}\n\n/* --------------------------------------------------------------- el grafico */\n\n/*\n * El grafico reserva dos margenes: 62px a la izquierda para la escala y 18px abajo para el rotulo\n * del eje. Los dos son padding del contenedor, asi que el SVG no los pisa y la escala no tapa\n * ninguna barra -- que es lo que pasaria poniendo el texto encima del dibujo.\n *\n * El contenedor es el bloque de referencia de las dos capas absolutas: la escala se posiciona\n * contra su caja de padding, de modo que un `top` en pixeles es la misma coordenada que la unidad\n * del viewBox (el SVG mide 190px de alto y su viewBox 190 unidades).\n */\n.uik-etdemo_product360 .pr360-chart {\n  position: relative;\n  margin-top: var(--pr360-gap-sm);\n  padding-left: 62px;\n  padding-bottom: 18px;\n}\n\n.uik-etdemo_product360 .pr360-ch-scale {\n  position: absolute;\n  left: 0;\n  width: 56px;\n  transform: translateY(-50%);\n  text-align: right;\n  font-size: 10px;\n  line-height: 1;\n  color: var(--uik-ink-soft);\n  font-variant-numeric: tabular-nums;\n  pointer-events: none;\n}\n\n/*\n * El SVG se estira a lo ancho del panel con preserveAspectRatio=\"none\", que deforma cualquier\n * cosa que tenga forma propia. Por eso no lleva ni una letra y por eso cada trazo declara\n * vector-effect: sin el, el ancho de linea se estiraria con el eje y la linea del saldo saldria\n * mas gruesa en una pantalla ancha que en una estrecha.\n */\n.uik-etdemo_product360 .pr360-chart-svg {\n  display: block;\n  width: 100%;\n  height: 190px;\n}\n\n.uik-etdemo_product360 .pr360-ch-line {\n  fill: none;\n  stroke: var(--uik-brand);\n  stroke-width: 1.5;\n  stroke-linejoin: round;\n  vector-effect: non-scaling-stroke;\n}\n\n.uik-etdemo_product360 .pr360-ch-area {\n  fill: var(--uik-brand);\n  stroke: none;\n  opacity: 0.12;\n}\n\n.uik-etdemo_product360 .pr360-ch-axis {\n  stroke: var(--uik-line);\n  stroke-width: 1;\n  vector-effect: non-scaling-stroke;\n}\n\n/* Entrada y salida: la direccion la dice el lado del eje, el tono solo separa las dos series. */\n.uik-etdemo_product360 .pr360-ch-in {\n  fill: var(--uik-brand);\n  opacity: 0.75;\n}\n\n.uik-etdemo_product360 .pr360-ch-out {\n  fill: var(--uik-ink-soft);\n  opacity: 0.75;\n}\n\n/* El periodo elegido, marcado detras de las dos series y no encima. */\n.uik-etdemo_product360 .pr360-ch-slot {\n  fill: var(--uik-brand);\n  opacity: 0.08;\n}\n\n/*\n * La tira de botones es a la vez el eje del tiempo y la unica superficie pulsable del grafico.\n * Cada boton se lleva la misma fraccion del ancho que su periodo se lleva en el dibujo, asi que\n * la diana cae debajo de sus barras sin que nadie calcule una posicion.\n */\n/*\n * La tira cubre el grafico entero, no solo la linea de rotulos: la diana de un periodo mide los\n * 208px de alto del dibujo en vez de los 18 de su nombre, asi que pulsar una columna es pulsar\n * donde estan sus barras. Cada boton se lleva la misma fraccion del ancho que su periodo se lleva\n * en el dibujo, asi que la diana cae bajo sus barras sin que nadie calcule una posicion.\n *\n * Empieza en los 62px del canal de la escala porque el posicionamiento absoluto se mide contra la\n * caja de padding, que incluye ese canal.\n */\n.uik-etdemo_product360 .pr360-chart-hits {\n  position: absolute;\n  top: 0;\n  right: 0;\n  bottom: 0;\n  left: 62px;\n  display: flex;\n  align-items: stretch;\n  padding: 0 6px;\n}\n\n.uik-etdemo_product360 .pr360-ch-hit {\n  position: relative;\n  display: flex;\n  flex: 1 1 0;\n  flex-direction: column;\n  justify-content: flex-end;\n  min-width: 0;\n  padding: 0;\n  border: 0;\n  background: none;\n  color: inherit;\n  font: inherit;\n  cursor: pointer;\n}\n\n/* El tinte del hover es una columna entera, muy tenue: va sobre el dibujo y no puede taparlo. */\n.uik-etdemo_product360 .pr360-ch-hit::before {\n  content: \"\";\n  position: absolute;\n  inset: 0;\n  background: var(--uik-brand);\n  opacity: 0;\n  pointer-events: none;\n}\n\n.uik-etdemo_product360 .pr360-ch-hit:hover::before {\n  opacity: 0.06;\n}\n\n/*\n * El nombre queda al pie de su columna, en los 18px que el contenedor reserva, y su borde\n * superior dibuja el eje del tiempo. overflow es VISIBLE: con grano mensual el nombre es el ano y\n * mide mas que sus 6,5px de columna, pero sus vecinos estan en .pr360-mute (visibility:hidden), de\n * modo que puede desbordar sobre ellos sin taparle nada a nadie. Recortandolo se leia \"2\".\n *\n * Va centrado para que el ano caiga SOBRE su columna y no a su derecha: alineado al inicio, los\n * 16px que le sobran salian todos hacia el mismo lado y el ultimo rotulo se iba de la region.\n * min-height y line-height fijan el alto del hueco, que asi no depende de que dentro haya texto:\n * los huecos van vacios y el eje sigue recto.\n */\n.uik-etdemo_product360 .pr360-ch-name {\n  position: relative;\n  display: block;\n  overflow: visible;\n  padding: 4px 0 2px;\n  border-top: 1px solid var(--uik-line);\n  font-size: 10px;\n  line-height: 12px;\n  min-height: 12px;\n  white-space: nowrap;\n  text-align: center;\n  color: var(--uik-ink-soft);\n  font-variant-numeric: tabular-nums;\n}\n\n.uik-etdemo_product360 .pr360-ch-hit.on .pr360-ch-name {\n  border-top-color: var(--uik-brand);\n  box-shadow: inset 0 2px 0 var(--uik-brand);\n  font-weight: 700;\n  color: var(--uik-ink);\n}\n\n/* Los rotulos de las dos series y del nivel, con su muestra delante. */\n.uik-etdemo_product360 .pr360-legend {\n  display: flex;\n  flex-wrap: wrap;\n  align-items: center;\n  gap: var(--pr360-gap-sm) var(--pr360-gap);\n  margin: 0;\n  font-size: 11px;\n  color: var(--uik-ink-soft);\n}\n\n.uik-etdemo_product360 .pr360-key {\n  display: inline-flex;\n  align-items: center;\n  gap: 6px;\n}\n\n.uik-etdemo_product360 .pr360-key::before {\n  content: \"\";\n  width: 10px;\n  height: 10px;\n  border-radius: 2px;\n  background: currentColor;\n}\n\n/* El nivel es una linea, no un area: su muestra tambien. */\n.uik-etdemo_product360 .pr360-key-level {\n  color: var(--uik-brand);\n}\n\n.uik-etdemo_product360 .pr360-key-level::before {\n  height: 2px;\n  width: 14px;\n  border-radius: 1px;\n}\n\n.uik-etdemo_product360 .pr360-key-in {\n  color: var(--uik-brand);\n}\n\n.uik-etdemo_product360 .pr360-key-out {\n  color: var(--uik-ink-soft);\n}\n\n/* Las cinco cifras del periodo elegido, en una linea y con el periodo primero. */\n.uik-etdemo_product360 .pr360-readout {\n  display: flex;\n  flex-wrap: wrap;\n  align-items: baseline;\n  gap: 4px var(--pr360-gap);\n  margin-top: var(--pr360-gap-sm);\n  padding-top: var(--pr360-gap-sm);\n  border-top: 1px solid var(--uik-line);\n  font-size: 12px;\n  font-variant-numeric: tabular-nums;\n  color: var(--uik-ink);\n}\n\n.uik-etdemo_product360 .pr360-readout em {\n  font-style: normal;\n  color: var(--uik-ink-soft);\n}\n\n.uik-etdemo_product360 .pr360-readout-key {\n  font-weight: 700;\n  color: var(--uik-brand);\n}\n\n/* --------------------------------------------------------- barras que eligen */\n\n/*\n * Una barra que es un eje. La geometria, el relleno tras el texto y el negativo creciendo desde\n * el borde derecho ya los resuelve .uik-bar del kit; lo unico que se anade es lo que hace falta\n * para que un boton no se vea como un boton del navegador, y la marca del elegido.\n */\n.uik-etdemo_product360 .pr360-barpicks {\n  margin-top: var(--pr360-gap-sm);\n}\n\n.uik-etdemo_product360 .pr360-barpick {\n  width: 100%;\n  border: 0;\n  font: inherit;\n  text-align: left;\n  cursor: pointer;\n  /* El relleno del kit es currentColor: aqui es tinte de marca, el mismo que .pr360-spark. */\n  color: var(--uik-brand);\n}\n\n/*\n * En reposo eran identicas a las barras de lectura de los paneles vecinos -- misma caja, mismo\n * gris, misma cifra -- y todo el afford estaba en el hover: nada decia que unas mueven la ventana\n * entera y otras no. Se leen ahora como .pr360-link: rotulo en marca y peso 600, con la cifra en\n * tinta. La marca aqui es color de interaccion, no de dato: no afirma nada que el dato no lleve.\n */\n.uik-etdemo_product360 .pr360-barpick .uik-bar-label {\n  color: var(--uik-brand);\n  font-weight: 600;\n}\n\n.uik-etdemo_product360 .pr360-barpick .uik-bar-value {\n  color: var(--uik-ink);\n}\n\n.uik-etdemo_product360 .pr360-barpick:hover {\n  background: var(--uik-ground);\n  box-shadow: inset 0 0 0 1px var(--uik-brand);\n}\n\n.uik-etdemo_product360 .pr360-barpick:hover .uik-bar-label {\n  text-decoration: underline;\n}\n\n.uik-etdemo_product360 .pr360-barpick.on {\n  background: var(--uik-ground);\n  box-shadow: inset 0 0 0 2px var(--uik-brand);\n}\n\n.uik-etdemo_product360 .pr360-barpick.on .uik-bar-label {\n  font-weight: 700;\n}\n\n/* Un almacen sin nada sigue siendo filtro, pero baja la voz: sigue estando, deja de reclamar. */\n.uik-etdemo_product360 .pr360-barpick[data-zero] .uik-bar-label,\n.uik-etdemo_product360 .pr360-barpick[data-zero] .uik-bar-value {\n  color: var(--uik-ink-soft);\n  font-weight: 400;\n}\n\n/* El puesto del producto entre los de su categoria. */\n.uik-etdemo_product360 .pr360-rank {\n  margin: 0;\n  font-size: 12px;\n  color: var(--uik-ink-soft);\n}\n\n.uik-etdemo_product360 .pr360-rank b {\n  font-size: 15px;\n  color: var(--uik-ink);\n  font-variant-numeric: tabular-nums;\n}\n\n/* La celda que lleva su barra: la barra debajo de la cifra, no detras. */\n.uik-etdemo_product360 .pr360-table td.pr360-cell-bar .pr360-spark {\n  margin-bottom: 3px;\n}\n\n/*\n * Un sitio vaciado se queda -- es donde estuvo, y en esta base son 163 de 255 filas -- pero baja\n * la voz y no pinta pista de barra. visibility y no display: la fila conserva su alto y las cifras\n * de las filas con stock siguen alineadas.\n */\n.uik-etdemo_product360 .pr360-row-empty td {\n  color: var(--uik-ink-soft);\n}\n\n.uik-etdemo_product360 .pr360-row-empty .pr360-cell-key {\n  font-weight: 400;\n}\n\n.uik-etdemo_product360 .pr360-row-empty .pr360-spark {\n  visibility: hidden;\n}\n\n/* --------------------------------------------------- la mezcla por tipo */\n\n/*\n * Dos longitudes desde un cero comun: lo que salio a la izquierda del eje, lo que entro a la\n * derecha, y una sola escala para todas las filas. Es la convencion del panel de flujo del libro\n * -- entrada y salida a lados opuestos de un eje, marca contra tinta suave, sin verde ni rojo --\n * y sustituye a una barra unica con el neto, que con un rango entre tipos de 7.350.270x dejaba\n * dos filas indistinguibles al 95% y una tercera sin dibujar nada.\n */\n.uik-etdemo_product360 .pr360-mix {\n  display: flex;\n  flex-direction: column;\n  gap: 3px;\n  margin-top: var(--pr360-gap-sm);\n}\n\n.uik-etdemo_product360 .pr360-mix-row {\n  display: grid;\n  grid-template-columns: minmax(0, 1fr) minmax(0, auto);\n  gap: 4px 10px;\n  padding: 6px 8px;\n  border-radius: var(--pr360-radius-sm);\n  background: var(--uik-surface);\n  box-shadow: inset 0 0 0 1px var(--uik-line);\n}\n\n.uik-etdemo_product360 .pr360-mix-label {\n  min-width: 0;\n  color: var(--uik-ink);\n}\n\n.uik-etdemo_product360 .pr360-mix-label em,\n.uik-etdemo_product360 .pr360-mix-net em {\n  display: block;\n  font-style: normal;\n  font-size: 11px;\n  font-weight: 400;\n  color: var(--uik-ink-soft);\n}\n\n.uik-etdemo_product360 .pr360-mix-net {\n  text-align: right;\n  font-weight: 600;\n  font-variant-numeric: tabular-nums;\n  color: var(--uik-ink);\n}\n\n.uik-etdemo_product360 .pr360-mix-track {\n  position: relative;\n  grid-column: 1 / -1;\n  height: 10px;\n  border-radius: 2px;\n  background: var(--uik-ground);\n}\n\n/* El eje: el cero comun de las dos series. */\n.uik-etdemo_product360 .pr360-mix-track::after {\n  content: \"\";\n  position: absolute;\n  top: -2px;\n  bottom: -2px;\n  left: 50%;\n  width: 1px;\n  background: var(--uik-ink-soft);\n}\n\n/*\n * Cada lado ocupa media pista, y lleva el mismo piso que las barras del kit: min(v*1e5, 3px) vale\n * cero exacto cuando el lado es 0% y 3px en cuanto hay dato, asi que un tipo sin salidas no pinta\n * nada por la izquierda y uno con 5.000 sobre 5.816.500 si pinta algo.\n */\n.uik-etdemo_product360 .pr360-mix-out,\n.uik-etdemo_product360 .pr360-mix-in {\n  position: absolute;\n  top: 0;\n  bottom: 0;\n  border-radius: 2px;\n  opacity: 0.55;\n}\n\n.uik-etdemo_product360 .pr360-mix-out {\n  right: 50%;\n  width: calc(max(var(--pr360-out, 0%), min(calc(var(--pr360-out, 0%) * 100000), 3px)) / 2);\n  background: var(--uik-ink-soft);\n}\n\n.uik-etdemo_product360 .pr360-mix-in {\n  left: 50%;\n  width: calc(max(var(--pr360-in, 0%), min(calc(var(--pr360-in, 0%) * 100000), 3px)) / 2);\n  background: var(--uik-brand);\n}\n\n/* La direccion de una cantidad con signo en el rastro. Sin verde ni rojo: no es un juicio. */\n.uik-etdemo_product360 .pr360-in {\n  color: var(--uik-ink);\n}\n\n.uik-etdemo_product360 .pr360-out {\n  color: var(--uik-ink-soft);\n}\n");

/* AD_MESSAGE */
OB.UIKit.labels({"ETDEMO_AlertsAck":"Revisar","ETDEMO_AlertsAcked":"Revisada","ETDEMO_AlertsAckFailed":"No se pudo revisar la alerta; se ha restaurado el estado anterior.","ETDEMO_AlertsACKNOWLEDGED":"Revisadas","ETDEMO_AlertsAll":"Todas","ETDEMO_AlertsBadTransition":"Solo se puede revisar una alerta nueva. Estado actual:","ETDEMO_AlertsColAction":"Acción","ETDEMO_AlertsColAlert":"Alerta","ETDEMO_AlertsColCreated":"Creada","ETDEMO_AlertsColOrg":"Organización","ETDEMO_AlertsDetailHead":"Detalle","ETDEMO_AlertsEmpty":"No hay alertas con este filtro.","ETDEMO_AlertsNEW":"Nuevas","ETDEMO_AlertsNoRules":"Este rol no tiene ninguna alerta visible.","ETDEMO_AlertsNoTab":"Sin ventana asociada","ETDEMO_AlertsNotVisible":"La alerta no existe o no es visible para este rol.","ETDEMO_AlertsOpen":"Abrir registro","ETDEMO_AlertsPause":"Pausar refresco","ETDEMO_AlertsRailNote":"Los recuentos por estado y por regla se calculan sobre todas las alertas visibles, sin mirar el filtro activo.","ETDEMO_AlertsRefreshEvery":"Refresco automático cada","ETDEMO_AlertsReloadNow":"Actualizar ahora","ETDEMO_AlertsResume":"Reanudar refresco","ETDEMO_AlertsRuleHead":"Regla","ETDEMO_AlertsSeconds":"segundos","ETDEMO_AlertsSOLVED":"Resueltas","ETDEMO_AlertsSource":"Alertas generadas por reglas del diccionario, no por la operación diaria.","ETDEMO_AlertsStatusHead":"Estado","ETDEMO_AlertsSUPPRESSED":"Silenciadas","ETDEMO_AlertsTitle":"Bandeja de alertas del administrador","ETDEMO_AlertsTotal":"Alertas visibles","ETDEMO_AlertsTruncated":"Lista recortada al límite de filas; ajusta el filtro para ver el resto.","ETDEMO_CashAging":"Antigüedad de la cartera","ETDEMO_CashAgingAria":"Antigüedad de la cartera por tramo","ETDEMO_CashAgingNote":"Los totales por tramo se calculan sobre toda la cartera del lado, sin mirar el tramo seleccionado.","ETDEMO_CashAP":"Pagos a proveedores","ETDEMO_CashAR":"Cobros de clientes","ETDEMO_CashAsOf":"Fecha de referencia","ETDEMO_CashBucketAll":"Todos los tramos","ETDEMO_CashBucketCur":"Sin vencer","ETDEMO_CashBucketD30":"1 a 30 días","ETDEMO_CashBucketD60":"31 a 60 días","ETDEMO_CashBucketD90":"61 a 90 días","ETDEMO_CashBucketD90p":"Más de 90 días","ETDEMO_CashColDays":"Días","ETDEMO_CashColDoc":"Documento","ETDEMO_CashColDocs":"Docs.","ETDEMO_CashColDue":"Vencimiento","ETDEMO_CashColInvoiced":"Fecha de factura","ETDEMO_CashColOldest":"Vencimiento más antiguo","ETDEMO_CashColOutstanding":"Pendiente","ETDEMO_CashColPartner":"Tercero","ETDEMO_CashCurrenciesWord":"monedas","ETDEMO_CashCurrency":"Moneda","ETDEMO_CashDaysOverdue":"días vencido","ETDEMO_CashDetail":"Detalle por tercero","ETDEMO_CashDocsWord":"documentos","ETDEMO_CashDueRange":"vencimientos","ETDEMO_CashEmpty":"No hay documentos pendientes con este filtro.","ETDEMO_CashEmptySide":"Esta cartera no tiene ningún documento pendiente dentro del ámbito del rol.","ETDEMO_CashExcludedNote":"documento(s) en otras monedas no se muestran","ETDEMO_CashFromData":"último vencimiento del dato","ETDEMO_CashFromParam":"indicada en la petición","ETDEMO_CashFromToday":"hoy del servidor","ETDEMO_CashNoTab":"sin ventana de factura resoluble","ETDEMO_CashNotDue":"sin vencer","ETDEMO_CashOneCurrency":"Una sola moneda a la vez: sumar monedas distintas da un número sin significado.","ETDEMO_CashPartnersWord":"terceros","ETDEMO_CashSeriesAP":"Pagos liquidados, 12 meses","ETDEMO_CashSeriesAR":"Cobros liquidados, 12 meses","ETDEMO_CashSeriesAria":"Serie mensual de caja de los últimos doce meses","ETDEMO_CashSeriesNote":"fin_payment es la única serie densa de esta instancia; los meses sin pagos se rellenan en Java.","ETDEMO_CashSideGroup":"Cartera","ETDEMO_CashTitle":"Cartera de cobros y pagos","ETDEMO_CashTotalLabel":"Total de la cartera","ETDEMO_CashWhySide":"El encargo original pedía un cuadro de cobros. En esta instancia los cobros están muertos y los pagos vivos, así que la pantalla abre en pagos y lo dice en vez de esconderlo: el conmutador cambia de lado en un clic.","ETDEMO_P360Amount":"Importe","ETDEMO_P360Count":"Nº","ETDEMO_P360Customer":"Cliente","ETDEMO_P360Date":"Fecha","ETDEMO_P360Directory":"Directorio","ETDEMO_P360DirEmpty":"Ningún tercero coincide con la búsqueda.","ETDEMO_P360DocNo":"Nº documento","ETDEMO_P360Docs":"documentos","ETDEMO_P360DocsEmpty":"Este tercero no tiene documentos de este tipo.","ETDEMO_P360Documents":"Documentos","ETDEMO_P360Last":"Último","ETDEMO_P360LazyNote":"El directorio se carga una vez; la ficha y la lista de documentos solo cuando hacen falta.","ETDEMO_P360Mixed":"varias monedas","ETDEMO_P360Next":"Siguiente","ETDEMO_P360Of":"de","ETDEMO_P360OpenDoc":"Abrir el documento","ETDEMO_P360OpenPartner":"Abrir la ficha del tercero","ETDEMO_P360Page":"Página","ETDEMO_P360Partner":"Tercero","ETDEMO_P360Partners":"terceros","ETDEMO_P360Pick":"Elige un tercero del directorio para ver su ficha.","ETDEMO_P360Prev":"Anterior","ETDEMO_P360ScopeNote":"Solo documentos de las organizaciones que tu rol puede leer.","ETDEMO_P360Search":"Buscar tercero","ETDEMO_P360Status":"Estado","ETDEMO_P360Summary":"Resumen","ETDEMO_P360TabPI":"Facturas de compra","ETDEMO_P360TabPM":"Pagos","ETDEMO_P360TabPO":"Pedidos de compra","ETDEMO_P360TabRC":"Cobros","ETDEMO_P360Tabs":"Tipos de documento","ETDEMO_P360TabSI":"Facturas de venta","ETDEMO_P360TabSO":"Pedidos de venta","ETDEMO_P360TaxId":"NIF","ETDEMO_P360Title":"Tercero 360","ETDEMO_P360Total":"Total","ETDEMO_P360TotalsNote":"Los totales por pestaña se calculan sobre todos los documentos del tercero, sin mirar la pestaña activa.","ETDEMO_P360Vendor":"Proveedor","ETDEMO_PickingActCO":"Confirmar","ETDEMO_PickingActRE":"Reabrir","ETDEMO_PickingAfter":"Después","ETDEMO_PickingAll":"Todos","ETDEMO_PickingApplied":"Aplicado","ETDEMO_PickingArm":"Armar ejecución real","ETDEMO_PickingArmed":"Armado: el siguiente clic modifica el pedido en el ERP","ETDEMO_PickingAsk":"Vas a modificar este pedido en el ERP. ¿Continuar?","ETDEMO_PickingAsOf":"Datos a fecha","ETDEMO_PickingBadAction":"Esta ventana no ejecuta la acción pedida por el navegador:","ETDEMO_PickingBadTransition":"Esta ventana solo confirma borradores y reabre completados. Estado actual:","ETDEMO_PickingBefore":"Antes","ETDEMO_PickingChoose":"Elige un pedido de la lista para ver sus líneas","ETDEMO_PickingCL":"Cerrado","ETDEMO_PickingCO":"Completado","ETDEMO_PickingCoreAllows":"El ERP admite ahora","ETDEMO_PickingCustomer":"Cliente","ETDEMO_PickingDate":"Fecha","ETDEMO_PickingDelivered":"Entregada","ETDEMO_PickingDisarm":"Desarmar","ETDEMO_PickingDR":"Borrador","ETDEMO_PickingDry":"Simular","ETDEMO_PickingDryDone":"Simulación completada: no se ha modificado nada","ETDEMO_PickingDryHint":"La simulación no modifica nada","ETDEMO_PickingErpError":"El ERP ha rechazado la acción.","ETDEMO_PickingErpSaid":"El ERP responde","ETDEMO_PickingGo":"Ejecutar de verdad","ETDEMO_PickingGone":"Ese pedido ya no está visible para tu rol","ETDEMO_PickingIdle":"Todavía no has intentado nada en esta sesión","ETDEMO_PickingIntro":"Pedidos de venta listos para confirmar. Simula antes de ejecutar.","ETDEMO_PickingLine":"Línea","ETDEMO_PickingLines":"Líneas del pedido","ETDEMO_PickingMatched":"coincidencias","ETDEMO_PickingNext":"Siguientes","ETDEMO_PickingNoAction":"Este estado no admite ninguna acción en esta ventana","ETDEMO_PickingNoLines":"Este pedido no tiene líneas","ETDEMO_PickingNoOrders":"Ningún pedido coincide con el filtro","ETDEMO_PickingNotVisible":"Ese pedido no existe o no es visible para tu rol.","ETDEMO_PickingOnHand":"En almacén","ETDEMO_PickingOpenOrder":"Abrir el pedido en su ventana","ETDEMO_PickingOrdered":"Pedida","ETDEMO_PickingOrders":"Pedidos","ETDEMO_PickingPending":"Pendiente","ETDEMO_PickingPrev":"Anteriores","ETDEMO_PickingProduct":"Producto","ETDEMO_PickingRejected":"Rechazado","ETDEMO_PickingResult":"Último intento","ETDEMO_PickingSearch":"Número de pedido o cliente","ETDEMO_PickingSending":"Enviando...","ETDEMO_PickingServices":"de servicio","ETDEMO_PickingSimulated":"Simulado","ETDEMO_PickingStatus":"Estado","ETDEMO_PickingStocked":"líneas de almacén","ETDEMO_PickingTitle":"Preparación de pedidos","ETDEMO_PickingToneDone":"Nada pendiente","ETDEMO_PickingToneNa":"Servicio","ETDEMO_PickingToneOk":"Cubierta","ETDEMO_PickingTonePartial":"Parcial","ETDEMO_PickingToneShort":"Sin stock","ETDEMO_PickingTotal":"Total","ETDEMO_PickingUnchanged":"Sin cambios","ETDEMO_PickingVO":"Anulado","ETDEMO_PickingWarehouse":"Almacén","ETDEMO_PickingWouldRun":"Se ejecutaría la acción","ETDEMO_PR360AllCategories":"All categories","ETDEMO_PR360AllWarehouses":"All warehouses","ETDEMO_PR360AsOf":"Stock as of","ETDEMO_PR360AsOfToday":"no movement recorded, so today is shown","ETDEMO_PR360Balance":"Balance","ETDEMO_PR360Brand":"UIKit demo","ETDEMO_PR360CategoryLabel":"Category","ETDEMO_PR360ColAttribute":"Lot / serial","ETDEMO_PR360ColAvailable":"Available","ETDEMO_PR360ColCurrency":"Currency","ETDEMO_PR360ColDate":"Date","ETDEMO_PR360ColDocumentNo":"Document no.","ETDEMO_PR360ColLines":"Lines","ETDEMO_PR360ColLocator":"Locator","ETDEMO_PR360ColMovementType":"Type","ETDEMO_PR360ColOnhand":"On hand","ETDEMO_PR360ColPlace":"Locator / warehouse","ETDEMO_PR360ColQty":"Quantity","ETDEMO_PR360ColReserved":"Reserved","ETDEMO_PR360ColSpan":"Received between","ETDEMO_PR360ColUnitCost":"Cost per unit","ETDEMO_PR360ColWarehouse":"Warehouse","ETDEMO_PR360Desc":"One product and every dimension of its stock: warehouse, locator, lot, category, movement type and time.","ETDEMO_PR360DirPurchase":"Purchase","ETDEMO_PR360DirSales":"Sales","ETDEMO_PR360DocInventory":"Physical inventory","ETDEMO_PR360DocMovement":"Goods movement","ETDEMO_PR360DocReceipt":"Goods receipt","ETDEMO_PR360DocShipment":"Goods shipment","ETDEMO_PR360FlowLineOne":"1 line","ETDEMO_PR360FlowLines":"lines","ETDEMO_PR360FlowOf":"of","ETDEMO_PR360GoneBody":"It may have been deactivated, or it sits outside the clients and organizations your role can read. Pick another product from the list.","ETDEMO_PR360GoneTitle":"This product is no longer readable","ETDEMO_PR360GrainMonth":"By month","ETDEMO_PR360GrainYear":"By year","ETDEMO_PR360In":"In","ETDEMO_PR360InUseWord":"in use","ETDEMO_PR360LastInventory":"Last counted","ETDEMO_PR360LastInventoryHint":"Most recent physical inventory date across the locators that hold this product.","ETDEMO_PR360Ledger":"Movement ledger","ETDEMO_PR360LedgerNote":"Every movement of this product, from the first to the last: there is no date filter, and the grain only decides how the periods are cut. The balance accumulates the signed transactions in date order, so its last value is the quantity on hand in the header. Bars are quantity moved during a period and the balance is the quantity held after it, which is two scales and therefore two panels.","ETDEMO_PR360LocatorNote":"Only the first locators are listed. Narrow by warehouse to read the rest.","ETDEMO_PR360Locators":"Locators","ETDEMO_PR360LotNote":"Lot and serial as recorded on the stock rows. No shelf life is shown: this instance records no guarantee date on any attribute set instance, so a remaining-life column would be a column of blanks.","ETDEMO_PR360Lots":"Lots and serials","ETDEMO_PR360Mix":"Movement mix","ETDEMO_PR360MixNote":"Each movement type on one shared scale: what went out grows to the left of the axis, what came in grows to the right, and the figure is the net that type contributed to the balance.","ETDEMO_PR360MoveOne":"1 movement","ETDEMO_PR360Moves":"movements","ETDEMO_PR360Net":"Net","ETDEMO_PR360Next":"Next","ETDEMO_PR360NoAttribute":"No lot or serial","ETDEMO_PR360NoDate":"no date recorded","ETDEMO_PR360NoLotsBody":"No lot or serial: every stock row of this product is recorded without an attribute set instance.","ETDEMO_PR360NoMoves":"No movement recorded for this product","ETDEMO_PR360NoPickBody":"Choose a product from the list to read its stock across every dimension.","ETDEMO_PR360NoPickTitle":"Pick a product","ETDEMO_PR360NoRowsBody":"Try a shorter search, or clear the filters.","ETDEMO_PR360NoRowsTitle":"No stock rows match","ETDEMO_PR360NotStocked":"Not stocked","ETDEMO_PR360NoWorth":"No cost recorded on the incoming movements of this product.","ETDEMO_PR360OpenProduct":"Open in Product window","ETDEMO_PR360Out":"Out","ETDEMO_PR360PageOf":"Page","ETDEMO_PR360PagerLabel":"Pages","ETDEMO_PR360PageSizeLabel":"Rows per page","ETDEMO_PR360Peers":"Category peers","ETDEMO_PR360PeersNote":"The products of the same category by quantity on hand. Choosing one moves the whole window to that product. Quantities may be in different units and are not added.","ETDEMO_PR360Pending":"Ordered and not delivered","ETDEMO_PR360PendingNote":"Open order lines by order year, never added to stock. The oldest open line in this instance is from 2011, so this is a portfolio of lines nobody closed and not goods in transit.","ETDEMO_PR360PeriodOne":"1 period","ETDEMO_PR360Periods":"periods","ETDEMO_PR360PickPeriod":"Pick a period to read its figures.","ETDEMO_PR360PlaceOne":"1 place","ETDEMO_PR360PlacesWord":"places","ETDEMO_PR360Prev":"Previous","ETDEMO_PR360ProductOne":"1 product","ETDEMO_PR360Products":"products","ETDEMO_PR360Rail":"Products","ETDEMO_PR360RailNote":"The bar compares quantities within this page only, not across the whole catalogue.","ETDEMO_PR360Rank":"Rank","ETDEMO_PR360SearchHint":"Search key or product name","ETDEMO_PR360SearchLabel":"Search","ETDEMO_PR360SortCategory":"Category","ETDEMO_PR360SortCode":"Search key","ETDEMO_PR360SortLabel":"Sort by","ETDEMO_PR360SortMoves":"Movements","ETDEMO_PR360SortName":"Product","ETDEMO_PR360SortOnhand":"On hand","ETDEMO_PR360SortRecent":"Most recent movement","ETDEMO_PR360Split":"Reserved share of the quantity on hand","ETDEMO_PR360StateLoading":"Loading","ETDEMO_PR360Stocked":"Stocked","ETDEMO_PR360TileLocators":"Locators in use","ETDEMO_PR360TileLots":"Lots and serials","ETDEMO_PR360TileLotsHint":"Distinct lots or serials holding stock of this product.","ETDEMO_PR360TileStockRows":"Stock rows","ETDEMO_PR360TileStockRowsHint":"One row is one product in one locator.","ETDEMO_PR360TileWarehouses":"Warehouses","ETDEMO_PR360Title":"Product 360","ETDEMO_PR360Trail":"Movement trail","ETDEMO_PR360TrailPager":"Movement trail pages","ETDEMO_PR360WarehouseLabel":"Warehouse","ETDEMO_PR360WarehouseNote":"This panel is the warehouse filter and not a filtered panel: it always shows the full split, and choosing a warehouse re-reads every other panel and the ledger under it.","ETDEMO_PR360Warehouses":"Warehouses","ETDEMO_PR360Worth":"Cost per unit as received","ETDEMO_PR360WorthNote":"Average cost per unit recorded on the incoming movements, by currency, with the number of lines behind it. It is not multiplied by the quantity on hand: valuing stock is the job of the Etendo costing engine.","ETDEMO_StockAxisNote":"El eje de almacenes ignora la búsqueda y la paginación.","ETDEMO_StockColTotals":"Total por almacén","ETDEMO_StockEmpty":"Ningún producto coincide con la búsqueda.","ETDEMO_StockGrand":"Total general","ETDEMO_StockNext":"Siguiente","ETDEMO_StockOf":"de","ETDEMO_StockOpenProduct":"Abrir la ficha del producto","ETDEMO_StockPage":"Página","ETDEMO_StockPageSize":"por página","ETDEMO_StockPrev":"Anterior","ETDEMO_StockProduct":"Producto","ETDEMO_StockProducts":"productos","ETDEMO_StockScopeNote":"Los totales por almacén cubren todo el conjunto filtrado, no solo la página visible.","ETDEMO_StockSearch":"Buscar por código o nombre de producto","ETDEMO_StockSort":"Ordenar por","ETDEMO_StockSortCode":"código","ETDEMO_StockSortName":"nombre","ETDEMO_StockSortQty":"cantidad","ETDEMO_StockTitle":"Stock por producto y almacén","ETDEMO_StockTotal":"Total","ETDEMO_StockUom":"UdM","ETDEMO_StockWarehouses":"almacenes","ETDEMO_StockZeros":"Incluir total cero","ETUIK_LoadFailed":"No se pudieron cargar los datos","ETUIK_Loading":"Cargando…","ETUIK_MeterAria":"Puntuación %{score} sobre un objetivo de %{target}","ETUIK_RailAria":"Avance %{progress}%, esperado %{expected}%"});

/* com.etendoerp.uikit.samples/web/com.etendoerp.uikit.samples/js/product-360.js */
/*
 * ETDEMO_Product360 -- un producto, todas las dimensiones de su stock.
 *
 * Las tres propuestas anteriores responden "que hay en el almacen". Esta responde la otra
 * pregunta, la que se hace delante de una estanteria: "que pasa con ESTE producto". Un solo
 * producto en el centro y a su alrededor todos los ejes que la base de datos sabe cruzar --
 * sitio, almacen, lote, categoria, tipo de movimiento y tiempo -- cada uno dibujado, y cada
 * dibujo pulsable.
 *
 * Tres lecturas y no una, porque son tres granos distintos y mezclarlos en un solo datasource
 * obligaria a repetir la mas caras cada vez que cambia la mas barata:
 *
 *   ProductIndex    un renglon por producto: el carril desde el que se elige
 *   ProductStock    ocho paneles sobre el producto elegido, todos al mismo instante
 *   ProductLedger   el movimiento: la serie por periodo, la mezcla por tipo y el rastro
 *
 * El eje del almacen es el que hace que esto sea 360 y no una ficha: el panel de almacenes NO
 * esta filtrado por almacen -- es el filtro -- asi que pulsar un almacen no oculta nada, vuelve
 * a leer los otros siete paneles y el libro entero bajo ese almacen, y el propio panel sigue
 * mostrando el reparto completo para poder salir.
 *
 * Tres cosas que esta ventana deliberadamente NO dice, y estan medidas, no supuestas:
 *
 * 1. Caducidad. `guaranteedate` esta nula en las 218 instancias de atributo de esta instancia,
 *    asi que un panel de vida util seria una columna de blancos con aire de dato.
 * 2. Valor de inventario. El panel de coste publica el coste medio por unidad recibido tal como
 *    lo grabaron los movimientos de entrada, con su moneda y su numero de lineas, y no lo
 *    multiplica por la cantidad de hoy: valorar existencias es trabajo del motor de costes de
 *    Etendo y una multiplicacion en una vista no lo sustituye.
 * 3. Stock en transito. Lo pedido y no entregado se presenta fechado por ano de pedido y nunca
 *    sumado al stock: la linea mas vieja es de 2011 y la mas nueva de 2021 contra 135.665 en
 *    mano, asi que es una cartera de lineas abiertas y no mercancia en camino.
 *
 * Y una que si dice, que es la espina dorsal: `m_transaction` viene con signo, y acumular las
 * transacciones de un producto en orden de fecha aterriza exactamente en la cantidad en mano.
 * Por eso el libro no lleva filtro de fechas -- va del primer movimiento al ultimo -- y el
 * grano solo decide como se cortan los periodos, nunca cuales entran. El saldo que cierra el
 * grafico y la cifra de la cabecera son el mismo numero, y eso se puede comprobar mirando.
 *
 * Nada se filtra, ordena ni pagina en el navegador: cada panel es un datasource con alcance y
 * la busqueda, el orden y la ventana son SQL.
 */
(function () {
  'use strict';

  var K = OB.UIKit;
  var html = K.html;

  K.datasource('ETDEMO_PR360Index', {
    action: 'com.etendoerp.uikit.samples.product360.ProductIndex'
  });
  K.datasource('ETDEMO_PR360Stock', {
    action: 'com.etendoerp.uikit.samples.product360.ProductStock'
  });
  K.datasource('ETDEMO_PR360Ledger', {
    action: 'com.etendoerp.uikit.samples.product360.ProductLedger'
  });

  /* ------------------------------------------------------------------ errores */

  /*
   * A datasource that failed reports through the runtime, not through the payload.
   *
   * The three sources answer OB.UIKit's error envelope -- {error: {message}} -- and the runtime
   * turns that into ui.errors[alias] and keeps the last good data on screen. So a region asks the
   * runtime whether its own source is broken and prints one translated line; the server's message
   * is never rendered, because it was written for the log and not for the reader.
   */
  function broke(ui, alias) {
    return !!(ui && ui.errors && ui.errors[alias]);
  }

  function failed(ui, alias) {
    return broke(ui, alias)
      ? html`<p class="uik-error">${K.t('ETUIK_LoadFailed')}</p>`
      : null;
  }

  /* Trailing edge, so the request goes out when typing stops rather than once per letter. */
  var SEARCH_MS = 300;

  /*
   * Dos ejes de orden que las otras ventanas no tienen, y son los que hacen util el carril: por
   * numero de movimientos (que producto se mueve) y por fecha del ultimo (que producto dejo de
   * moverse). El servidor tiene el mismo whitelist; esto solo evita mandar una clave que alli
   * se sustituiria en silencio.
   */
  var SORT_IDS = ['code', 'name', 'category', 'onhand', 'moves', 'recent'];
  var SORTS = [
    { id: 'onhand', label: 'ETDEMO_PR360SortOnhand' },
    { id: 'code', label: 'ETDEMO_PR360SortCode' },
    { id: 'name', label: 'ETDEMO_PR360SortName' },
    { id: 'category', label: 'ETDEMO_PR360SortCategory' },
    { id: 'moves', label: 'ETDEMO_PR360SortMoves' },
    { id: 'recent', label: 'ETDEMO_PR360SortRecent' }
  ];
  var SORT_DEFAULT = 'onhand';

  /* El grano no decide que periodos entran, solo por donde se cortan. */
  var GRAIN_IDS = ['year', 'month'];
  var GRAINS = [
    { id: 'year', label: 'ETDEMO_PR360GrainYear' },
    { id: 'month', label: 'ETDEMO_PR360GrainMonth' }
  ];
  var GRAIN_DEFAULT = 'year';

  var LIMITS = [10, 25, 50];
  var LIMIT_DEFAULT = 25;
  /*
   * Diez movimientos por pagina y no veinte. Con veinte el rastro medía 1.103px: nunca caben su
   * cabecera y su pager en la misma pantalla, y acotarlo con scroll propio seria el tercer
   * scroller anidado de la ventana -- y obligaria a meterlo en keepScroll, que conserva el
   * scrollTop en CADA repintado y dejaria la pagina siguiente abierta por el final.
   */
  var TRAIL_LIMIT = 10;
  var PAGE_MAX = 1000000;

  /*
   * One debounced setter per open view, keyed on the state object -- which the runtime creates once
   * per instance and never replaces. A single module-level debounce would be shared by two tabs of
   * the same window, and the second typist would cancel the first one's pending search.
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

  /* ------------------------------------------------------ normalizacion del bookmark */

  function intOf(value) {
    if (typeof value === 'number' && isFinite(value)) {
      return Math.floor(value);
    }
    if (typeof value === 'string' && /^-?[0-9]+$/.test(value.trim())) {
      return parseInt(value.trim(), 10);
    }
    return null;
  }

  function textOf(value) {
    if (typeof value === 'string') {
      return value;
    }
    if (typeof value === 'number' && isFinite(value)) {
      return String(value);
    }
    return '';
  }

  /** A number the server sent, or null: absence is not zero and must not be drawn as zero. */
  function numOf(value) {
    if (typeof value === 'number' && isFinite(value)) {
      return value;
    }
    if (typeof value === 'string' && value.trim() !== '' && isFinite(Number(value))) {
      return Number(value);
    }
    return null;
  }

  function pageOf(value) {
    var n = intOf(value);
    return n !== null && n >= 1 && n <= PAGE_MAX ? n : 1;
  }

  function limitOf(state) {
    var n = intOf(state ? state.limit : null);
    return n !== null && LIMITS.indexOf(n) !== -1 ? n : LIMIT_DEFAULT;
  }

  function sortOf(state) {
    var raw = state ? state.sort : null;
    return typeof raw === 'string' && SORT_IDS.indexOf(raw) !== -1 ? raw : SORT_DEFAULT;
  }

  function grainOf(state) {
    var raw = state ? state.grain : null;
    return typeof raw === 'string' && GRAIN_IDS.indexOf(raw) !== -1 ? raw : GRAIN_DEFAULT;
  }

  /* ------------------------------------------------------------------ formato */

  /*
   * Un contador con su palabra. Las claves llevan prefijo Flow por donde nacieron, no por donde
   * valen: el texto es generico y duplicarlas solo para renombrarlas dejaria dos filas del
   * diccionario diciendo lo mismo.
   */
  function count(value, oneKey, manyKey) {
    return intOf(value) === 1
      ? K.t(oneKey)
      : K.fmt(value, 'int') + ' ' + K.t(manyKey);
  }

  /** A quantity reads with its own unit; two rows in different units are never added. */
  function qty(value, unit) {
    if (value === null || value === undefined) {
      return html`<span class="pr360-dash">-</span>`;
    }
    return html`${K.fmt(value, 'qty')} <span class="pr360-uom">${unit}</span>`;
  }

  function dash(value, kind) {
    if (value === null || value === undefined) {
      return html`<span class="pr360-dash">-</span>`;
    }
    return html`${K.fmt(value, kind || 'qty')}`;
  }

  function dateText(value) {
    return value ? K.fmt(value, 'date') : K.t('ETDEMO_PR360NoDate');
  }

  /** The share of a whole, or null when there is no whole to take a share of. */
  function share(part, whole) {
    var p = numOf(part);
    var w = numOf(whole);
    if (p === null || w === null || w <= 0) {
      return null;
    }
    return Math.max(0, Math.min(100, (p / w) * 100));
  }

  /* ------------------------------------------------------------------ grafico */

  /*
   * El libro dibujado, en dos paneles que comparten el eje del tiempo.
   *
   * Arriba el NIVEL: el saldo acumulado, en escalones y no en pendiente, porque un saldo se
   * mantiene durante el periodo y no interpola entre dos puntos. Abajo el FLUJO: entradas hacia
   * arriba y salidas hacia abajo de una linea de cero. Son dos escalas distintas y por eso son
   * dos paneles distintos: una sola caja con el saldo y el flujo en el mismo eje pondria a la
   * misma altura una cantidad y una variacion, que es la manera clasica de hacer que un grafico
   * afirme algo que el dato no dice.
   *
   * El SVG no lleva ni una letra: se estira a lo ancho de su panel con preserveAspectRatio="none"
   * -- que a un texto lo deformaria -- y el eje del tiempo lo rotulan los botones de debajo, que
   * son HTML de verdad. Asi el dibujo es decorativo (aria-hidden), la serie se recorre con el
   * tabulador, cada periodo tiene su etiqueta accesible completa y no hay ni un foreignObject ni
   * un manejador colgado de un nodo que no puede recibir el foco.
   */
  var CH_W = 760;
  var CH_LEVEL_TOP = 10;
  var CH_LEVEL_H = 86;
  var CH_FLOW_TOP = 112;
  var CH_FLOW_H = 78;
  var CH_H = 190;
  var CH_PAD = 6;

  /*
   * Que periodos llevan rotulo visible. Con grano anual, todos. Con grano mensual hay 115
   * columnas de 6,5px en un panel de 784, asi que se rotula el PRIMER mes presente de cada ano
   * civil y el rotulo es el ano: once rotulos a doce columnas de distancia en vez de un
   * "YYYY-MM" cada diez columnas recortado a "2".
   *
   * "El primero presente" y no "el que acaba en -01" a proposito: la serie no rellena los meses
   * sin movimiento -- ProductLedger agrupa por to_char sobre m_transaction y no genera periodos
   * vacios -- asi que exigir enero dejaria sin nombre a los anos que empiezan a moverse en marzo.
   */
  function tickLabels(rows) {
    var seen = {};
    return rows.map(function (r) {
      var period = textOf(r.period);
      if (period.length <= 4) {
        return period;
      }
      var year = period.slice(0, 4);
      if (seen[year]) {
        return '';
      }
      seen[year] = 1;
      return year;
    });
  }

  /*
   * Los extremos de la serie, calculados en un solo sitio: los usa el dibujo para escalar y la
   * escala para rotular. Calcularlos dos veces seria la manera de que la cifra escrita no fuese
   * la altura dibujada.
   */
  function chartExtent(rows) {
    var loBal = 0;
    var hiBal = 0;
    var flow = 0;
    rows.forEach(function (r) {
      var b = numOf(r.balance) || 0;
      loBal = Math.min(loBal, b);
      hiBal = Math.max(hiBal, b);
      flow = Math.max(flow, Math.abs(numOf(r.qtyIn) || 0), Math.abs(numOf(r.qtyOut) || 0));
    });
    if (hiBal === loBal) {
      hiBal = loBal + 1;
    }
    return { loBal: loBal, hiBal: hiBal, flow: flow };
  }

  function scale(value, lo, hi, top, height) {
    var span = hi - lo;
    if (span <= 0) {
      return top + height;
    }
    return top + height - ((value - lo) / span) * height;
  }

  function ledgerChart(rows, selected) {
    var n = rows.length;
    var slot = (CH_W - CH_PAD * 2) / n;
    var ext = chartExtent(rows);
    var loBal = ext.loBal;
    var hiBal = ext.hiBal;
    var flow = ext.flow;
    var zeroLevel = scale(0, loBal, hiBal, CH_LEVEL_TOP, CH_LEVEL_H);
    var zeroFlow = CH_FLOW_TOP + CH_FLOW_H / 2;
    var half = CH_FLOW_H / 2;

    var steps = '';
    rows.forEach(function (r, i) {
      var x0 = CH_PAD + slot * i;
      var y = scale(numOf(r.balance) || 0, loBal, hiBal, CH_LEVEL_TOP, CH_LEVEL_H);
      steps += (i === 0 ? 'M' : 'L') + x0.toFixed(1) + ' ' + y.toFixed(1)
        + 'L' + (x0 + slot).toFixed(1) + ' ' + y.toFixed(1);
    });
    var area = steps + 'L' + (CH_PAD + slot * n).toFixed(1) + ' ' + zeroLevel.toFixed(1)
      + 'L' + CH_PAD.toFixed(1) + ' ' + zeroLevel.toFixed(1) + 'Z';

    var body = '';
    rows.forEach(function (r, i) {
      var x0 = CH_PAD + slot * i;
      /*
       * La barra se lleva casi todo su hueco y va centrada en el. Entrada y salida no se estorban
       * -- cada una crece por su lado del eje del flujo -- asi que partir el hueco en dos mitades
       * solo servia para que con grano mensual las dos fueran astillas de 2px.
       */
      var wBar = Math.max(1, slot * 0.7);
      var xBar = x0 + slot * 0.15;
      var hIn = flow === 0 ? 0 : (Math.abs(numOf(r.qtyIn) || 0) / flow) * half;
      var hOut = flow === 0 ? 0 : (Math.abs(numOf(r.qtyOut) || 0) / flow) * half;
      if (r.period === selected) {
        body += '<rect class="pr360-ch-slot" x="' + x0.toFixed(1) + '" y="' + CH_LEVEL_TOP
          + '" width="' + slot.toFixed(1) + '" height="'
          + (CH_FLOW_TOP + CH_FLOW_H - CH_LEVEL_TOP) + '"></rect>';
      }
      if (hIn > 0) {
        body += '<rect class="pr360-ch-in" x="' + xBar.toFixed(1) + '" y="'
          + (zeroFlow - hIn).toFixed(1) + '" width="' + wBar.toFixed(1) + '" height="'
          + hIn.toFixed(1) + '"></rect>';
      }
      if (hOut > 0) {
        body += '<rect class="pr360-ch-out" x="' + xBar.toFixed(1) + '" y="'
          + zeroFlow.toFixed(1) + '" width="' + wBar.toFixed(1) + '" height="'
          + hOut.toFixed(1) + '"></rect>';
      }
    });

    return K.raw(
      '<svg class="pr360-chart-svg" viewBox="0 0 ' + CH_W + ' ' + CH_H
        + '" preserveAspectRatio="none" focusable="false" aria-hidden="true">'
      + body
      + '<path class="pr360-ch-area" d="' + area + '"></path>'
      + '<path class="pr360-ch-line" d="' + steps + '"></path>'
      + '<line class="pr360-ch-axis" x1="' + CH_PAD + '" y1="' + zeroLevel.toFixed(1)
        + '" x2="' + (CH_W - CH_PAD) + '" y2="' + zeroLevel.toFixed(1) + '"></line>'
      + '<line class="pr360-ch-axis" x1="' + CH_PAD + '" y1="' + zeroFlow.toFixed(1)
        + '" x2="' + (CH_W - CH_PAD) + '" y2="' + zeroFlow.toFixed(1) + '"></line>'
      + '</svg>'
    );
  }

  /*
   * La escala, en HTML y en un canal reservado a la izquierda del dibujo: cuatro cifras en los
   * cuatro bordes que el dibujo usa como limite -- techo y suelo del saldo, maximo de entrada y
   * maximo de salida. No van encima del SVG a proposito, asi que nunca tapan una barra; y son
   * exactas porque el alto del SVG en pixeles es el mismo numero que el alto de su viewBox, de
   * modo que una unidad del dibujo es un pixel de la pagina.
   *
   * aria-hidden porque no aportan nada a quien no ve el dibujo: cada boton del eje ya dice sus
   * tres cifras enteras en su etiqueta accesible.
   */
  function chartScale(rows) {
    var ext = chartExtent(rows);
    var marks = [
      { y: CH_LEVEL_TOP, v: ext.hiBal },
      { y: CH_LEVEL_TOP + CH_LEVEL_H, v: ext.loBal },
      { y: CH_FLOW_TOP, v: ext.flow },
      { y: CH_FLOW_TOP + CH_FLOW_H, v: ext.flow }
    ];
    return marks.map(function (m) {
      return html`
        <span class="pr360-ch-scale" style="top:${m.y}px" aria-hidden="true"
          >${K.fmt(m.v, 'qty')}</span>
      `;
    });
  }

  /*
   * La tira de botones que hace pulsable el grafico, y que a la vez es el rotulo del eje. Uno por
   * periodo, con su etiqueta accesible completa: quien no ve el dibujo recorre la misma serie con
   * el tabulador y oye el periodo, la entrada, la salida y el saldo.
   *
   * La tira cubre el grafico entero (el CSS la pone en absoluto sobre .pr360-chart), asi que la
   * diana de un periodo mide los 208px de alto del dibujo y no los 18 de su rotulo: pulsar una
   * columna es pulsar donde esta la barra, que es donde el lector mira. El rotulo visible se
   * escribe solo en el primer periodo de cada ano -- ver tickLabels -- y el resto conserva su
   * hueco con .pr360-mute, VACIO: el hueco lo sostiene el min-height del CSS, no un texto. Con el
   * periodo escrito dentro, el hueco de la ultima columna medido con grano mensual desbordaba su
   * region a lo ancho aunque no se viese -- visibility:hidden no quita el ancho.
   */
  function chartHits(rows, selected, unit) {
    var names = tickLabels(rows);
    var hits = rows.map(function (r, i) {
      var label = r.period + ': ' + K.t('ETDEMO_PR360In') + ' ' + K.fmt(numOf(r.qtyIn) || 0, 'qty')
        + ', ' + K.t('ETDEMO_PR360Out') + ' ' + K.fmt(numOf(r.qtyOut) || 0, 'qty')
        + ', ' + K.t('ETDEMO_PR360Balance') + ' ' + K.fmt(numOf(r.balance) || 0, 'qty')
        + ' ' + unit;
      return html`
        <button type="button" class="pr360-ch-hit${r.period === selected ? ' on' : ''}"
          data-period="${r.period}" aria-pressed="${r.period === selected ? 'true' : 'false'}"
          aria-label="${label}" title="${label}"
          ><span class="${names[i] ? 'pr360-ch-name' : 'pr360-ch-name pr360-mute'}"
          >${names[i]}</span></button>
      `;
    });
    return html`
      <div class="pr360-chart-hits" role="group" aria-label="${K.t('ETDEMO_PR360Periods')}"
        >${hits}</div>
    `;
  }

  /* --------------------------------------------------------------- barras */

  /*
   * Una barra pulsable. Reusa .uik-bar de la hoja del kit -- la geometria, el relleno tras el
   * texto y la direccion del negativo ya estan resueltas alli -- y solo cambia el elemento por un
   * boton, porque estas barras son un eje y no una lectura: pulsar una vuelve a leer la ventana.
   */
  function pickBar(spec) {
    var pct = spec.max > 0 ? Math.max(0, Math.min(100, (Math.abs(spec.value) / spec.max) * 100))
      : 0;
    return html`
      <button type="button" class="uik-bar uik-${spec.state || 'flat'} pr360-barpick${spec.on
          ? ' on' : ''}" style="--uik-v:${pct.toFixed(1)}%"${spec.value === 0
          ? ' data-zero="1"' : ''}
        data-${spec.axis}="${spec.id}" aria-pressed="${spec.on ? 'true' : 'false'}">
        <span class="uik-bar-label">${spec.label}${spec.sub
          ? html`<em>${spec.sub}</em>` : ''}</span>
        <span class="uik-bar-value">${spec.text}</span>
      </button>
    `;
  }

  /** The largest absolute value in a set of rows, so every bar in a panel shares one scale. */
  function topOf(rows, key) {
    var top = 0;
    rows.forEach(function (r) {
      top = Math.max(top, Math.abs(numOf(r[key]) || 0));
    });
    return top;
  }

  /* ------------------------------------------------------------------ regiones */

  function headRegion() {
    return html`
      <header class="pr360-head">
        <h1 class="pr360-title">${K.t('ETDEMO_PR360Title')}</h1>
        <p class="pr360-subtitle">${K.t('ETDEMO_PR360Desc')}</p>
        <span class="pr360-brand">${K.t('ETDEMO_PR360Brand')}</span>
      </header>
    `;
  }

  /*
   * La barra lleva los cuatro ejes que eligen QUE producto se lee -- texto, categoria, orden y
   * tamano de pagina -- y el almacen, que elige BAJO QUE se lee.
   *
   * Los dos ejes de catalogo vienen del datasource calculados sin la busqueda y sin el propio
   * filtro, asi que las pastillas que se ven no dependen de lo que este elegido: si dependieran,
   * quitar un filtro seria imposible porque su pastilla habria desaparecido al aplicarlo. La
   * categoria lleva su conteo porque es el dato que dice si vale la pena entrar.
   *
   * Cada grupo de pastillas lleva su rotulo EN LINEA y no encima, que es el marcado de Console.
   * Envolverlos en .pr360-field -- un contenedor de 260px pensado para un input -- doblaba 609px
   * de pastillas en tres filas y con align-items:flex-end dejaba el buscador pegado al fondo de
   * una linea de 135px: la barra medía 310px de los 900 de pantalla y el carril empezaba en 498.
   * El rotulo en linea es tambien el nombre accesible del grupo, y por eso va el role.
   */
  function barRegion(state, data, ui) {
    var d = data.index;
    var cats = d && d.categories ? d.categories : [];
    var whs = d && d.warehouses ? d.warehouses : [];
    var cat = textOf(state.categoryId);
    var wh = textOf(state.warehouseId);
    var sort = sortOf(state);
    var limit = limitOf(state);
    return html`
      <div class="pr360-bar pr360-bar-p360">
        <label class="pr360-field pr360-field-wide">
          <span class="pr360-field-label">${K.t('ETDEMO_PR360SearchLabel')}</span>
          <input type="search" class="pr360-input" data-q value="${textOf(state.q)}"
            placeholder="${K.t('ETDEMO_PR360SearchHint')}" autocomplete="off">
        </label>
        <div class="pr360-chips" role="group" aria-label="${K.t('ETDEMO_PR360CategoryLabel')}">
          <span class="pr360-chips-label">${K.t('ETDEMO_PR360CategoryLabel')}</span>
          <button type="button" class="pr360-chip${cat ? '' : ' on'}" data-category=""
            aria-pressed="${cat ? 'false' : 'true'}">${K.t('ETDEMO_PR360AllCategories')}</button>
          ${cats.map(function (c) {
            return html`
              <button type="button" class="pr360-chip${cat === c.id ? ' on' : ''}"
                data-category="${c.id}" aria-pressed="${cat === c.id ? 'true' : 'false'}"
                >${c.name} <em>${K.fmt(c.n, 'int')}</em></button>
            `;
          })}
        </div>
        <div class="pr360-chips" role="group" aria-label="${K.t('ETDEMO_PR360WarehouseLabel')}">
          <span class="pr360-chips-label">${K.t('ETDEMO_PR360WarehouseLabel')}</span>
          <button type="button" class="pr360-chip${wh ? '' : ' on'}" data-warehouse-pick=""
            aria-pressed="${wh ? 'false' : 'true'}">${K.t('ETDEMO_PR360AllWarehouses')}</button>
          ${whs.map(function (w) {
            return html`
              <button type="button" class="pr360-chip${wh === w.id ? ' on' : ''}"
                data-warehouse-pick="${w.id}" aria-pressed="${wh === w.id ? 'true' : 'false'}"
                >${w.name}</button>
            `;
          })}
        </div>
        <div class="pr360-chips" role="group" aria-label="${K.t('ETDEMO_PR360SortLabel')}">
          <span class="pr360-chips-label">${K.t('ETDEMO_PR360SortLabel')}</span>
          ${SORTS.map(function (s) {
            return html`
              <button type="button" class="pr360-chip${sort === s.id ? ' on' : ''}"
                data-sort="${s.id}" aria-pressed="${sort === s.id ? 'true' : 'false'}"
                >${K.t(s.label)}</button>
            `;
          })}
        </div>
        <div class="pr360-chips pr360-chips-quiet" role="group"
          aria-label="${K.t('ETDEMO_PR360PageSizeLabel')}">
          <span class="pr360-chips-label">${K.t('ETDEMO_PR360PageSizeLabel')}</span>
          ${LIMITS.map(function (n) {
            return html`
              <button type="button" class="pr360-chip${limit === n ? ' on' : ''}"
                data-limit="${n}" aria-pressed="${limit === n ? 'true' : 'false'}">${n}</button>
            `;
          })}
        </div>
      </div>
    `;
  }

  /*
   * El carril: un renglon por producto y nada mas que lo que hace falta para elegir. La barra
   * compara solo dentro de la pagina que se esta viendo -- y lo dice -- porque comparar contra el
   * maximo del catalogo dejaria 24 barras invisibles junto a una llena.
   */
  function railRegion(state, data, ui) {
    var broken = failed(ui, 'index');
    if (broken) {
      return broken;
    }
    var d = data.index;
    if (!d) {
      return html`<p class="pr360-note">${K.t('ETDEMO_PR360StateLoading')}</p>`;
    }
    var rows = d.rows || [];
    if (!rows.length) {
      return html`
        <div class="pr360-state pr360-state-empty">
          <h2 class="pr360-state-title">${K.t('ETDEMO_PR360NoRowsTitle')}</h2>
          <p class="pr360-state-body">${K.t('ETDEMO_PR360NoRowsBody')}</p>
        </div>
      `;
    }
    var top = topOf(rows, 'onhand');
    var chosen = textOf(state.itemId);
    var items = rows.map(function (r) {
      var pct = top > 0 ? Math.max(0, Math.min(100, ((numOf(r.onhand) || 0) / top) * 100)) : 0;
      return html`
        <li class="pr360-rail-item">
          <button type="button" class="pr360-rail-pick${chosen === r.id ? ' on' : ''}"
            data-product="${r.id}" aria-pressed="${chosen === r.id ? 'true' : 'false'}">
            <span class="pr360-rail-top">
              <b class="pr360-rail-code">${r.code}</b>
              <span class="pr360-rail-qty">${qty(r.onhand, r.uom)}</span>
            </span>
            <span class="pr360-rail-name">${r.name}</span>
            <span class="pr360-spark" style="--uik-v:${pct.toFixed(1)}%"></span>
            <em class="pr360-rail-foot">
              <span>${r.category}</span>
              <span>${count(r.moves, 'ETDEMO_PR360MoveOne', 'ETDEMO_PR360Moves')}</span>
              <span>${dateText(r.lastMove)}</span>
            </em>
          </button>
        </li>
      `;
    });
    return html`
      <section class="pr360-panel">
        <div class="pr360-panel-head">
          <h2 class="pr360-panel-title">${K.t('ETDEMO_PR360Rail')}</h2>
          <span class="pr360-panel-aside">${count(d.page ? d.page.total : null,
            'ETDEMO_PR360ProductOne', 'ETDEMO_PR360Products')}</span>
        </div>
        <ul class="pr360-rail-list">${items}</ul>
        <p class="pr360-note">${K.t('ETDEMO_PR360RailNote')}</p>
      </section>
    `;
  }

  function pagerRegion(state, data, ui) {
    var d = data.index;
    if (!d || broke(ui, 'index') || !d.page) {
      return '';
    }
    var page = d.page.page;
    var pages = d.page.pages;
    return html`
      <nav class="uik-pager pr360-pager" aria-label="${K.t('ETDEMO_PR360PagerLabel')}">
        <button type="button" class="pr360-page" data-page="${page - 1}"
          ${page <= 1 ? 'disabled' : ''}>${K.t('ETDEMO_PR360Prev')}</button>
        <span class="pr360-page-of">
          ${K.t('ETDEMO_PR360PageOf')} ${K.fmt(page, 'int')} / ${K.fmt(pages, 'int')}
          &middot; ${K.fmt(d.page.total, 'int')} ${K.t('ETDEMO_PR360Products')}
        </span>
        <button type="button" class="pr360-page" data-page="${page + 1}"
          ${page >= pages ? 'disabled' : ''}>${K.t('ETDEMO_PR360Next')}</button>
      </nav>
    `;
  }

  /* ------------------------------------------------------------ el producto */

  /*
   * La ficha y las cifras del instante, con una decision en el medio: la reparticion entre
   * reservado y disponible se dibuja con la barra del kit, cuya marca es el reservado y cuyo
   * relleno es el disponible, sobre la cantidad en mano. No hay umbral ni color de alarma: la
   * base no trae ningun minimo con valor -- `qtymin` es cero en todo el catalogo -- asi que
   * pintar de rojo una cantidad seria una opinion de la vista, no un dato.
   */
  function tile(labelKey, value, hintKey) {
    return html`
      <div class="pr360-tile">
        <span class="pr360-tile-label">${K.t(labelKey)}</span>
        <span class="pr360-tile-value">${value}</span>
        ${hintKey ? html`<span class="pr360-tile-hint">${K.t(hintKey)}</span>` : ''}
      </div>
    `;
  }

  function worthTable(rows) {
    if (!rows.length) {
      return html`<p class="pr360-note">${K.t('ETDEMO_PR360NoWorth')}</p>`;
    }
    var body = rows.map(function (r) {
      return html`
        <tr>
          <td>${r.currency}</td>
          <td class="pr360-num">${dash(r.unitCost, 'price')}</td>
          <td class="pr360-num">${dash(r.lines, 'int')}</td>
          <td>${dateText(r.firstDate)} - ${dateText(r.lastDate)}</td>
        </tr>
      `;
    });
    return html`
      <table class="uik-table pr360-table pr360-worth">
        <thead>
          <tr>
            <th>${K.t('ETDEMO_PR360ColCurrency')}</th>
            <th class="pr360-num">${K.t('ETDEMO_PR360ColUnitCost')}</th>
            <th class="pr360-num">${K.t('ETDEMO_PR360ColLines')}</th>
            <th>${K.t('ETDEMO_PR360ColSpan')}</th>
          </tr>
        </thead>
        <tbody>${body}</tbody>
      </table>
    `;
  }

  function heroRegion(state, data, ui) {
    if (!textOf(state.itemId)) {
      return html`
        <div class="pr360-state pr360-state-empty">
          <h2 class="pr360-state-title">${K.t('ETDEMO_PR360NoPickTitle')}</h2>
          <p class="pr360-state-body">${K.t('ETDEMO_PR360NoPickBody')}</p>
        </div>
      `;
    }
    var broken = failed(ui, 'item');
    if (broken) {
      return broken;
    }
    var d = data.item;
    if (!d) {
      return html`<p class="pr360-note">${K.t('ETDEMO_PR360StateLoading')}</p>`;
    }
    var h = d.head;
    if (!h) {
      return html`
        <div class="pr360-state pr360-state-empty">
          <h2 class="pr360-state-title">${K.t('ETDEMO_PR360GoneTitle')}</h2>
          <p class="pr360-state-body">${K.t('ETDEMO_PR360GoneBody')}</p>
        </div>
      `;
    }
    var t = d.totals || {};
    var meta = d.meta || {};
    var reserved = share(t.reserved, t.onhand);
    // Una sola linea: el minificador del kernel no entiende plantillas y una comilla de atributo
    // abierta en una linea y cerrada en la siguiente le parece una cadena sin cerrar.
    var reservedAria = reserved === null ? ''
      : K.t('ETDEMO_PR360ColReserved') + ' ' + K.fmt(reserved, 'pct');
    return html`
      <section class="pr360-panel pr360-hero">
        <div class="pr360-hero-id">
          <h2 class="pr360-hero-code">${h.code}</h2>
          <p class="pr360-hero-name">${h.name}</p>
          ${textOf(h.description)
            ? html`<p class="pr360-hero-desc">${h.description}</p>` : ''}
          <p class="pr360-hero-tags">
            <button type="button" class="pr360-link" data-category="${h.categoryId}"
              >${h.category}</button>
            ${K.badge(h.uom, 'flat')}
            ${K.badge(h.stocked === 'Y' ? K.t('ETDEMO_PR360Stocked')
              : K.t('ETDEMO_PR360NotStocked'), 'flat')}
            ${textOf(h.attributeSet)
              ? K.badge(h.attributeSet, 'flat') : ''}
            ${meta.productTab
              ? html`<button type="button" class="pr360-link" data-open="${h.id}"
                  >${K.t('ETDEMO_PR360OpenProduct')}</button>`
              : ''}
          </p>
        </div>
        <div class="pr360-tiles pr360-hero-tiles pr360-hero-qty">
          ${tile('ETDEMO_PR360ColOnhand', qty(t.onhand, h.uom))}
          ${tile('ETDEMO_PR360ColReserved', qty(t.reserved, h.uom))}
          ${tile('ETDEMO_PR360ColAvailable', qty(t.available, h.uom))}
        </div>
        <div class="pr360-split">
          <span class="pr360-split-label">${K.t('ETDEMO_PR360Split')}</span>
          ${reserved === null
            ? html`<span class="pr360-dash">-</span>`
            : html`
              <span class="pr360-spark pr360-split-rail"
                style="--uik-v:${reserved.toFixed(1)}%"
                role="img" aria-label="${reservedAria}"></span>
              <span class="pr360-split-value">${K.fmt(reserved, 'pct')}
                ${K.t('ETDEMO_PR360ColReserved')}</span>
            `}
        </div>
        <div class="pr360-tiles pr360-hero-tiles pr360-hero-counts">
          ${tile('ETDEMO_PR360TileLocators', dash(t.locators, 'int'))}
          ${tile('ETDEMO_PR360TileWarehouses', dash(t.warehouses, 'int'))}
          ${tile('ETDEMO_PR360TileLots', dash(t.lots, 'int'), 'ETDEMO_PR360TileLotsHint')}
          ${tile('ETDEMO_PR360TileStockRows', dash(t.rows, 'int'), 'ETDEMO_PR360TileStockRowsHint')}
          ${tile('ETDEMO_PR360LastInventory', dateText(t.lastInventory), 'ETDEMO_PR360LastInventoryHint')}
        </div>
        <div class="pr360-worth-block">
          <h3 class="pr360-panel-sub">${K.t('ETDEMO_PR360Worth')}</h3>
          ${worthTable(d.worth || [])}
          <p class="pr360-note">${K.t('ETDEMO_PR360WorthNote')}</p>
        </div>
        <p class="pr360-asof">${K.t('ETDEMO_PR360AsOf')} ${dateText(meta.asOf)}
          ${meta.asOfSource === 'today'
            ? html`<em>${K.t('ETDEMO_PR360AsOfToday')}</em>` : ''}</p>
      </section>
    `;
  }

  /* --------------------------------------------------------------- el libro */

  /*
   * El libro es la espina dorsal de la ventana: acumular las transacciones con signo en orden de
   * fecha aterriza en la cantidad en mano de la cabecera, y eso vale tanto en total como almacen
   * por almacen. Por eso no hay filtro de fechas y el grano solo corta los periodos.
   *
   * El periodo elegido es estado de la vista y no del servidor: la serie ya vino entera, asi que
   * pulsar un periodo no vuelve a pedir nada, solo mueve la lectura. Y no filtra el rastro: el
   * rastro se pagina en SQL y no acepta periodo, asi que fingir que lo estrecha seria decir algo
   * que la consulta no hace.
   */
  function readout(row, unit) {
    if (!row) {
      return html`<p class="pr360-note">${K.t('ETDEMO_PR360PickPeriod')}</p>`;
    }
    return html`
      <div class="pr360-readout">
        <span class="pr360-readout-key">${row.period}</span>
        <span><em>${K.t('ETDEMO_PR360In')}</em> ${qty(row.qtyIn, unit)}</span>
        <span><em>${K.t('ETDEMO_PR360Out')}</em> ${qty(row.qtyOut, unit)}</span>
        <span><em>${K.t('ETDEMO_PR360Net')}</em> ${qty(row.net, unit)}</span>
        <span><em>${K.t('ETDEMO_PR360Balance')}</em> ${qty(row.balance, unit)}</span>
        <span><em>${K.t('ETDEMO_PR360ColLines')}</em> ${dash(row.lines, 'int')}</span>
        <span class="pr360-quiet">${dateText(row.firstDate)} - ${dateText(row.lastDate)}</span>
      </div>
    `;
  }

  function ledgerRegion(state, data, ui) {
    if (!textOf(state.itemId)) {
      return '';
    }
    var broken = failed(ui, 'ledger');
    if (broken) {
      return broken;
    }
    var d = data.ledger;
    var unit = data.item && data.item.head ? data.item.head.uom : '';
    if (!d) {
      return html`<p class="pr360-note">${K.t('ETDEMO_PR360StateLoading')}</p>`;
    }
    var rows = d.series || [];
    var grain = grainOf(state);
    var chips = GRAINS.map(function (g) {
      return html`
        <button type="button" class="pr360-chip${grain === g.id ? ' on' : ''}"
          data-grain="${g.id}" aria-pressed="${grain === g.id ? 'true' : 'false'}"
          >${K.t(g.label)}</button>
      `;
    });
    if (!rows.length) {
      return html`
        <section class="pr360-panel">
          <div class="pr360-panel-head">
            <h2 class="pr360-panel-title">${K.t('ETDEMO_PR360Ledger')}</h2>
            <span class="pr360-chips pr360-chips-quiet">${chips}</span>
          </div>
          <div class="pr360-state pr360-state-empty">
            <h2 class="pr360-state-title">${K.t('ETDEMO_PR360NoMoves')}</h2>
          </div>
        </section>
      `;
    }
    /* Sin eleccion se lee el ultimo periodo, que es el que cierra el saldo. */
    var wanted = textOf(state.period);
    var current = null;
    rows.forEach(function (r) {
      if (r.period === wanted) {
        current = r;
      }
    });
    if (!current) {
      current = rows[rows.length - 1];
    }
    return html`
      <section class="pr360-panel">
        <div class="pr360-panel-head">
          <h2 class="pr360-panel-title">${K.t('ETDEMO_PR360Ledger')}</h2>
          <span class="pr360-chips pr360-chips-quiet">${chips}</span>
        </div>
        <p class="pr360-legend">
          <span class="pr360-key pr360-key-level">${K.t('ETDEMO_PR360Balance')}</span>
          <span class="pr360-key pr360-key-in">${K.t('ETDEMO_PR360In')}</span>
          <span class="pr360-key pr360-key-out">${K.t('ETDEMO_PR360Out')}</span>
          <span class="pr360-quiet">${count(rows.length, 'ETDEMO_PR360PeriodOne',
            'ETDEMO_PR360Periods')}</span>
          <span class="pr360-quiet">${K.t('ETDEMO_PR360PickPeriod')}</span>
        </p>
        <div class="pr360-chart">
          ${chartScale(rows)}
          ${ledgerChart(rows, current.period)}
          ${chartHits(rows, current.period, unit)}
        </div>
        ${readout(current, unit)}
        <p class="pr360-note">${K.t('ETDEMO_PR360LedgerNote')}</p>
      </section>
    `;
  }

  /* ----------------------------------------------------------- los otros ejes */

  /*
   * La mezcla por tipo de movimiento, medida en NETO: lo que cada tipo aporto al saldo. Es la
   * unica cifra que se puede poner en una sola barra sin mentir -- entrada y salida en la misma
   * barra serian dos magnitudes en un solo largo -- y el kit ya dibuja el negativo creciendo
   * desde el borde derecho, asi que una salida no se confunde con una entrada pequena. El
   * rotulo del tipo lo resuelve el diccionario en SQL; la vista no tiene tabla de traduccion.
   */
  /*
   * La mezcla por tipo de documento. Dos longitudes desde un cero comun -- lo que salio a la
   * izquierda del eje, lo que entro a la derecha -- y no una sola barra con el neto.
   *
   * El neto solo no se podia leer: en esta base el rango entre tipos llega a 7.350.270x y un tipo
   * de inventario neta casi a cero porque suma y resta, asi que "Inventory In 15.000" no dibujaba
   * nada mientras habia movido 564.700 unidades en nueve lineas. El neto sigue impreso como cifra,
   * que es lo que aporta al saldo; el dibujo cuenta el movimiento. Es la misma convencion que el
   * panel de flujo del libro, y por eso comparte su leyenda: marca lo que entra, tinta suave lo
   * que sale, y la direccion la dice el lado del eje y no el color.
   */
  function mixRegion(state, data, ui) {
    if (!textOf(state.itemId)) {
      return '';
    }
    var d = data.ledger;
    if (!d || broke(ui, 'ledger')) {
      return '';
    }
    var rows = d.mix || [];
    if (!rows.length) {
      return '';
    }
    var unit = data.item && data.item.head ? data.item.head.uom : '';
    var top = Math.max(topOf(rows, 'qtyIn'), topOf(rows, 'qtyOut'));
    var items = rows.map(function (r) {
      var qin = numOf(r.qtyIn) || 0;
      var qout = numOf(r.qtyOut) || 0;
      var net = numOf(r.qtyIn) === null && numOf(r.qtyOut) === null ? 0 : qin - qout;
      var pIn = top > 0 ? (qin / top) * 100 : 0;
      var pOut = top > 0 ? (qout / top) * 100 : 0;
      return html`
        <div class="pr360-mix-row"
          style="--pr360-in:${pIn.toFixed(1)}%;--pr360-out:${pOut.toFixed(1)}%">
          <span class="pr360-mix-label">${textOf(r.label) || r.type}<em
            >${K.t('ETDEMO_PR360Out')} ${K.fmt(qout, 'qty')} - ${K.t('ETDEMO_PR360In')}
            ${K.fmt(qin, 'qty')} - ${count(r.lines, 'ETDEMO_PR360FlowLineOne',
              'ETDEMO_PR360FlowLines')}</em></span>
          <span class="pr360-mix-net">${K.fmt(net, 'qty')}<em
            >${K.t('ETDEMO_PR360Net')}</em></span>
          <span class="pr360-mix-track" aria-hidden="true"><i class="pr360-mix-out"></i><i
            class="pr360-mix-in"></i></span>
        </div>
      `;
    });
    return html`
      <section class="pr360-panel">
        <div class="pr360-panel-head">
          <h2 class="pr360-panel-title">${K.t('ETDEMO_PR360Mix')}</h2>
          <span class="pr360-panel-aside">${unit}</span>
        </div>
        <p class="pr360-legend">
          <span class="pr360-key pr360-key-out">${K.t('ETDEMO_PR360Out')}</span>
          <span class="pr360-key pr360-key-in">${K.t('ETDEMO_PR360In')}</span>
        </p>
        <div class="pr360-mix">${items}</div>
        <p class="pr360-note">${K.t('ETDEMO_PR360MixNote')}</p>
      </section>
    `;
  }

  /*
   * El eje del almacen, y el unico panel que ignora a proposito el filtro que el mismo escribe.
   *
   * Si se filtrara, elegir un almacen dejaria una sola barra en pantalla y salir del filtro
   * exigiria acordarse de que hay una pastilla arriba. Sin filtrar, el reparto completo sigue
   * ahi: se ve donde esta el resto del stock, se ve cuanto pesa el almacen elegido sobre el
   * total, y se cambia de almacen desde el propio panel.
   */
  function warehousesRegion(state, data, ui) {
    if (!textOf(state.itemId)) {
      return '';
    }
    var d = data.item;
    if (!d || broke(ui, 'item') || !d.head) {
      return '';
    }
    var rows = d.warehouses || [];
    if (!rows.length) {
      return '';
    }
    var unit = d.head.uom;
    var current = textOf(state.warehouseId);
    var top = topOf(rows, 'onhand');
    var bars = rows.map(function (r) {
      return pickBar({
        axis: 'warehouse-pick',
        id: r.id,
        on: current === r.id,
        value: numOf(r.onhand) || 0,
        max: top,
        state: 'flat',
        label: r.name,
        sub: count(r.locators, 'ETDEMO_PR360PlaceOne', 'ETDEMO_PR360PlacesWord') + ' - '
          + K.t('ETDEMO_PR360ColReserved') + ' ' + K.fmt(numOf(r.reserved) || 0, 'qty'),
        text: K.fmt(numOf(r.onhand) || 0, 'qty')
      });
    });
    return html`
      <section class="pr360-panel">
        <div class="pr360-panel-head">
          <h2 class="pr360-panel-title">${K.t('ETDEMO_PR360Warehouses')}</h2>
          ${current
            ? html`<button type="button" class="pr360-close" data-warehouse-pick=""
                >${K.t('ETDEMO_PR360AllWarehouses')}</button>`
            : html`<span class="pr360-panel-aside">${unit}</span>`}
        </div>
        <div class="uik-bars pr360-barpicks">${bars}</div>
        <p class="pr360-note">${K.t('ETDEMO_PR360WarehouseNote')}</p>
      </section>
    `;
  }

  /* El sitio exacto, que es lo que se pregunta delante de una estanteria. */
  function locatorsRegion(state, data, ui) {
    if (!textOf(state.itemId)) {
      return '';
    }
    var d = data.item;
    if (!d || broke(ui, 'item') || !d.head) {
      return '';
    }
    var rows = d.locators || [];
    if (!rows.length) {
      return '';
    }
    var unit = d.head.uom;
    var shown = (d.meta || {}).locatorRows;
    var total = (d.totals || {}).rows;
    var inUse = (d.totals || {}).locators;
    var top = topOf(rows, 'onhand');
    var body = rows.map(function (r) {
      var pct = top > 0 ? Math.max(0, Math.min(100, ((numOf(r.onhand) || 0) / top) * 100)) : 0;
      /*
       * Cero estricto en las dos cifras, como isEmpty en locate.js: una cantidad negativa no es
       * un sitio vacio. En esta base 163 de las 255 filas de existencias estan a cero -- son
       * sitios que se vaciaron, no ruido -- asi que se quedan, detras y en voz baja.
       */
      var empty = numOf(r.onhand) === 0 && numOf(r.reserved) === 0;
      return html`
        <tr class="${empty ? 'pr360-row-empty' : ''}">
          <td>${r.warehouse}</td>
          <td class="pr360-cell-key">${r.locator}</td>
          <td>${textOf(r.attribute) || html`<span class="pr360-dash">-</span>`}</td>
          <td class="pr360-num pr360-cell-bar">
            <span class="pr360-spark" style="--uik-v:${pct.toFixed(1)}%"></span>
            ${dash(r.onhand)} <span class="pr360-uom">${unit}</span>
          </td>
          <td class="pr360-num">${dash(r.reserved)}</td>
          <td>${dateText(r.lastInventory)}</td>
        </tr>
      `;
    });
    return html`
      <section class="pr360-panel">
        <div class="pr360-panel-head">
          <h2 class="pr360-panel-title">${K.t('ETDEMO_PR360Locators')}</h2>
          <span class="pr360-panel-aside">${dash(inUse, 'int')}
            ${K.t('ETDEMO_PR360InUseWord')} - ${K.fmt(rows.length, 'int')}
            ${K.t('ETDEMO_PR360FlowOf')} ${dash(total, 'int')}</span>
        </div>
        <table class="uik-table pr360-table">
          <thead>
            <tr>
              <th>${K.t('ETDEMO_PR360ColWarehouse')}</th>
              <th>${K.t('ETDEMO_PR360ColLocator')}</th>
              <th>${K.t('ETDEMO_PR360ColAttribute')}</th>
              <th class="pr360-num">${K.t('ETDEMO_PR360ColOnhand')}</th>
              <th class="pr360-num">${K.t('ETDEMO_PR360ColReserved')}</th>
              <th>${K.t('ETDEMO_PR360LastInventory')}</th>
            </tr>
          </thead>
          <tbody>${body}</tbody>
        </table>
        ${rows.length >= shown
          ? html`<p class="pr360-note">${K.t('ETDEMO_PR360LocatorNote')}</p>` : ''}
      </section>
    `;
  }

  /*
   * El lote o la serie. Aqui es donde estaria la caducidad si la hubiera: `guaranteedate` esta
   * nula en las 218 instancias de atributo de esta base, asi que el panel dice que no la usa en
   * vez de dibujar una columna de blancos.
   */
  function lotsRegion(state, data, ui) {
    if (!textOf(state.itemId)) {
      return '';
    }
    var d = data.item;
    if (!d || broke(ui, 'item') || !d.head) {
      return '';
    }
    var rows = d.lots || [];
    if (!rows.length) {
      return '';
    }
    /*
     * Cuarenta y nueve de los cincuenta y cinco productos de esta base no llevan lote ni serie, y
     * para ellos el panel dibujaba una sola barra llena que repetia el "en mano" de la cabecera.
     * El panel se queda -- la pregunta "tiene lotes?" merece respuesta visible, y un eje que
     * desaparece cuando esta vacio deja al lector sin saber si la ventana lo miro -- pero
     * responde con una linea de texto en vez de con una barra que no compara nada.
     */
    var lotless = rows.length === 1 && !textOf(rows[0].label);
    var items = rows.map(function (r) {
      return {
        label: textOf(r.label) || K.t('ETDEMO_PR360NoAttribute'),
        sub: count(r.locators, 'ETDEMO_PR360PlaceOne', 'ETDEMO_PR360PlacesWord'),
        value: numOf(r.onhand) || 0,
        state: 'flat'
      };
    });
    return html`
      <section class="pr360-panel">
        <div class="pr360-panel-head">
          <h2 class="pr360-panel-title">${K.t('ETDEMO_PR360Lots')}</h2>
          <span class="pr360-panel-aside">${d.head.uom}</span>
        </div>
        ${lotless
          ? html`<p class="pr360-note">${K.t('ETDEMO_PR360NoLotsBody')}</p>`
          : html`
            ${K.bars({
              items: items,
              label: K.t('ETDEMO_PR360Lots'),
              format: function (v) {
                return K.fmt(v, 'qty');
              }
            })}
            <p class="pr360-note">${K.t('ETDEMO_PR360LotNote')}</p>
          `}
      </section>
    `;
  }

  /*
   * La categoria como eje de comparacion: el mismo producto no dice nada solo, y "1.234 en mano"
   * cambia de sentido segun si es el primero de su categoria o el septimo. El servidor devuelve
   * las primeras filas por cantidad MAS el producto elegido aunque caiga fuera, para que la
   * comparacion no desaparezca justo cuando es interesante.
   */
  function peersRegion(state, data, ui) {
    if (!textOf(state.itemId)) {
      return '';
    }
    var d = data.item;
    if (!d || broke(ui, 'item') || !d.head) {
      return '';
    }
    var rows = d.peers || [];
    if (rows.length < 2) {
      return '';
    }
    var chosen = textOf(state.itemId);
    var mine = null;
    rows.forEach(function (r) {
      if (r.id === chosen) {
        mine = r;
      }
    });
    var top = topOf(rows, 'onhand');
    var bars = rows.map(function (r) {
      return pickBar({
        axis: 'product',
        id: r.id,
        on: r.id === chosen,
        value: numOf(r.onhand) || 0,
        max: top,
        state: 'flat',
        label: r.code,
        sub: r.name,
        text: K.fmt(numOf(r.onhand) || 0, 'qty')
      });
    });
    return html`
      <section class="pr360-panel">
        <div class="pr360-panel-head">
          <h2 class="pr360-panel-title">${K.t('ETDEMO_PR360Peers')}</h2>
          <span class="pr360-panel-aside">${d.head.category}</span>
        </div>
        ${mine
          ? html`<p class="pr360-rank">${K.t('ETDEMO_PR360Rank')}
              <b>${K.fmt(mine.rank, 'int')}</b> ${K.t('ETDEMO_PR360FlowOf')}
              ${K.fmt(mine.peers, 'int')}</p>`
          : ''}
        <div class="uik-bars pr360-barpicks">${bars}</div>
        <p class="pr360-note">${K.t('ETDEMO_PR360PeersNote')}</p>
      </section>
    `;
  }

  /*
   * Lo pedido y no entregado, fechado por ano de pedido y NUNCA sumado al stock. La fecha es la
   * que lo explica: la linea abierta mas vieja de esta base es de 2011 y la mas nueva de 2021,
   * asi que esto es una cartera de lineas que nadie cerro y no mercancia en camino. Presentado
   * sin fecha, un solo numero al lado del stock invitaria a sumarlos.
   */
  function pendingRegion(state, data, ui) {
    if (!textOf(state.itemId)) {
      return '';
    }
    var d = data.item;
    if (!d || broke(ui, 'item') || !d.head) {
      return '';
    }
    var rows = d.pending || [];
    if (!rows.length) {
      return '';
    }
    var items = rows.map(function (r) {
      return {
        label: r.period,
        sub: K.t(r.direction === 'sales' ? 'ETDEMO_PR360DirSales' : 'ETDEMO_PR360DirPurchase') + ' - '
          + count(r.lines, 'ETDEMO_PR360FlowLineOne', 'ETDEMO_PR360FlowLines'),
        value: numOf(r.qty) || 0,
        state: 'flat'
      };
    });
    return html`
      <section class="pr360-panel">
        <div class="pr360-panel-head">
          <h2 class="pr360-panel-title">${K.t('ETDEMO_PR360Pending')}</h2>
          <span class="pr360-panel-aside">${d.head.uom}</span>
        </div>
        ${K.bars({
          items: items,
          label: K.t('ETDEMO_PR360Pending'),
          format: function (v) {
            return K.fmt(v, 'qty');
          }
        })}
        <p class="pr360-note">${K.t('ETDEMO_PR360PendingNote')}</p>
      </section>
    `;
  }

  /*
   * El rastro: el movimiento uno por uno, del mas nuevo al mas viejo, con su documento.
   *
   * Cada transaccion de esta base resuelve a exactamente un padre -- 8737 lineas de albaran, 402
   * de conteo, 28 de movimiento y ningun huerfano -- asi que el boton del documento siempre sabe
   * a que ventana ir. La pestana la resolvio el diccionario en SQL, una por clase de documento;
   * si alguna vuelve nula, ese documento se escribe como texto y no como boton.
   */
  var DOCS = {
    shipment: { tab: 'shipmentTab', label: 'ETDEMO_PR360DocShipment' },
    receipt: { tab: 'receiptTab', label: 'ETDEMO_PR360DocReceipt' },
    inventory: { tab: 'inventoryTab', label: 'ETDEMO_PR360DocInventory' },
    movement: { tab: 'movementTab', label: 'ETDEMO_PR360DocMovement' }
  };

  function docCell(row, meta) {
    var spec = DOCS[row.docKind];
    var text = textOf(row.document);
    if (!spec || !text) {
      return html`<span class="pr360-dash">-</span>`;
    }
    var tab = meta ? meta[spec.tab] : null;
    var kind = html`<em class="pr360-sub">${K.t(spec.label)}</em>`;
    if (!tab || !textOf(row.docId)) {
      return html`<span class="pr360-cell-key">${text}</span>${kind}`;
    }
    return html`
      <button type="button" class="pr360-link pr360-cell-key" data-open-doc="${row.docId}"
        data-doc-kind="${row.docKind}">${text}</button>${kind}
    `;
  }

  function trailRegion(state, data, ui) {
    if (!textOf(state.itemId)) {
      return '';
    }
    /*
     * El error del libro lo pinta la region del libro; aqui se calla. Siete paneles del mismo
     * datasource repitiendo la misma caja roja no informan siete veces, informan una vez y
     * ensucian seis.
     */
    var d = data.ledger;
    if (!d || broke(ui, 'ledger')) {
      return '';
    }
    var rows = d.trail || [];
    if (!rows.length) {
      return '';
    }
    var unit = data.item && data.item.head ? data.item.head.uom : '';
    var meta = d.meta || {};
    var page = d.page || {};
    var body = rows.map(function (r) {
      var v = numOf(r.qty) || 0;
      return html`
        <tr>
          <td>${dateText(r.date)}</td>
          <td>${textOf(r.label) || r.type}</td>
          <td class="pr360-num ${v < 0 ? 'pr360-out' : 'pr360-in'}">${dash(r.qty)}
            <span class="pr360-uom">${unit}</span></td>
          <td>${r.warehouse}<em class="pr360-sub">${r.locator}</em></td>
          <td>${docCell(r, meta)}</td>
        </tr>
      `;
    });
    /*
     * La tabla va envuelta en .pr360-scroll, que es el patron de las otras seis vistas: el eje
     * horizontal es de la tabla y no de la region ni del shell. Sus cinco columnas -- fecha, tipo,
     * cifra con unidad, almacen con sitio y documento -- no caben en una ventana estrecha, y sin el
     * envoltorio el desborde no era alcanzable: medido a 768px de ancho, la region pedia 573px
     * contra los 468 que tiene y con overflow-x visible, asi que la columna del documento -- la que
     * lleva al albaran -- la recortaba el shell y no habia gesto que la trajese.
     *
     * El rastro puede permitirselo y la tabla de sitios no: alli el thead es pegajoso contra la
     * region, que es quien desplaza por keepScroll, y meter un scroller intermedio dejaria la
     * cabecera pegada a un contenedor que no se mueve. Esa se queda desplazando la region.
     */
    return html`
      <section class="pr360-panel">
        <div class="pr360-panel-head">
          <h2 class="pr360-panel-title">${K.t('ETDEMO_PR360Trail')}</h2>
          <span class="pr360-panel-aside">${K.t('ETDEMO_PR360PageOf')}
            ${K.fmt(page.page, 'int')} / ${K.fmt(page.pages, 'int')} &middot;
            ${count(page.total, 'ETDEMO_PR360MoveOne', 'ETDEMO_PR360Moves')}</span>
        </div>
        <div class="pr360-scroll">
          <table class="uik-table pr360-table">
            <thead>
              <tr>
                <th>${K.t('ETDEMO_PR360ColDate')}</th>
                <th>${K.t('ETDEMO_PR360ColMovementType')}</th>
                <th class="pr360-num">${K.t('ETDEMO_PR360ColQty')}</th>
                <th>${K.t('ETDEMO_PR360ColPlace')}</th>
                <th>${K.t('ETDEMO_PR360ColDocumentNo')}</th>
              </tr>
            </thead>
            <tbody>${body}</tbody>
          </table>
        </div>
      </section>
    `;
  }

  function trailPagerRegion(state, data, ui) {
    if (!textOf(state.itemId)) {
      return '';
    }
    var d = data.ledger;
    if (!d || broke(ui, 'ledger') || !d.page || !(d.trail || []).length) {
      return '';
    }
    var page = d.page.page;
    var pages = d.page.pages;
    return html`
      <nav class="uik-pager pr360-pager" aria-label="${K.t('ETDEMO_PR360TrailPager')}">
        <button type="button" class="pr360-page" data-tpage="${page - 1}"
          ${page <= 1 ? 'disabled' : ''}>${K.t('ETDEMO_PR360Prev')}</button>
        <span class="pr360-page-of">
          ${K.t('ETDEMO_PR360PageOf')} ${K.fmt(page, 'int')} / ${K.fmt(pages, 'int')}
          &middot; ${count(d.page.total, 'ETDEMO_PR360MoveOne', 'ETDEMO_PR360Moves')}
        </span>
        <button type="button" class="pr360-page" data-tpage="${page + 1}"
          ${page >= pages ? 'disabled' : ''}>${K.t('ETDEMO_PR360Next')}</button>
      </nav>
    `;
  }

  /* ------------------------------------------------------------------ vista */

  K.defineView({
    name: 'ETDEMO_Product360',
    title: 'ETDEMO_PR360Title',

    /*
     * El orden de declaracion es el orden del DOM: identidad, tiempo (el libro), tipo de
     * movimiento (la mezcla, que sale del mismo datasource que el libro), donde esta (almacen y
     * lote, emparejados por el CSS), donde exactamente (los sitios), con que se compara (los
     * pares de su categoria y la cartera abierta) y por ultimo el rastro con su pager.
     *
     * El carril va antes que los paneles porque es el orden en que se tabula y porque en una
     * pantalla estrecha hay que elegir un producto para que lo demas signifique algo; por debajo
     * de 1200px el CSS adelanta la ficha por encima del carril con `order`, para que la respuesta
     * aparezca donde estaba la pregunta.
     */
    regions: ['head', 'bar', 'rail', 'pager', 'hero', 'ledger', 'mix', 'warehouses', 'lots',
      'locators', 'peers', 'pending', 'trail', 'tpager'],
    loading: 'rail',

    /*
     * Solo las dos regiones que desplazan de verdad. Poner aqui una region que no tiene overflow
     * propio no hace nada: uikSetRegion lee el scrollTop DEL NODO DE LA REGION, asi que una
     * promesa sobre una region que crece libremente es letra muerta -- y el CSS acota estas dos
     * precisamente para que la promesa se pueda cumplir.
     */
    keepScroll: ['rail', 'locators'],

    state: {
      q: '',
      categoryId: '',
      warehouseId: '',
      sort: SORT_DEFAULT,
      page: 1,
      limit: LIMIT_DEFAULT,
      itemId: '',
      grain: GRAIN_DEFAULT,
      period: '',
      tpage: 1
    },

    params: function (s) {
      return {
        q: textOf(s.q),
        categoryId: textOf(s.categoryId),
        warehouseId: textOf(s.warehouseId),
        sort: sortOf(s),
        page: pageOf(s.page),
        limit: limitOf(s),
        itemId: textOf(s.itemId),
        grain: grainOf(s),
        period: textOf(s.period),
        tpage: pageOf(s.tpage)
      };
    },

    data: {
      index: {
        source: 'ETDEMO_PR360Index',
        params: function (s) {
          return {
            q: textOf(s.q),
            categoryId: textOf(s.categoryId),
            warehouseId: textOf(s.warehouseId),
            sort: sortOf(s),
            page: pageOf(s.page),
            limit: limitOf(s)
          };
        }
      },
      /*
       * Los ocho paneles del producto vienen de una sola lectura, y eso es deliberado: son ocho
       * cortes del MISMO instante. Pedirlos por separado dejaria la cabecera contando un total y
       * un panel repartiendolo de otra manera si algo se movio entre las dos peticiones.
       */
      item: {
        source: 'ETDEMO_PR360Stock',
        params: function (s) {
          return { itemId: textOf(s.itemId), warehouseId: textOf(s.warehouseId) };
        },
        when: function (s) {
          return !!textOf(s.itemId);
        }
      },
      /*
       * El libro va aparte porque cambia por razones distintas: el grano y la pagina del rastro
       * no tocan ninguno de los ocho paneles, asi que cambiarlos no vuelve a pedirlos.
       */
      ledger: {
        source: 'ETDEMO_PR360Ledger',
        params: function (s) {
          return {
            itemId: textOf(s.itemId),
            warehouseId: textOf(s.warehouseId),
            grain: grainOf(s),
            page: pageOf(s.tpage),
            limit: TRAIL_LIMIT
          };
        },
        when: function (s) {
          return !!textOf(s.itemId);
        }
      }
    },

    render: function (state, data, ui) {
      return {
        head: headRegion(),
        bar: barRegion(state, data, ui),
        rail: railRegion(state, data, ui),
        pager: pagerRegion(state, data, ui),
        hero: heroRegion(state, data, ui),
        ledger: ledgerRegion(state, data, ui),
        warehouses: warehousesRegion(state, data, ui),
        peers: peersRegion(state, data, ui),
        mix: mixRegion(state, data, ui),
        lots: lotsRegion(state, data, ui),
        locators: locatorsRegion(state, data, ui),
        pending: pendingRegion(state, data, ui),
        trail: trailRegion(state, data, ui),
        tpager: trailPagerRegion(state, data, ui)
      };
    },

    on: {
      'input [data-q]': function (ctx, e, el) {
        searcher(ctx)(el.value);
      },
      'click [data-category]': function (ctx, e, el) {
        ctx.set({ categoryId: el.dataset.category, page: 1 });
      },
      /*
       * El almacen mueve dos cosas a la vez: el carril y los ocho paneles. La pagina del rastro
       * vuelve a uno porque bajo otro almacen hay otro numero de movimientos y la pagina siete
       * podria no existir; el periodo elegido se conserva porque la serie va del primer
       * movimiento al ultimo y ese periodo sigue estando, con otras cifras.
       */
      'click [data-warehouse-pick]': function (ctx, e, el) {
        ctx.set({ warehouseId: el.dataset.warehousePick, page: 1, tpage: 1 });
      },
      'click [data-sort]': function (ctx, e, el) {
        ctx.set({ sort: el.dataset.sort, page: 1 });
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
      'click [data-tpage]': function (ctx, e, el) {
        var page = parseInt(el.dataset.tpage, 10);
        if (page >= 1) {
          ctx.set({ tpage: page });
        }
      },
      /*
       * Elegir producto reinicia el rastro y la lectura del periodo: los periodos de un producto
       * no son los del otro, y quedarse con "2016" elegido dejaria una lectura que no aparece en
       * el grafico que se acaba de dibujar.
       */
      'click [data-product]': function (ctx, e, el) {
        ctx.set({ itemId: el.dataset.product, period: '', tpage: 1 });
      },
      'click [data-grain]': function (ctx, e, el) {
        ctx.set({ grain: el.dataset.grain, period: '' });
      },
      /*
       * El periodo es estado de la vista y nada mas: la serie ya vino entera, asi que esto no
       * pide nada al servidor. Tampoco estrecha el rastro -- el rastro se pagina en SQL y no
       * acepta periodo -- y por eso el grafico no dice que lo haga.
       */
      'click [data-period]': function (ctx, e, el) {
        ctx.set({ period: el.dataset.period });
      },
      /*
       * El eje del tiempo se recorre con las flechas, que es como se recorre una serie. Mueve el
       * foco al periodo vecino sin elegirlo: elegir sigue siendo pulsar. El foco se busca en el
       * ancestro de la tira, no en el documento -- la vista no escucha nunca fuera de su raiz.
       */
      'keydown [data-period]': function (ctx, e, el) {
        var step = e.key === 'ArrowRight' ? 1 : (e.key === 'ArrowLeft' ? -1 : 0);
        if (!step) {
          return;
        }
        var strip = el.parentNode;
        var hits = strip ? strip.querySelectorAll('[data-period]') : [];
        var i = Array.prototype.indexOf.call(hits, el) + step;
        if (i >= 0 && i < hits.length) {
          e.preventDefault();
          hits[i].focus();
        }
      },
      'click [data-open]': function (ctx, e, el) {
        // La pestana la resolvio el datasource en SQL. Si vuelve nula el boton no se pinta, asi
        // que aqui solo se llega con una pestana que el diccionario devolvio de verdad.
        K.nav(ctx.data.item.meta.productTab, el.dataset.open);
      },
      /*
       * Una transaccion de esta base resuelve a exactamente un documento, y su clase decide la
       * ventana: albaran, recepcion, conteo o movimiento. Es navegacion de lectura; no pasa por
       * ctx.run y no escribe nada.
       */
      'click [data-open-doc]': function (ctx, e, el) {
        var spec = DOCS[el.dataset.docKind];
        var meta = ctx.data.ledger ? ctx.data.ledger.meta : null;
        K.nav(spec && meta ? meta[spec.tab] : null, el.dataset.openDoc);
      }
    },

    /* The pending search must not fire into a DOM that is already gone. */
    destroy: function (ctx) {
      var fn = searchers.get(ctx.state);
      if (fn) {
        fn.cancel();
        searchers.delete(ctx.state);
      }
    }
  });
})();

</#noparse>
