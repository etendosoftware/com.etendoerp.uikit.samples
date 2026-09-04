# Convenciones congeladas de la ronda R2

Se congelaron antes de la fase paralela. Nadie las cambia sin resincronizar a todos los agentes.

## Nombres de clase CSS del runtime

El runtime aporta, y ningun modulo redefine: `.uik-bars`, `.uik-bar`, `.uik-spark`, `.uik-table`,
`.uik-pager`, `.uik-busy`, `.uik-chip`. Todas leen tokens `--uik-*` y nada mas.

`.uik-chip` se agrego a las seis del plan porque la decision D5 obliga a mostrar la fecha de
referencia en pantalla y esa marca necesita una clase.

## Esquema del manifest de vista

`view`, `source`, `classpath` y `bundle[]` son los de siempre y `deploy-view.mjs` no cambia. Las
tres claves nuevas las lee el runner de `check-window.mjs`; `deploy-view.mjs` las ignora.

```json
{
  "view": "ETDEMO_Cash",
  "module": "com.etendoerp.uikit.samples",
  "source": "com.etendoerp.uikit.samples/src/com/etendoerp/uikit/samples/cash/templates/ETDEMO_Cash.ftl",
  "classpath": "/com/etendoerp/uikit/samples/cash/templates/ETDEMO_Cash.ftl",
  "bundle": [],
  "datasources": [
    {
      "action": "com.etendoerp.uikit.samples.cash.Portfolio",
      "params": { "side": "AP" },
      "requires": ["asOf", "asOfSource", "buckets", "rows"]
    }
  ],
  "writes": [
    {
      "action": "com.etendoerp.uikit.samples.alerts.AckAlert",
      "payload": { "id": "0", "status": "ACKNOWLEDGED" }
    }
  ],
  "checks": "com.etendoerp.uikit.samples/verify/etdemo-cash.checks.mjs"
}
```

- `datasources[]` alimenta W4: cada uno responde 200, es JSON y trae las claves de `requires`.
- `writes[]` alimenta W7: cada uno debe ser rechazado sin token CSRF y aceptado con token.
- `checks` es una ruta bajo `modules/`, igual que `bundle[].path`, y exporta
  `export default async function (ctx)` con `ctx = {manifest, action, get, query, pass, fail, skip}`.

## Documentacion

Los docs de las demos viven en `com.etendoerp.uikit/docs/samples/<slug>.md`, no en este modulo: el
indice que los gobierna es `com.etendoerp.uikit/uikit.contract.json` y G4 resuelve las rutas
relativas al modulo del framework. Las capturas van a `com.etendoerp.uikit/docs/samples/img/`.

## Mensajes

Un solo prefijo: `ETDEMO_`. Todo manifest declara `["ETDEMO_", "ETUIK_"]` en su entrada `labels`:
`deploy-view.mjs` hornea las etiquetas al desplegar, y omitir `ETUIK_` deja la vista con claves
crudas donde el runtime llama a `t()`.
