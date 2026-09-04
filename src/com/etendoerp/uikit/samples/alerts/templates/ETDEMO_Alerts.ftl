<#noparse>
/* ETDEMO_Alerts -- generado por verify/deploy-view.mjs. No editar en base de datos:
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

/* com.etendoerp.uikit.samples/web/com.etendoerp.uikit.samples/css/alerts-inbox.css */
OB.UIKit.style("com.etendoerp.uikit.samples.alerts", "/*\n * ETDEMO_Alerts stylesheet. Everything is scoped under .uik-etdemo_alerts, the class the runtime\n * puts on this window's own root, so nothing here can reach Classic's chrome or another window.\n *\n * The tables, the chips and the status badges are .uik-table, .uik-chip and .uik-badge from\n * uikit.css and are not restyled. What is here is only what an inbox needs and a list does not:\n * a two-column split that puts the filter-independent rail beside the detail it does not follow,\n * a refresh strip that reads as machinery rather than as content, and a rejection line that is\n * impossible to mistake for a heading.\n *\n * Every colour is a --uik-* token. A raw hex here would drift away from the runtime's palette the\n * first time the palette changes, and the window would be the only one on screen that did not.\n */\n\n.uik-etdemo_alerts {\n  --alr-radius: 7px;\n  --alr-gap: 14px;\n}\n\n/* ------------------------------------------------------------------ top bar */\n\n.uik-etdemo_alerts .alr-bar {\n  margin-bottom: var(--alr-gap);\n}\n\n.uik-etdemo_alerts .alr-title {\n  margin: 0;\n  font-size: 16px;\n  font-weight: 600;\n}\n\n/* The provenance line. Section 0 of the doc argues that a reader who does not know these rows\n * were written by a dictionary job will misread every count on the screen, so the claim is on\n * the screen and not only in the doc. */\n.uik-etdemo_alerts .alr-source {\n  margin: 2px 0 0;\n  color: var(--uik-ink-soft);\n  font-size: 12px;\n}\n\n.uik-etdemo_alerts .alr-rates {\n  display: flex;\n  align-items: center;\n  flex-wrap: wrap;\n  gap: 6px;\n  margin-top: 10px;\n  color: var(--uik-ink-soft);\n  font-size: 12px;\n}\n\n/* The asymmetry, said on the screen. The rail counts what the filter excludes, and a reader who\n * has not been told that will read the chips as a contradiction rather than as the feature. */\n.uik-etdemo_alerts .alr-asym {\n  margin: 10px 0 0;\n  padding: 6px 10px;\n  border-left: 3px solid var(--uik-brand);\n  background: var(--uik-surface);\n  color: var(--uik-ink-soft);\n  font-size: 12px;\n}\n\n/* A rejection from the server, and the only red text on the screen that is not a badge. It sits\n * above the rail rather than beside the row, because by the time it is painted the optimistic\n * change has already been rolled back and the row looks untouched again. */\n.uik-etdemo_alerts .alr-note {\n  margin: 10px 0 0;\n  padding: 6px 10px;\n  border: 1px solid var(--uik-line);\n  border-radius: var(--alr-radius);\n  background: var(--uik-surface);\n  font-size: 12px;\n}\n\n/* -------------------------------------------------------------------- rail */\n\n.uik-etdemo_alerts .alr-chips {\n  display: flex;\n  flex-wrap: wrap;\n  gap: 6px;\n  margin-bottom: 10px;\n}\n\n.uik-etdemo_alerts .alr-chips b {\n  margin-left: 4px;\n  font-variant-numeric: tabular-nums;\n}\n\n.uik-etdemo_alerts .alr-rail,\n.uik-etdemo_alerts .alr-list {\n  padding: 12px 14px;\n  border: 1px solid var(--uik-line);\n  border-radius: var(--alr-radius);\n  background: var(--uik-surface);\n}\n\n.uik-etdemo_alerts .alr-rail {\n  margin-bottom: var(--alr-gap);\n}\n\n/* The rule name is a chip inside a table cell, so it must not stretch the column: a long rule\n * name wraps inside the chip rather than pushing the counts off the right edge. */\n.uik-etdemo_alerts .alr-rail .uik-chip {\n  max-width: 42ch;\n  white-space: normal;\n  text-align: left;\n}\n\n/* ------------------------------------------------------------------- list */\n\n.uik-etdemo_alerts .alr-list td:first-child {\n  max-width: 52ch;\n}\n\n.uik-etdemo_alerts .alr-list a {\n  color: var(--uik-brand);\n  text-decoration: none;\n}\n\n.uik-etdemo_alerts .alr-list a:hover {\n  text-decoration: underline;\n}\n\n.uik-etdemo_alerts .alr-empty {\n  margin: 0;\n  padding: 18px 20px;\n  border: 1px dashed var(--uik-line);\n  border-radius: var(--alr-radius);\n  background: var(--uik-surface);\n  color: var(--uik-ink-soft);\n}\n\n/* The acknowledge button is a chip, but it is the only chip on the screen that changes data, so\n * it reads as an action instead of as a filter. */\n.uik-etdemo_alerts .alr-list .uik-chip[data-ack] {\n  border-color: color-mix(in srgb, var(--uik-brand) 45%, var(--uik-line));\n  color: var(--uik-brand);\n  font-weight: 600;\n}\n\n/* uik-busy already blocks pointer events on every region while a request is in flight; this only\n * makes the pending row look like the reason. */\n.uik-etdemo_alerts.uik-busy .alr-list .uik-chip[data-ack] {\n  color: var(--uik-flat);\n  border-color: var(--uik-line);\n}\n");

