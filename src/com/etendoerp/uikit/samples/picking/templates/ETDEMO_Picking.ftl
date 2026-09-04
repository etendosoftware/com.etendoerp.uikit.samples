<#noparse>
/* ETDEMO_Picking -- generado por verify/deploy-view.mjs. No editar en base de datos:
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

/* com.etendoerp.uikit.samples/web/com.etendoerp.uikit.samples/css/picking.css */
OB.UIKit.style("com.etendoerp.uikit.samples.picking", "/*\n * ETDEMO_Picking stylesheet. Everything is scoped under .uik-etdemo_picking, the class the\n * runtime puts on this window's own root, so nothing here can reach Classic's chrome or another\n * uikit window.\n *\n * The tables, the chips, the pager, the badges and the meter are .uik-table, .uik-chip,\n * .uik-pager, .uik-badge and .uik-meter from uikit.css and are not restyled. What is here is only\n * what a screen that can change a document needs and a read-only list does not:\n *\n *  - a two-column split that puts the order selector beside the line detail, because the reader\n *    picks an order and then reads its lines, and losing the list on every click would make the\n *    comparison the screen exists for impossible;\n *  - a visual gap between the simulate control and the armed one wide enough that no click\n *    intended for the first can land on the second, plus a colour for the armed button that\n *    exists nowhere else in the kit;\n *  - a line row tinted by the semaphore its own datasource computed, so the eye finds the short\n *    line before it reads the numbers.\n *\n * Every colour is a --uik-* token. A raw hex here would drift away from the runtime's palette the\n * first time the palette changes, and this window would be the only one on screen that did not.\n */\n\n.uik-etdemo_picking {\n  --pck-radius: 7px;\n  --pck-gap: 14px;\n}\n\n/* ------------------------------------------------------------------ the bar */\n\n.uik-etdemo_picking .pck-bar {\n  margin-bottom: var(--pck-gap);\n  padding-bottom: 10px;\n  border-bottom: 1px solid var(--uik-line);\n}\n\n.uik-etdemo_picking .pck-title {\n  margin: 0;\n  font-size: 16px;\n  font-weight: 600;\n}\n\n.uik-etdemo_picking .pck-intro,\n.uik-etdemo_picking .pck-asof {\n  margin: 2px 0 0;\n  font-size: 12px;\n  color: var(--uik-ink-soft);\n}\n\n.uik-etdemo_picking .pck-target {\n  display: flex;\n  align-items: center;\n  gap: 8px;\n  margin-top: 8px;\n  font-size: 13px;\n}\n\n.uik-etdemo_picking .pck-result {\n  margin: var(--pck-gap) 0 4px;\n  font-size: 12px;\n  font-weight: 600;\n  text-transform: uppercase;\n  letter-spacing: 0.04em;\n  color: var(--uik-ink-soft);\n}\n\n/* --------------------------------------------------------- simulate and arm */\n\n.uik-etdemo_picking .pck-controls {\n  display: flex;\n  align-items: center;\n  flex-wrap: wrap;\n  gap: 10px;\n  margin-top: 10px;\n}\n\n/* The simulation is the primary control, so it is the one that looks like a button you press\n * without thinking. That is the correct habit to build: it cannot change anything. */\n.uik-etdemo_picking .pck-dry {\n  font-weight: 600;\n  border-color: var(--uik-brand);\n  color: var(--uik-brand);\n}\n\n/* The armed strip. Its left border and tint say this row is not the row that was here a\n * moment ago, the only warning that survives a reader who never reads warnings. */\n.uik-etdemo_picking .pck-live {\n  padding: 8px 10px;\n  border-left: 3px solid var(--uik-bad);\n  border-radius: var(--pck-radius);\n  background: color-mix(in srgb, var(--uik-bad) 8%, var(--uik-surface));\n}\n\n/* The one control in the kit that mutates an ERP document, and the only filled-danger button in\n * it. The extra margin is not decoration: it is the distance a mis-aimed click has to cross. */\n.uik-etdemo_picking .pck-danger {\n  margin-left: 12px;\n  padding: 5px 14px;\n  border: 1px solid var(--uik-bad);\n  border-radius: var(--pck-radius);\n  background: var(--uik-bad);\n  color: var(--uik-surface);\n  font-weight: 700;\n  cursor: pointer;\n}\n\n.uik-etdemo_picking .pck-danger:hover {\n  filter: brightness(0.92);\n}\n\n.uik-etdemo_picking .pck-armed,\n.uik-etdemo_picking .pck-hint {\n  font-size: 12px;\n}\n\n/* ------------------------------------------------------------- the verdict */\n\n.uik-etdemo_picking .pck-verdict {\n  display: flex;\n  align-items: center;\n  flex-wrap: wrap;\n  gap: 8px;\n  font-size: 13px;\n}\n\n.uik-etdemo_picking .pck-delta,\n.uik-etdemo_picking .pck-allowed,\n.uik-etdemo_picking .pck-erp {\n  display: inline-flex;\n  align-items: center;\n  gap: 6px;\n  font-size: 12px;\n}\n\n/* The ERP's own sentence, marked as a quotation because that is what it is: core's words, not\n * this window's. Nothing restyles it into a heading or an alert. */\n.uik-etdemo_picking .pck-msg {\n  font-style: normal;\n  padding: 2px 8px;\n  border-left: 2px solid var(--uik-line);\n  color: var(--uik-ink);\n}\n\n.uik-etdemo_picking .pck-fail .pck-msg {\n  border-left-color: var(--uik-bad);\n}\n\n/* ------------------------------------------------- selector beside detail */\n\n.uik-etdemo_picking {\n  display: grid;\n  grid-template-columns: minmax(320px, 42%) minmax(0, 1fr);\n  grid-template-areas: 'bar bar' 'list detail';\n  gap: 0 var(--pck-gap);\n  align-items: start;\n}\n\n.uik-etdemo_picking .uik-region-bar {\n  grid-area: bar;\n}\n\n.uik-etdemo_picking .uik-region-list {\n  grid-area: list;\n  min-width: 0;\n  max-height: 62vh;\n  overflow: auto;\n}\n\n/*\n * Both tables are wide -- seven columns in the selector, eight in the line list -- and each one\n * scrolls inside its own region rather than pushing the page sideways. Without this the line table\n * simply spilled out of a 351px detail pane: overflow-x defaults to visible, so the columns were\n * drawn outside the panel with no way to reach them.\n */\n.uik-etdemo_picking .uik-region-detail {\n  grid-area: detail;\n  min-width: 0;\n  overflow-x: auto;\n}\n\n/*\n * Side by side needs about 1490px of content width: the selector wants ~775 and the line list\n * ~685. Below that the two tracks only clip each other, and a column the reader cannot see is a\n * worse outcome than a scroll -- so up to 1500px viewport the regions stack and each one gets the\n * full width it asks for. Above it, the documented selector-beside-detail layout applies.\n */\n@media (max-width: 1500px) {\n  .uik-etdemo_picking {\n    grid-template-columns: minmax(0, 1fr);\n    grid-template-areas: 'bar' 'list' 'detail';\n  }\n\n  .uik-etdemo_picking .uik-region-list {\n    max-height: none;\n  }\n}\n\n/* ----------------------------------------------------------------- selector */\n\n.uik-etdemo_picking .pck-chips {\n  display: flex;\n  flex-wrap: wrap;\n  gap: 6px;\n  margin-bottom: 8px;\n}\n\n.uik-etdemo_picking .pck-input {\n  width: 100%;\n  box-sizing: border-box;\n  margin-bottom: 8px;\n  padding: 5px 8px;\n  border: 1px solid var(--uik-line);\n  border-radius: var(--pck-radius);\n  background: var(--uik-surface);\n  color: var(--uik-ink);\n  font: inherit;\n}\n\n/* The order number is a control, not a link: it changes this screen's selection and navigates\n * nowhere, so it must not look like the drill-down in the detail header, which does. */\n.uik-etdemo_picking .pck-pick {\n  padding: 0;\n  border: 0;\n  background: none;\n  color: var(--uik-brand);\n  font: inherit;\n  font-weight: 600;\n  cursor: pointer;\n}\n\n.uik-etdemo_picking tr[aria-selected='true'] {\n  background: color-mix(in srgb, var(--uik-brand) 10%, var(--uik-surface));\n}\n\n.uik-etdemo_picking .pck-next {\n  font-size: 12px;\n  font-weight: 600;\n  color: var(--uik-ink-soft);\n}\n\n.uik-etdemo_picking .pck-matched,\n.uik-etdemo_picking .pck-none {\n  font-size: 12px;\n  color: var(--uik-ink-soft);\n}\n\n.uik-etdemo_picking .pck-none {\n  margin: 8px 0;\n}\n\n/* ------------------------------------------------------------- line detail */\n\n.uik-etdemo_picking .pck-head {\n  display: flex;\n  align-items: center;\n  flex-wrap: wrap;\n  gap: 10px;\n  font-size: 13px;\n}\n\n.uik-etdemo_picking .pck-sem {\n  display: flex;\n  align-items: center;\n  flex-wrap: wrap;\n  gap: 8px;\n  margin: 10px 0;\n  font-size: 12px;\n}\n\n/* The semaphore, tinted from the tone the datasource computed. A service line is grey rather\n * than green: it has no stock to be short of, and painting it as available would claim an\n * availability nobody measured. */\n.uik-etdemo_picking .pck-lines tr[data-tone='ok'] {\n  background: color-mix(in srgb, var(--uik-ok) 7%, transparent);\n}\n\n.uik-etdemo_picking .pck-lines tr[data-tone='partial'] {\n  background: color-mix(in srgb, var(--uik-risk) 9%, transparent);\n}\n\n.uik-etdemo_picking .pck-lines tr[data-tone='short'] {\n  background: color-mix(in srgb, var(--uik-bad) 9%, transparent);\n}\n\n.uik-etdemo_picking .pck-lines tr[data-tone='na'] td {\n  color: var(--uik-ink-soft);\n}\n");

