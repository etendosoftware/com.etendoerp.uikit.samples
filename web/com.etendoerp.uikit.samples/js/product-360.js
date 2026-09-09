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