/* AD_MESSAGE */
OB.UIKit.labels({"ETDEMO_AlertsAck":"Revisar","ETDEMO_AlertsAcked":"Revisada","ETDEMO_AlertsAckFailed":"No se pudo revisar la alerta; se ha restaurado el estado anterior.","ETDEMO_AlertsACKNOWLEDGED":"Revisadas","ETDEMO_AlertsAll":"Todas","ETDEMO_AlertsBadTransition":"Solo se puede revisar una alerta nueva. Estado actual:","ETDEMO_AlertsColAction":"Acción","ETDEMO_AlertsColAlert":"Alerta","ETDEMO_AlertsColCreated":"Creada","ETDEMO_AlertsColOrg":"Organización","ETDEMO_AlertsDetailHead":"Detalle","ETDEMO_AlertsEmpty":"No hay alertas con este filtro.","ETDEMO_AlertsNEW":"Nuevas","ETDEMO_AlertsNoRules":"Este rol no tiene ninguna alerta visible.","ETDEMO_AlertsNoTab":"Sin ventana asociada","ETDEMO_AlertsNotVisible":"La alerta no existe o no es visible para este rol.","ETDEMO_AlertsOpen":"Abrir registro","ETDEMO_AlertsPause":"Pausar refresco","ETDEMO_AlertsRailNote":"Los recuentos por estado y por regla se calculan sobre todas las alertas visibles, sin mirar el filtro activo.","ETDEMO_AlertsRefreshEvery":"Refresco automático cada","ETDEMO_AlertsReloadNow":"Actualizar ahora","ETDEMO_AlertsResume":"Reanudar refresco","ETDEMO_AlertsRuleHead":"Regla","ETDEMO_AlertsSeconds":"segundos","ETDEMO_AlertsSOLVED":"Resueltas","ETDEMO_AlertsSource":"Alertas generadas por reglas del diccionario, no por la operación diaria.","ETDEMO_AlertsStatusHead":"Estado","ETDEMO_AlertsSUPPRESSED":"Silenciadas","ETDEMO_AlertsTitle":"Bandeja de alertas del administrador","ETDEMO_AlertsTotal":"Alertas visibles","ETDEMO_AlertsTruncated":"Lista recortada al límite de filas; ajusta el filtro para ver el resto.","ETDEMO_CashAging":"Antigüedad de la cartera","ETDEMO_CashAgingAria":"Antigüedad de la cartera por tramo","ETDEMO_CashAgingNote":"Los totales por tramo se calculan sobre toda la cartera del lado, sin mirar el tramo seleccionado.","ETDEMO_CashAP":"Pagos a proveedores","ETDEMO_CashAR":"Cobros de clientes","ETDEMO_CashAsOf":"Fecha de referencia","ETDEMO_CashBucketAll":"Todos los tramos","ETDEMO_CashBucketCur":"Sin vencer","ETDEMO_CashBucketD30":"1 a 30 días","ETDEMO_CashBucketD60":"31 a 60 días","ETDEMO_CashBucketD90":"61 a 90 días","ETDEMO_CashBucketD90p":"Más de 90 días","ETDEMO_CashColDays":"Días","ETDEMO_CashColDoc":"Documento","ETDEMO_CashColDocs":"Docs.","ETDEMO_CashColDue":"Vencimiento","ETDEMO_CashColInvoiced":"Fecha de factura","ETDEMO_CashColOldest":"Vencimiento más antiguo","ETDEMO_CashColOutstanding":"Pendiente","ETDEMO_CashColPartner":"Tercero","ETDEMO_CashCurrenciesWord":"monedas","ETDEMO_CashCurrency":"Moneda","ETDEMO_CashDaysOverdue":"días vencido","ETDEMO_CashDetail":"Detalle por tercero","ETDEMO_CashDocsWord":"documentos","ETDEMO_CashDueRange":"vencimientos","ETDEMO_CashEmpty":"No hay documentos pendientes con este filtro.","ETDEMO_CashEmptySide":"Esta cartera no tiene ningún documento pendiente dentro del ámbito del rol.","ETDEMO_CashExcludedNote":"documento(s) en otras monedas no se muestran","ETDEMO_CashFromData":"último vencimiento del dato","ETDEMO_CashFromParam":"indicada en la petición","ETDEMO_CashFromToday":"hoy del servidor","ETDEMO_CashNoTab":"sin ventana de factura resoluble","ETDEMO_CashNotDue":"sin vencer","ETDEMO_CashOneCurrency":"Una sola moneda a la vez: sumar monedas distintas da un número sin significado.","ETDEMO_CashPartnersWord":"terceros","ETDEMO_CashSeriesAP":"Pagos liquidados, 12 meses","ETDEMO_CashSeriesAR":"Cobros liquidados, 12 meses","ETDEMO_CashSeriesAria":"Serie mensual de caja de los últimos doce meses","ETDEMO_CashSeriesNote":"fin_payment es la única serie densa de esta instancia; los meses sin pagos se rellenan en Java.","ETDEMO_CashSideGroup":"Cartera","ETDEMO_CashTitle":"Cartera de cobros y pagos","ETDEMO_CashTotalLabel":"Total de la cartera","ETDEMO_CashWhySide":"El encargo original pedía un cuadro de cobros. En esta instancia los cobros están muertos y los pagos vivos, así que la pantalla abre en pagos y lo dice en vez de esconderlo: el conmutador cambia de lado en un clic.","ETDEMO_P360Amount":"Importe","ETDEMO_P360Count":"Nº","ETDEMO_P360Customer":"Cliente","ETDEMO_P360Date":"Fecha","ETDEMO_P360Directory":"Directorio","ETDEMO_P360DirEmpty":"Ningún tercero coincide con la búsqueda.","ETDEMO_P360DocNo":"Nº documento","ETDEMO_P360Docs":"documentos","ETDEMO_P360DocsEmpty":"Este tercero no tiene documentos de este tipo.","ETDEMO_P360Documents":"Documentos","ETDEMO_P360Last":"Último","ETDEMO_P360LazyNote":"El directorio se carga una vez; la ficha y la lista de documentos solo cuando hacen falta.","ETDEMO_P360Mixed":"varias monedas","ETDEMO_P360Next":"Siguiente","ETDEMO_P360Of":"de","ETDEMO_P360OpenDoc":"Abrir el documento","ETDEMO_P360OpenPartner":"Abrir la ficha del tercero","ETDEMO_P360Page":"Página","ETDEMO_P360Partner":"Tercero","ETDEMO_P360Partners":"terceros","ETDEMO_P360Pick":"Elige un tercero del directorio para ver su ficha.","ETDEMO_P360Prev":"Anterior","ETDEMO_P360ScopeNote":"Solo documentos de las organizaciones que tu rol puede leer.","ETDEMO_P360Search":"Buscar tercero","ETDEMO_P360Status":"Estado","ETDEMO_P360Summary":"Resumen","ETDEMO_P360TabPI":"Facturas de compra","ETDEMO_P360TabPM":"Pagos","ETDEMO_P360TabPO":"Pedidos de compra","ETDEMO_P360TabRC":"Cobros","ETDEMO_P360Tabs":"Tipos de documento","ETDEMO_P360TabSI":"Facturas de venta","ETDEMO_P360TabSO":"Pedidos de venta","ETDEMO_P360TaxId":"NIF","ETDEMO_P360Title":"Tercero 360","ETDEMO_P360Total":"Total","ETDEMO_P360TotalsNote":"Los totales por pestaña se calculan sobre todos los documentos del tercero, sin mirar la pestaña activa.","ETDEMO_P360Vendor":"Proveedor","ETDEMO_PickingActCO":"Confirmar","ETDEMO_PickingActRE":"Reabrir","ETDEMO_PickingAfter":"Después","ETDEMO_PickingAll":"Todos","ETDEMO_PickingApplied":"Aplicado","ETDEMO_PickingArm":"Armar ejecución real","ETDEMO_PickingArmed":"Armado: el siguiente clic modifica el pedido en el ERP","ETDEMO_PickingAsk":"Vas a modificar este pedido en el ERP. ¿Continuar?","ETDEMO_PickingAsOf":"Datos a fecha","ETDEMO_PickingBadAction":"Esta ventana no ejecuta la acción pedida por el navegador:","ETDEMO_PickingBadTransition":"Esta ventana solo confirma borradores y reabre completados. Estado actual:","ETDEMO_PickingBefore":"Antes","ETDEMO_PickingChoose":"Elige un pedido de la lista para ver sus líneas","ETDEMO_PickingCL":"Cerrado","ETDEMO_PickingCO":"Completado","ETDEMO_PickingCoreAllows":"El ERP admite ahora","ETDEMO_PickingCustomer":"Cliente","ETDEMO_PickingDate":"Fecha","ETDEMO_PickingDelivered":"Entregada","ETDEMO_PickingDisarm":"Desarmar","ETDEMO_PickingDR":"Borrador","ETDEMO_PickingDry":"Simular","ETDEMO_PickingDryDone":"Simulación completada: no se ha modificado nada","ETDEMO_PickingDryHint":"La simulación no modifica nada","ETDEMO_PickingErpError":"El ERP ha rechazado la acción.","ETDEMO_PickingErpSaid":"El ERP responde","ETDEMO_PickingGo":"Ejecutar de verdad","ETDEMO_PickingGone":"Ese pedido ya no está visible para tu rol","ETDEMO_PickingIdle":"Todavía no has intentado nada en esta sesión","ETDEMO_PickingIntro":"Pedidos de venta listos para confirmar. Simula antes de ejecutar.","ETDEMO_PickingLine":"Línea","ETDEMO_PickingLines":"Líneas del pedido","ETDEMO_PickingMatched":"coincidencias","ETDEMO_PickingNext":"Siguientes","ETDEMO_PickingNoAction":"Este estado no admite ninguna acción en esta ventana","ETDEMO_PickingNoLines":"Este pedido no tiene líneas","ETDEMO_PickingNoOrders":"Ningún pedido coincide con el filtro","ETDEMO_PickingNotVisible":"Ese pedido no existe o no es visible para tu rol.","ETDEMO_PickingOnHand":"En almacén","ETDEMO_PickingOpenOrder":"Abrir el pedido en su ventana","ETDEMO_PickingOrdered":"Pedida","ETDEMO_PickingOrders":"Pedidos","ETDEMO_PickingPending":"Pendiente","ETDEMO_PickingPrev":"Anteriores","ETDEMO_PickingProduct":"Producto","ETDEMO_PickingRejected":"Rechazado","ETDEMO_PickingResult":"Último intento","ETDEMO_PickingSearch":"Número de pedido o cliente","ETDEMO_PickingSending":"Enviando...","ETDEMO_PickingServices":"de servicio","ETDEMO_PickingSimulated":"Simulado","ETDEMO_PickingStatus":"Estado","ETDEMO_PickingStocked":"líneas de almacén","ETDEMO_PickingTitle":"Preparación de pedidos","ETDEMO_PickingToneDone":"Nada pendiente","ETDEMO_PickingToneNa":"Servicio","ETDEMO_PickingToneOk":"Cubierta","ETDEMO_PickingTonePartial":"Parcial","ETDEMO_PickingToneShort":"Sin stock","ETDEMO_PickingTotal":"Total","ETDEMO_PickingUnchanged":"Sin cambios","ETDEMO_PickingVO":"Anulado","ETDEMO_PickingWarehouse":"Almacén","ETDEMO_PickingWouldRun":"Se ejecutaría la acción","ETDEMO_StockAxisNote":"El eje de almacenes ignora la búsqueda y la paginación.","ETDEMO_StockColTotals":"Total por almacén","ETDEMO_StockEmpty":"Ningún producto coincide con la búsqueda.","ETDEMO_StockGrand":"Total general","ETDEMO_StockNext":"Siguiente","ETDEMO_StockOf":"de","ETDEMO_StockOpenProduct":"Abrir la ficha del producto","ETDEMO_StockPage":"Página","ETDEMO_StockPageSize":"por página","ETDEMO_StockPrev":"Anterior","ETDEMO_StockProduct":"Producto","ETDEMO_StockProducts":"productos","ETDEMO_StockScopeNote":"Los totales por almacén cubren todo el conjunto filtrado, no solo la página visible.","ETDEMO_StockSearch":"Buscar por código o nombre de producto","ETDEMO_StockSort":"Ordenar por","ETDEMO_StockSortCode":"código","ETDEMO_StockSortName":"nombre","ETDEMO_StockSortQty":"cantidad","ETDEMO_StockTitle":"Stock por producto y almacén","ETDEMO_StockTotal":"Total","ETDEMO_StockUom":"UdM","ETDEMO_StockWarehouses":"almacenes","ETDEMO_StockZeros":"Incluir total cero","ETUIK_LoadFailed":"No se pudieron cargar los datos","ETUIK_Loading":"Cargando…","ETUIK_MeterAria":"Puntuación %{score} sobre un objetivo de %{target}","ETUIK_RailAria":"Avance %{progress}%, esperado %{expected}%"});

/* com.etendoerp.uikit.samples/web/com.etendoerp.uikit.samples/js/alerts-inbox.js */
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

</#noparse>
