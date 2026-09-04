<#noparse>
/* ETOKRS_Review -- generado por verify/deploy-view.mjs. No editar en base de datos:
   la fuente son los archivos web/ de los modulos, y este bundle se regenera desde ahi. */
/* com.etendoerp.uikit/web/com.etendoerp.uikit/js/uikit.js */
/*
 * com.etendoerp.uikit runtime.
 *
 * One job: let a module own a rectangle of the DOM inside an Etendo Classic tab, and render it
 * from state with plain strings, without learning SmartClient. Everything here is in service of
 * OB.UIKit.defineView; the rest of the surface exists because defineView needs it.
 *
 * The contract this file implements is documented in docs/ — L0 for the shape, L5 for the API.
 * If the two disagree, gate G8 fails the build, so change both or neither.
 */
(function () {
  'use strict';

  if (typeof OB === 'undefined') {
    window.OB = {};
  }
  if (OB.UIKit) {
    return;
  }

  var VERSION = '0.1.0';
  var DATASOURCES = {};
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
    return raw(
      '<span class="uik-rail uik-' +
      (STATES[state] || 'flat') +
      '" style="--uik-p:' +
      p.toFixed(1) +
      '%;--uik-e:' +
      e.toFixed(1) +
      '%" role="img" aria-label="' +
      Math.round(p) +
      '% avanzado, ' +
      Math.round(e) +
      '% esperado"></span>'
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
    var cells = '';
    for (var i = 1; i <= 10; i++) {
      cells +=
        '<i class="' + (i <= filled ? 'on' : '') + (i === mark ? ' tg' : '') + '"></i>';
    }
    return raw(
      '<span class="uik-meter" role="img" aria-label="score ' +
      score.toFixed(2) +
      ' de ' +
      target.toFixed(2) +
      '">' +
      cells +
      '</span>'
    );
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

  /* -------------------------------------------------------------- the view */

  /**
   * Defines a Classic view that owns its own DOM subtree.
   *
   * Rendering is whole-region strings, and a region is written only when its string changed. That
   * is what keeps the filter bar from flickering when the user clicks a chip inside it.
   *
   * @param {Object} spec
   * @param {string} spec.name  the view id, matching OBUIAPP_View_Impl.name and isc.<name>
   * @param {string} [spec.title]  label key for the tab title; falls back to the view id
   * @param {Object} spec.state  the initial state object; every key is yours
   * @param {Object<string, string>} [spec.data]  { alias: 'DatasourceName' }, fetched before the first render
   * @param {function(Object): Object<string, *>} [spec.params]  (state) => request params; a change to these refetches
   * @param {string[]} [spec.regions]  region names, in render order
   * @param {string[]} [spec.keepScroll]  region names whose scrollTop survives a redraw
   * @param {function(Object, Object): Object<string, string|Raw>} spec.render  (state, data) => { region: html }
   * @param {Object<string, function(Object, Event, Element): void>} [spec.on]  { 'click [data-x]': handler }
   * @returns {Object} the SmartClient class, already registered as isc.<name>
   */
  function defineView(spec) {
    var name = spec.name;
    var regions = spec.regions || Object.keys(spec.state.regions || {});

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

      /** Creates our root element inside the SmartClient handle and paints once. */
      uikMount: function () {
        var handle = this.getHandle();
        if (!handle) {
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
          self.uikRoot.addEventListener(type, function (event) {
            var rules = byType[type];
            for (var i = 0; i < rules.length; i++) {
              var el = rules[i].selector
                ? event.target.closest(rules[i].selector)
                : event.target;
              if (el && self.uikRoot.contains(el)) {
                rules[i].fn(self.uikCtx(), event, el);
                return;
              }
            }
          });
        });
      },

      /** The context handed to event handlers: the only sanctioned way to change state. */
      uikCtx: function () {
        var self = this;
        return {
          state: self.uikState,
          data: self.uikData,
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
          }
        };
      },

      /** Refetches when the datasource params changed; otherwise just repaints. */
      uikSync: function () {
        var next = JSON.stringify(spec.params ? spec.params(this.uikState) : {});
        if (next !== this.uikParams) {
          this.uikLoad();
        } else {
          this.uikPaint();
        }
      },

      uikLoad: function () {
        var self = this;
        var params = spec.params ? spec.params(this.uikState) : {};
        var aliases = Object.keys(spec.data || {});
        this.uikParams = JSON.stringify(params);
        // These params are what getBookMarkParams publishes, so the URL has to follow them.
        if (this.viewTabId && OB.Layout.HistoryManager) {
          OB.Layout.HistoryManager.updateHistory();
        }
        if (aliases.length === 0) {
          this.uikPaint();
          return;
        }
        this.uikSetRegion('rail', '<div class="uik-loading">' + esc(t('ETUIK_Loading')) + '</div>');
        var pending = aliases.length;
        var failed = null;
        aliases.forEach(function (alias) {
          fetch(spec.data[alias], params, function (err, data) {
            if (err) {
              failed = failed || err;
            } else {
              self.uikData[alias] = data;
            }
            if (--pending === 0) {
              if (failed) {
                self.uikFail(failed);
              } else {
                self.uikPaint();
              }
            }
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
        if (!this.uikRoot) {
          return;
        }
        var out;
        try {
          out = spec.render(this.uikState, this.uikData) || {};
        } catch (e) {
          this.uikFail(e);
          throw e;
        }
        var self = this;
        regions.forEach(function (r) {
          self.uikSetRegion(r, out[r] === undefined ? '' : out[r]);
        });
      },

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
        node.innerHTML = markup;
        this.uikPainted[region] = markup;
        if (keep !== null) {
          node.scrollTop = keep;
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
    badge: badge,
    rail: rail,
    meter: meter,
    clamp: clamp,
    defineView: defineView
  };
})();


/* com.etendoerp.uikit/web/com.etendoerp.uikit/css/uikit.css */
OB.UIKit.style("com.etendoerp.uikit", "/*\n * com.etendoerp.uikit base stylesheet.\n *\n * Scoped under .uik so nothing here can reach Classic's own chrome, and so a window can be\n * dropped into any skin without a specificity fight. Only the primitives the runtime ships live\n * here -- regions, badge, rail, meter, loading and error. Everything else belongs to the app.\n */\n\n.uik {\n  --uik-ink: #16202b;\n  --uik-ink-soft: #5b6b7c;\n  --uik-line: #dde3ea;\n  --uik-surface: #ffffff;\n  --uik-ground: #f4f6f9;\n  --uik-brand: #1b5e8c;\n  --uik-ok: #1c7a54;\n  --uik-risk: #a8700d;\n  --uik-bad: #b23a3a;\n  --uik-flat: #7d8b99;\n\n  box-sizing: border-box;\n  padding: 16px 20px 28px;\n  min-height: 100%;\n  background: var(--uik-ground);\n  color: var(--uik-ink);\n  font: 13px/1.45 \"Helvetica Neue\", Helvetica, Arial, sans-serif;\n  -webkit-font-smoothing: antialiased;\n}\n\n.uik *,\n.uik *::before,\n.uik *::after {\n  box-sizing: inherit;\n}\n\n.uik .uik-region + .uik-region {\n  margin-top: 14px;\n}\n\n.uik .uik-region:empty {\n  display: none;\n}\n\n/* --------------------------------------------------------------- feedback */\n\n.uik .uik-loading,\n.uik .uik-error {\n  padding: 18px 20px;\n  border: 1px solid var(--uik-line);\n  border-radius: 6px;\n  background: var(--uik-surface);\n  color: var(--uik-ink-soft);\n}\n\n.uik .uik-error {\n  border-color: color-mix(in srgb, var(--uik-bad) 40%, var(--uik-line));\n  color: var(--uik-bad);\n}\n\n/* ----------------------------------------------------------------- badge */\n\n.uik .uik-badge {\n  display: inline-block;\n  padding: 2px 8px;\n  border-radius: 10px;\n  border: 1px solid currentColor;\n  font-size: 11px;\n  font-weight: 600;\n  letter-spacing: 0.02em;\n  white-space: nowrap;\n}\n\n.uik .uik-ok { color: var(--uik-ok); }\n.uik .uik-risk { color: var(--uik-risk); }\n.uik .uik-bad { color: var(--uik-bad); }\n.uik .uik-flat { color: var(--uik-flat); }\n\n/* -------------------------------------------------------------- pace rail\n * --uik-p is the progress fill, --uik-e the expected mark for today. The gap between them is the\n * whole point of the instrument, so the mark is drawn on top of the fill, never behind it.\n */\n\n.uik .uik-rail {\n  position: relative;\n  display: block;\n  height: 8px;\n  border-radius: 4px;\n  background: #e6ebf1;\n  overflow: hidden;\n}\n\n.uik .uik-rail::before {\n  content: \"\";\n  position: absolute;\n  inset: 0 auto 0 0;\n  width: var(--uik-p, 0%);\n  border-radius: 4px 0 0 4px;\n  background: currentColor;\n}\n\n.uik .uik-rail::after {\n  content: \"\";\n  position: absolute;\n  top: -2px;\n  bottom: -2px;\n  left: var(--uik-e, 0%);\n  width: 2px;\n  margin-left: -1px;\n  background: var(--uik-ink);\n  opacity: 0.72;\n}\n\n/* ------------------------------------------------------------ score meter */\n\n.uik .uik-meter {\n  display: inline-flex;\n  gap: 2px;\n  vertical-align: middle;\n}\n\n.uik .uik-meter i {\n  width: 7px;\n  height: 12px;\n  border-radius: 1px;\n  background: #e6ebf1;\n  box-shadow: inset 0 0 0 1px transparent;\n}\n\n.uik .uik-meter i.on {\n  background: var(--uik-brand);\n}\n\n.uik .uik-meter i.tg {\n  box-shadow: inset 0 0 0 1px var(--uik-ink);\n}\n\n.uik .uik-meter i.tg:not(.on) {\n  background: transparent;\n}\n\n/* ---------------------------------------------------------------- a11y */\n\n.uik :focus-visible {\n  outline: 2px solid var(--uik-brand);\n  outline-offset: 1px;\n}\n\n@media (prefers-reduced-motion: reduce) {\n  .uik * {\n    transition: none !important;\n    animation: none !important;\n  }\n}\n");

/* com.etendoerp.uikit.samples/web/com.etendoerp.uikit.samples/css/okr-review.css */
OB.UIKit.style("com.etendoerp.uikit.samples.okr", "/*\n * ETOKRS_Review stylesheet. Everything is scoped under .uik-etokrs_review, the class the runtime\n * puts on the window's own root, so this file cannot reach Classic's chrome or another window.\n *\n * Primitives (badge, rail, meter) come from uikit.css. What is here is layout and the two\n * densities the screen needs: a summary that reads at a glance, and a table that reads carefully.\n */\n\n.uik-etokrs_review {\n  --okr-radius: 7px;\n  --okr-shadow: 0 1px 2px rgba(22, 32, 43, 0.06);\n}\n\n.uik-etokrs_review .okr-h2 {\n  margin: 0 0 10px;\n  font-size: 12px;\n  font-weight: 700;\n  letter-spacing: 0.06em;\n  text-transform: uppercase;\n  color: var(--uik-ink-soft);\n  display: flex;\n  align-items: baseline;\n  gap: 10px;\n}\n\n.uik-etokrs_review .okr-h2 span {\n  font-size: 12px;\n  font-weight: 400;\n  letter-spacing: 0;\n  text-transform: none;\n}\n\n/* ----------------------------------------------------------- filter bar */\n\n.uik-etokrs_review .okr-bar {\n  display: flex;\n  align-items: center;\n  justify-content: space-between;\n  gap: 16px;\n  flex-wrap: wrap;\n}\n\n.uik-etokrs_review .okr-seg {\n  display: inline-flex;\n  border: 1px solid var(--uik-line);\n  border-radius: var(--okr-radius);\n  background: var(--uik-surface);\n  overflow: hidden;\n}\n\n.uik-etokrs_review .okr-seg-item {\n  appearance: none;\n  border: 0;\n  border-left: 1px solid var(--uik-line);\n  background: transparent;\n  padding: 6px 14px;\n  font: inherit;\n  font-weight: 600;\n  color: var(--uik-ink-soft);\n  cursor: pointer;\n}\n\n.uik-etokrs_review .okr-seg-item:first-child {\n  border-left: 0;\n}\n\n.uik-etokrs_review .okr-seg-item[data-empty=\"1\"] {\n  color: color-mix(in srgb, var(--uik-ink-soft) 55%, var(--uik-surface));\n}\n\n.uik-etokrs_review .okr-seg-item[aria-pressed=\"true\"] {\n  background: var(--uik-brand);\n  color: #fff;\n}\n\n.uik-etokrs_review .okr-clock {\n  display: flex;\n  align-items: baseline;\n  gap: 8px;\n}\n\n.uik-etokrs_review .okr-clock-num {\n  font-weight: 700;\n  font-variant-numeric: tabular-nums;\n}\n\n.uik-etokrs_review .okr-clock-sub {\n  color: var(--uik-ink-soft);\n}\n\n.uik-etokrs_review .okr-chips {\n  display: flex;\n  flex-wrap: wrap;\n  gap: 6px;\n  margin-top: 10px;\n}\n\n.uik-etokrs_review .okr-chip {\n  appearance: none;\n  border: 1px solid var(--uik-line);\n  border-radius: 12px;\n  background: var(--uik-surface);\n  padding: 3px 11px;\n  font: inherit;\n  color: var(--uik-ink-soft);\n  cursor: pointer;\n}\n\n.uik-etokrs_review .okr-chip[aria-pressed=\"true\"] {\n  border-color: var(--uik-brand);\n  background: color-mix(in srgb, var(--uik-brand) 10%, var(--uik-surface));\n  color: var(--uik-brand);\n  font-weight: 600;\n}\n\n/* --------------------------------------------- department small multiples */\n\n.uik-etokrs_review .okr-rail {\n  display: grid;\n  grid-template-columns: repeat(auto-fit, minmax(190px, 1fr));\n  gap: 10px;\n}\n\n.uik-etokrs_review .okr-card {\n  appearance: none;\n  display: grid;\n  gap: 8px;\n  text-align: left;\n  padding: 11px 13px 12px;\n  border: 1px solid var(--uik-line);\n  border-radius: var(--okr-radius);\n  background: var(--uik-surface);\n  box-shadow: var(--okr-shadow);\n  font: inherit;\n  color: inherit;\n  cursor: pointer;\n}\n\n.uik-etokrs_review .okr-card.is-on {\n  border-color: var(--uik-brand);\n  box-shadow: 0 0 0 1px var(--uik-brand);\n}\n\n.uik-etokrs_review .okr-card-head {\n  display: flex;\n  align-items: center;\n  justify-content: space-between;\n  gap: 8px;\n}\n\n.uik-etokrs_review .okr-card-name {\n  font-weight: 700;\n}\n\n.uik-etokrs_review .okr-card-foot {\n  display: flex;\n  align-items: center;\n  gap: 8px;\n}\n\n.uik-etokrs_review .okr-card-score {\n  font-variant-numeric: tabular-nums;\n  font-weight: 600;\n}\n\n.uik-etokrs_review .okr-card-score em {\n  font-style: normal;\n  font-weight: 400;\n  color: var(--uik-ink-soft);\n}\n\n.uik-etokrs_review .okr-card-meta {\n  font-size: 11px;\n  color: var(--uik-ink-soft);\n}\n\n/* ----------------------------------------------------------------- agenda */\n\n.uik-etokrs_review .okr-agenda {\n  padding: 13px 15px 6px;\n  border: 1px solid var(--uik-line);\n  border-left: 3px solid var(--uik-brand);\n  border-radius: var(--okr-radius);\n  background: var(--uik-surface);\n  box-shadow: var(--okr-shadow);\n}\n\n.uik-etokrs_review .okr-agenda-list {\n  margin: 0;\n  padding: 0;\n  list-style: none;\n}\n\n.uik-etokrs_review .okr-agenda-item {\n  display: grid;\n  grid-template-columns: 22px 1fr auto;\n  align-items: center;\n  gap: 12px;\n  padding: 9px 0;\n  border-top: 1px solid var(--uik-line);\n}\n\n.uik-etokrs_review .okr-agenda-item:first-child {\n  border-top: 0;\n}\n\n.uik-etokrs_review .okr-agenda-rank {\n  font-size: 15px;\n  font-weight: 700;\n  color: var(--uik-ink-soft);\n  font-variant-numeric: tabular-nums;\n}\n\n.uik-etokrs_review .okr-agenda-body {\n  display: grid;\n  gap: 4px;\n  min-width: 0;\n}\n\n.uik-etokrs_review .okr-agenda-title {\n  font-weight: 600;\n}\n\n.uik-etokrs_review .okr-agenda-meta {\n  font-size: 11px;\n  color: var(--uik-ink-soft);\n}\n\n.uik-etokrs_review .okr-agenda-num {\n  display: grid;\n  justify-items: end;\n  gap: 3px;\n  font-variant-numeric: tabular-nums;\n}\n\n.uik-etokrs_review .okr-agenda-sub {\n  font-size: 11px;\n  color: var(--uik-ink-soft);\n}\n\n/* ------------------------------------------------------------------ panel */\n\n.uik-etokrs_review .okr-panel-head {\n  display: flex;\n  align-items: center;\n  justify-content: space-between;\n  gap: 16px;\n  flex-wrap: wrap;\n  border-bottom: 1px solid var(--uik-line);\n  padding-bottom: 8px;\n  margin-bottom: 12px;\n}\n\n.uik-etokrs_review .okr-tabs {\n  display: inline-flex;\n  gap: 4px;\n}\n\n.uik-etokrs_review .okr-tab {\n  appearance: none;\n  border: 0;\n  border-bottom: 2px solid transparent;\n  background: transparent;\n  padding: 5px 4px;\n  margin-bottom: -9px;\n  font: inherit;\n  font-size: 14px;\n  font-weight: 600;\n  color: var(--uik-ink-soft);\n  cursor: pointer;\n}\n\n.uik-etokrs_review .okr-tab[aria-pressed=\"true\"] {\n  border-bottom-color: var(--uik-brand);\n  color: var(--uik-ink);\n}\n\n.uik-etokrs_review .okr-sort {\n  font-size: 11px;\n  color: var(--uik-ink-soft);\n}\n\n.uik-etokrs_review .okr-sort-item {\n  appearance: none;\n  border: 0;\n  background: transparent;\n  padding: 2px 4px;\n  font: inherit;\n  color: var(--uik-ink-soft);\n  cursor: pointer;\n  text-decoration: underline dotted;\n  text-underline-offset: 2px;\n}\n\n.uik-etokrs_review .okr-sort-item[aria-pressed=\"true\"] {\n  color: var(--uik-brand);\n  font-weight: 700;\n  text-decoration: none;\n}\n\n/* -------------------------------------------------------------- objectives */\n\n.uik-etokrs_review .okr-obj {\n  border: 1px solid var(--uik-line);\n  border-radius: var(--okr-radius);\n  background: var(--uik-surface);\n  margin-bottom: 8px;\n  overflow: hidden;\n}\n\n.uik-etokrs_review .okr-obj-head {\n  appearance: none;\n  width: 100%;\n  display: grid;\n  grid-template-columns: 14px minmax(0, 1fr) 200px auto;\n  align-items: center;\n  gap: 14px;\n  padding: 11px 14px;\n  border: 0;\n  background: transparent;\n  font: inherit;\n  text-align: left;\n  color: inherit;\n  cursor: pointer;\n}\n\n.uik-etokrs_review .okr-obj-head:hover {\n  background: color-mix(in srgb, var(--uik-brand) 4%, var(--uik-surface));\n}\n\n.uik-etokrs_review .okr-obj-caret {\n  width: 0;\n  height: 0;\n  border-left: 5px solid var(--uik-ink-soft);\n  border-top: 4px solid transparent;\n  border-bottom: 4px solid transparent;\n  margin-left: 3px;\n}\n\n.uik-etokrs_review .okr-obj.is-open .okr-obj-caret {\n  border-left: 4px solid transparent;\n  border-right: 4px solid transparent;\n  border-top: 5px solid var(--uik-ink-soft);\n  border-bottom: 0;\n  margin-left: 0;\n}\n\n.uik-etokrs_review .okr-obj-main {\n  display: grid;\n  gap: 3px;\n  min-width: 0;\n}\n\n.uik-etokrs_review .okr-obj-title {\n  font-weight: 600;\n  font-size: 14px;\n}\n\n.uik-etokrs_review .okr-obj-meta {\n  font-size: 11px;\n  color: var(--uik-ink-soft);\n}\n\n.uik-etokrs_review .okr-obj-nums {\n  display: grid;\n  gap: 5px;\n  font-variant-numeric: tabular-nums;\n}\n\n.uik-etokrs_review .okr-obj-pct {\n  font-size: 17px;\n  font-weight: 700;\n  line-height: 1;\n}\n\n.uik-etokrs_review .okr-obj-scores {\n  display: flex;\n  align-items: center;\n  gap: 7px;\n  font-size: 11px;\n}\n\n.uik-etokrs_review .okr-obj-scores em {\n  font-style: normal;\n  color: var(--uik-ink-soft);\n}\n\n/* ------------------------------------------------------------------ table */\n\n.uik-etokrs_review .okr-tablewrap {\n  overflow-x: auto;\n  border-top: 1px solid var(--uik-line);\n  background: var(--uik-ground);\n}\n\n.uik-etokrs_review .okr-panel-body > .okr-tablewrap {\n  border: 1px solid var(--uik-line);\n  border-radius: var(--okr-radius);\n  background: var(--uik-surface);\n}\n\n.uik-etokrs_review .okr-table {\n  width: 100%;\n  border-collapse: collapse;\n  font-variant-numeric: tabular-nums;\n}\n\n.uik-etokrs_review .okr-table th {\n  text-align: right;\n  font-size: 10px;\n  font-weight: 700;\n  letter-spacing: 0.05em;\n  text-transform: uppercase;\n  color: var(--uik-ink-soft);\n  padding: 8px 12px;\n  border-bottom: 1px solid var(--uik-line);\n  white-space: nowrap;\n}\n\n.uik-etokrs_review .okr-table th:first-child {\n  text-align: left;\n}\n\n.uik-etokrs_review .okr-table td {\n  padding: 9px 12px;\n  border-bottom: 1px solid var(--uik-line);\n  vertical-align: middle;\n}\n\n.uik-etokrs_review .okr-table tr:last-child td {\n  border-bottom: 0;\n}\n\n.uik-etokrs_review .okr-t-title {\n  min-width: 240px;\n}\n\n.uik-etokrs_review .okr-t-title span {\n  display: block;\n  font-weight: 600;\n}\n\n.uik-etokrs_review .okr-t-title em {\n  display: block;\n  margin-top: 2px;\n  font-style: normal;\n  font-size: 11px;\n  color: var(--uik-ink-soft);\n}\n\n.uik-etokrs_review .okr-t-val {\n  text-align: right;\n  white-space: nowrap;\n}\n\n.uik-etokrs_review .okr-t-rail {\n  min-width: 150px;\n}\n\n.uik-etokrs_review .okr-t-rail em,\n.uik-etokrs_review .okr-t-score em {\n  display: block;\n  margin-top: 4px;\n  font-style: normal;\n  font-size: 11px;\n  color: var(--uik-ink-soft);\n}\n\n.uik-etokrs_review .okr-t-score {\n  white-space: nowrap;\n}\n\n/* ---------------------------------------------------------------- updates */\n\n.uik-etokrs_review .okr-updates {\n  margin: 0;\n  padding: 0;\n  list-style: none;\n}\n\n.uik-etokrs_review .okr-upd {\n  display: grid;\n  grid-template-columns: 92px minmax(0, 1fr);\n  gap: 14px;\n  padding: 11px 0;\n  border-bottom: 1px solid var(--uik-line);\n}\n\n.uik-etokrs_review .okr-upd:last-child {\n  border-bottom: 0;\n}\n\n.uik-etokrs_review .okr-upd-date {\n  font-variant-numeric: tabular-nums;\n  color: var(--uik-ink-soft);\n  font-size: 11px;\n  padding-top: 2px;\n}\n\n.uik-etokrs_review .okr-upd-body {\n  display: grid;\n  gap: 3px;\n  min-width: 0;\n}\n\n.uik-etokrs_review .okr-upd-title {\n  font-weight: 600;\n}\n\n.uik-etokrs_review .okr-upd-move {\n  font-size: 11px;\n  color: var(--uik-ink-soft);\n  font-variant-numeric: tabular-nums;\n}\n\n.uik-etokrs_review .okr-upd-move b {\n  color: var(--uik-ink);\n}\n\n.uik-etokrs_review .okr-upd-note {\n  max-width: 74ch;\n}\n\n.uik-etokrs_review .okr-empty {\n  margin: 0;\n  padding: 26px 4px;\n  color: var(--uik-ink-soft);\n  text-align: center;\n}\n");

/* AD_MESSAGE */
OB.UIKit.labels({"ETOKRS_ReviewTitle":"Revisión de OKRs","ETUIK_LoadFailed":"No se pudieron cargar los datos","ETUIK_Loading":"Cargando…"});

/* com.etendoerp.uikit.samples/web/com.etendoerp.uikit.samples/js/okr-review.js */
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

</#noparse>