/* AD_MESSAGE */
OB.UIKit.labels({"ETDEMO_AlertsAck":"Revisar","ETDEMO_AlertsAcked":"Revisada","ETDEMO_AlertsAckFailed":"No se pudo revisar la alerta; se ha restaurado el estado anterior.","ETDEMO_AlertsACKNOWLEDGED":"Revisadas","ETDEMO_AlertsAll":"Todas","ETDEMO_AlertsBadTransition":"Solo se puede revisar una alerta nueva. Estado actual:","ETDEMO_AlertsColAction":"Acción","ETDEMO_AlertsColAlert":"Alerta","ETDEMO_AlertsColCreated":"Creada","ETDEMO_AlertsColOrg":"Organización","ETDEMO_AlertsDetailHead":"Detalle","ETDEMO_AlertsEmpty":"No hay alertas con este filtro.","ETDEMO_AlertsNEW":"Nuevas","ETDEMO_AlertsNoRules":"Este rol no tiene ninguna alerta visible.","ETDEMO_AlertsNoTab":"Sin ventana asociada","ETDEMO_AlertsNotVisible":"La alerta no existe o no es visible para este rol.","ETDEMO_AlertsOpen":"Abrir registro","ETDEMO_AlertsPause":"Pausar refresco","ETDEMO_AlertsRailNote":"Los recuentos por estado y por regla se calculan sobre todas las alertas visibles, sin mirar el filtro activo.","ETDEMO_AlertsRefreshEvery":"Refresco automático cada","ETDEMO_AlertsReloadNow":"Actualizar ahora","ETDEMO_AlertsResume":"Reanudar refresco","ETDEMO_AlertsRuleHead":"Regla","ETDEMO_AlertsSeconds":"segundos","ETDEMO_AlertsSOLVED":"Resueltas","ETDEMO_AlertsSource":"Alertas generadas por reglas del diccionario, no por la operación diaria.","ETDEMO_AlertsStatusHead":"Estado","ETDEMO_AlertsSUPPRESSED":"Silenciadas","ETDEMO_AlertsTitle":"Bandeja de alertas del administrador","ETDEMO_AlertsTotal":"Alertas visibles","ETDEMO_AlertsTruncated":"Lista recortada al límite de filas; ajusta el filtro para ver el resto.","ETDEMO_CashAging":"Antigüedad de la cartera","ETDEMO_CashAgingAria":"Antigüedad de la cartera por tramo","ETDEMO_CashAgingNote":"Los totales por tramo se calculan sobre toda la cartera del lado, sin mirar el tramo seleccionado.","ETDEMO_CashAP":"Pagos a proveedores","ETDEMO_CashAR":"Cobros de clientes","ETDEMO_CashAsOf":"Fecha de referencia","ETDEMO_CashBucketAll":"Todos los tramos","ETDEMO_CashBucketCur":"Sin vencer","ETDEMO_CashBucketD30":"1 a 30 días","ETDEMO_CashBucketD60":"31 a 60 días","ETDEMO_CashBucketD90":"61 a 90 días","ETDEMO_CashBucketD90p":"Más de 90 días","ETDEMO_CashColDays":"Días","ETDEMO_CashColDoc":"Documento","ETDEMO_CashColDocs":"Docs.","ETDEMO_CashColDue":"Vencimiento","ETDEMO_CashColInvoiced":"Fecha de factura","ETDEMO_CashColOldest":"Vencimiento más antiguo","ETDEMO_CashColOutstanding":"Pendiente","ETDEMO_CashColPartner":"Tercero","ETDEMO_CashCurrenciesWord":"monedas","ETDEMO_CashCurrency":"Moneda","ETDEMO_CashDaysOverdue":"días vencido","ETDEMO_CashDetail":"Detalle por tercero","ETDEMO_CashDocsWord":"documentos","ETDEMO_CashDueRange":"vencimientos","ETDEMO_CashEmpty":"No hay documentos pendientes con este filtro.","ETDEMO_CashEmptySide":"Esta cartera no tiene ningún documento pendiente dentro del ámbito del rol.","ETDEMO_CashExcludedNote":"documento(s) en otras monedas no se muestran","ETDEMO_CashFromData":"último vencimiento del dato","ETDEMO_CashFromParam":"indicada en la petición","ETDEMO_CashFromToday":"hoy del servidor","ETDEMO_CashNoTab":"sin ventana de factura resoluble","ETDEMO_CashNotDue":"sin vencer","ETDEMO_CashOneCurrency":"Una sola moneda a la vez: sumar monedas distintas da un número sin significado.","ETDEMO_CashPartnersWord":"terceros","ETDEMO_CashSeriesAP":"Pagos liquidados, 12 meses","ETDEMO_CashSeriesAR":"Cobros liquidados, 12 meses","ETDEMO_CashSeriesAria":"Serie mensual de caja de los últimos doce meses","ETDEMO_CashSeriesNote":"fin_payment es la única serie densa de esta instancia; los meses sin pagos se rellenan en Java.","ETDEMO_CashSideGroup":"Cartera","ETDEMO_CashTitle":"Cartera de cobros y pagos","ETDEMO_CashTotalLabel":"Total de la cartera","ETDEMO_CashWhySide":"El encargo original pedía un cuadro de cobros. En esta instancia los cobros están muertos y los pagos vivos, así que la pantalla abre en pagos y lo dice en vez de esconderlo: el conmutador cambia de lado en un clic.","ETDEMO_P360Amount":"Importe","ETDEMO_P360Count":"Nº","ETDEMO_P360Customer":"Cliente","ETDEMO_P360Date":"Fecha","ETDEMO_P360Directory":"Directorio","ETDEMO_P360DirEmpty":"Ningún tercero coincide con la búsqueda.","ETDEMO_P360DocNo":"Nº documento","ETDEMO_P360Docs":"documentos","ETDEMO_P360DocsEmpty":"Este tercero no tiene documentos de este tipo.","ETDEMO_P360Documents":"Documentos","ETDEMO_P360Last":"Último","ETDEMO_P360LazyNote":"El directorio se carga una vez; la ficha y la lista de documentos solo cuando hacen falta.","ETDEMO_P360Mixed":"varias monedas","ETDEMO_P360Next":"Siguiente","ETDEMO_P360Of":"de","ETDEMO_P360OpenDoc":"Abrir el documento","ETDEMO_P360OpenPartner":"Abrir la ficha del tercero","ETDEMO_P360Page":"Página","ETDEMO_P360Partner":"Tercero","ETDEMO_P360Partners":"terceros","ETDEMO_P360Pick":"Elige un tercero del directorio para ver su ficha.","ETDEMO_P360Prev":"Anterior","ETDEMO_P360ScopeNote":"Solo documentos de las organizaciones que tu rol puede leer.","ETDEMO_P360Search":"Buscar tercero","ETDEMO_P360Status":"Estado","ETDEMO_P360Summary":"Resumen","ETDEMO_P360TabPI":"Facturas de compra","ETDEMO_P360TabPM":"Pagos","ETDEMO_P360TabPO":"Pedidos de compra","ETDEMO_P360TabRC":"Cobros","ETDEMO_P360Tabs":"Tipos de documento","ETDEMO_P360TabSI":"Facturas de venta","ETDEMO_P360TabSO":"Pedidos de venta","ETDEMO_P360TaxId":"NIF","ETDEMO_P360Title":"Tercero 360","ETDEMO_P360Total":"Total","ETDEMO_P360TotalsNote":"Los totales por pestaña se calculan sobre todos los documentos del tercero, sin mirar la pestaña activa.","ETDEMO_P360Vendor":"Proveedor","ETDEMO_PickingActCO":"Confirmar","ETDEMO_PickingActRE":"Reabrir","ETDEMO_PickingAfter":"Después","ETDEMO_PickingAll":"Todos","ETDEMO_PickingApplied":"Aplicado","ETDEMO_PickingArm":"Armar ejecución real","ETDEMO_PickingArmed":"Armado: el siguiente clic modifica el pedido en el ERP","ETDEMO_PickingAsk":"Vas a modificar este pedido en el ERP. ¿Continuar?","ETDEMO_PickingAsOf":"Datos a fecha","ETDEMO_PickingBadAction":"Esta ventana no ejecuta la acción pedida por el navegador:","ETDEMO_PickingBadTransition":"Esta ventana solo confirma borradores y reabre completados. Estado actual:","ETDEMO_PickingBefore":"Antes","ETDEMO_PickingChoose":"Elige un pedido de la lista para ver sus líneas","ETDEMO_PickingCL":"Cerrado","ETDEMO_PickingCO":"Completado","ETDEMO_PickingCoreAllows":"El ERP admite ahora","ETDEMO_PickingCustomer":"Cliente","ETDEMO_PickingDate":"Fecha","ETDEMO_PickingDelivered":"Entregada","ETDEMO_PickingDisarm":"Desarmar","ETDEMO_PickingDR":"Borrador","ETDEMO_PickingDry":"Simular","ETDEMO_PickingDryDone":"Simulación completada: no se ha modificado nada","ETDEMO_PickingDryHint":"La simulación no modifica nada","ETDEMO_PickingErpError":"El ERP ha rechazado la acción.","ETDEMO_PickingErpSaid":"El ERP responde","ETDEMO_PickingGo":"Ejecutar de verdad","ETDEMO_PickingGone":"Ese pedido ya no está visible para tu rol","ETDEMO_PickingIdle":"Todavía no has intentado nada en esta sesión","ETDEMO_PickingIntro":"Pedidos de venta listos para confirmar. Simula antes de ejecutar.","ETDEMO_PickingLine":"Línea","ETDEMO_PickingLines":"Líneas del pedido","ETDEMO_PickingMatched":"coincidencias","ETDEMO_PickingNext":"Siguientes","ETDEMO_PickingNoAction":"Este estado no admite ninguna acción en esta ventana","ETDEMO_PickingNoLines":"Este pedido no tiene líneas","ETDEMO_PickingNoOrders":"Ningún pedido coincide con el filtro","ETDEMO_PickingNotVisible":"Ese pedido no existe o no es visible para tu rol.","ETDEMO_PickingOnHand":"En almacén","ETDEMO_PickingOpenOrder":"Abrir el pedido en su ventana","ETDEMO_PickingOrdered":"Pedida","ETDEMO_PickingOrders":"Pedidos","ETDEMO_PickingPending":"Pendiente","ETDEMO_PickingPrev":"Anteriores","ETDEMO_PickingProduct":"Producto","ETDEMO_PickingRejected":"Rechazado","ETDEMO_PickingResult":"Último intento","ETDEMO_PickingSearch":"Número de pedido o cliente","ETDEMO_PickingSending":"Enviando...","ETDEMO_PickingServices":"de servicio","ETDEMO_PickingSimulated":"Simulado","ETDEMO_PickingStatus":"Estado","ETDEMO_PickingStocked":"líneas de almacén","ETDEMO_PickingTitle":"Preparación de pedidos","ETDEMO_PickingToneDone":"Nada pendiente","ETDEMO_PickingToneNa":"Servicio","ETDEMO_PickingToneOk":"Cubierta","ETDEMO_PickingTonePartial":"Parcial","ETDEMO_PickingToneShort":"Sin stock","ETDEMO_PickingTotal":"Total","ETDEMO_PickingUnchanged":"Sin cambios","ETDEMO_PickingVO":"Anulado","ETDEMO_PickingWarehouse":"Almacén","ETDEMO_PickingWouldRun":"Se ejecutaría la acción","ETDEMO_StockAxisNote":"El eje de almacenes ignora la búsqueda y la paginación.","ETDEMO_StockColTotals":"Total por almacén","ETDEMO_StockEmpty":"Ningún producto coincide con la búsqueda.","ETDEMO_StockGrand":"Total general","ETDEMO_StockNext":"Siguiente","ETDEMO_StockOf":"de","ETDEMO_StockOpenProduct":"Abrir la ficha del producto","ETDEMO_StockPage":"Página","ETDEMO_StockPageSize":"por página","ETDEMO_StockPrev":"Anterior","ETDEMO_StockProduct":"Producto","ETDEMO_StockProducts":"productos","ETDEMO_StockScopeNote":"Los totales por almacén cubren todo el conjunto filtrado, no solo la página visible.","ETDEMO_StockSearch":"Buscar por código o nombre de producto","ETDEMO_StockSort":"Ordenar por","ETDEMO_StockSortCode":"código","ETDEMO_StockSortName":"nombre","ETDEMO_StockSortQty":"cantidad","ETDEMO_StockTitle":"Stock por producto y almacén","ETDEMO_StockTotal":"Total","ETDEMO_StockUom":"UdM","ETDEMO_StockWarehouses":"almacenes","ETDEMO_StockZeros":"Incluir total cero","ETUIK_LoadFailed":"No se pudieron cargar los datos","ETUIK_Loading":"Cargando…","ETUIK_MeterAria":"Puntuación %{score} sobre un objetivo de %{target}","ETUIK_RailAria":"Avance %{progress}%, esperado %{expected}%"});

/* com.etendoerp.uikit.samples/web/com.etendoerp.uikit.samples/js/picking.js */
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
        : s.order
          /* Solo el aviso de "ya no es visible", que explica por que faltan los controles. La
             invitacion a elegir la da el panel de detalle: decirla dos veces en la misma
             pantalla no invita el doble, solo ocupa dos renglones. */
          ? html`<p class="pck-none">${K.t('ETDEMO_PickingGone')}</p>`
          : ''}
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

</#noparse>
