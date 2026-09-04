# Etendo UI Kit — Samples

Las ventanas de referencia de `com.etendoerp.uikit`: seis ventanas de Etendo Classic construidas
sobre el runtime `OB.UIKit`, sin una linea de Java de vista y sin tocar core.

| vista | de que es | datos |
|---|---|---|
| `ETOKRS_Review` | revision trimestral de OKRs | tablas propias `ETOKRS_*` |
| `ETDEMO_Stock` | pivot producto x almacen | `m_storage_detail` |
| `ETDEMO_Cash` | cartera AR/AP con aging | `fin_payment_schedule`, `fin_payment` |
| `ETDEMO_Partner360` | ficha de tercero | `c_order`, `c_invoice`, `fin_payment` |
| `ETDEMO_Alerts` | bandeja del administrador | `ad_alert` |
| `ETDEMO_Picking` | preparacion de pedidos + Confirmar | `c_order`, `c_orderline` |

Dos prefijos, un modulo: **`ETOKRS`** para las cinco tablas fisicas que la ventana de OKRs necesita
y **`ETDEMO`** para las demos, que no crean ni una tabla y leen solo el modelo estandar de Etendo.
Es la unica razon por la que hay dos y no uno: renombrar tablas ya creadas es DDL, y no vale el
churn.

Este modulo es showcase, no framework. El framework —`com.etendoerp.uikit`— se instala solo y no
arrastra ninguna de estas ventanas; ahi viven el runtime, los gates, los docs y el indice del
contrato. Aca viven las ventanas, sus datasources, sus manifests y sus checks propios.

- Convenciones congeladas de la ronda: [CONVENTIONS.md](CONVENTIONS.md)
- Docs de cada ventana: `com.etendoerp.uikit/docs/samples/<slug>.md`
- Permisos: los aporta el module script `GrantSampleViewAccess`, porque `export.database` no cubre
  `OBUIAPP_View_Role_Access` y sin la fila la entrada de menu no aparece.
