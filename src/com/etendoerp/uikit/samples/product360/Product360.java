package com.etendoerp.uikit.samples.product360;

import org.codehaus.jettison.json.JSONObject;

/**
 * What the three ETDEMO_Product360 datasources share: the error envelope and the join that names
 * a coded column.
 *
 * There is deliberately no shared SQL here. The three sources read the same product from three
 * different grains -- one row per product in {@link ProductIndex}, eight panels of one product in
 * {@link ProductStock}, and the movement in {@link ProductLedger} -- and a common base query would
 * be a fourth grain that none of them actually wants.
 *
 * <h2>Why the coded labels are read and not written down</h2>
 *
 * {@code m_transaction.movementtype} holds {@code C-}, and that means "Customer Shipment" because
 * Etendo's dictionary says so: the vocabulary is declared in {@code ad_ref_list} against the
 * reference the column itself points at. So this window reads that label instead of defining a
 * parallel set of {@code ETDEMO_} rows for the same values. A private copy of somebody else's
 * vocabulary goes stale silently the day a module adds a status, and it would look like a
 * statement about the movement when it was really a statement about our guess.
 *
 * The reference is looked up from {@code ad_column} by table and column name at query time, so
 * the only things written down are names that belong to Etendo's public data model. A reference
 * UUID pasted into this file would be a per-installation constant pretending to be a fact, and a
 * value with no matching row simply has no label -- the caller then shows the raw code, which is
 * the honest answer for a code nobody declared. This module's own {@code AD_MESSAGE} rows cover
 * this module's own chrome: column headers, filters, empty states.
 */
final class Product360 {

  /** Core's Product window. The tab inside it is still resolved from the dictionary. */
  static final String PRODUCT_WINDOW = "140";

  private Product360() {
  }

  /**
   * A left join resolving one coded column's declared label.
   *
   * The dictionary subquery is uncorrelated, so it is evaluated once per statement rather than
   * once per row. Both the table and the column name are literals supplied by the calling
   * datasource -- never request values -- so nothing a user types reaches this SQL.
   *
   * @param joinAlias
   *          the alias to give the joined {@code ad_ref_list}
   * @param table
   *          the table owning the coded column, as {@code ad_table.tablename} spells it, compared
   *          case-insensitively
   * @param column
   *          the coded column, as {@code ad_column.columnname} spells it
   * @param valueExpr
   *          the qualified expression holding the code, for example {@code t.movementtype}
   * @return a {@code left join} clause; the label is {@code <joinAlias>.name}
   */
  static String refLabel(String joinAlias, String table, String column, String valueExpr) {
    return " left join ad_ref_list " + joinAlias + " on " + joinAlias + ".ad_reference_id ="
        + "   (select dc.ad_reference_value_id from ad_column dc"
        + "      join ad_table dt on dt.ad_table_id = dc.ad_table_id"
        + "     where lower(dt.tablename) = lower('" + table + "')"
        + "       and dc.columnname = '" + column + "')"
        + "   and " + joinAlias + ".value = " + valueExpr
        + "   and " + joinAlias + ".isactive = 'Y'";
  }

  /**
   * The error envelope every uikit datasource answers with: a 200 carrying {@code error.message},
   * which {@code OB.UIKit.fetch} turns into an Error instead of into data a view might render.
   *
   * @param e
   *          the failure
   * @return the envelope, or an empty object if even that could not be built
   */
  static JSONObject error(Exception e) {
    try {
      return new JSONObject().put("error",
          new JSONObject().put("message", e.getMessage() == null ? e.toString() : e.getMessage()));
    } catch (Exception ignored) {
      return new JSONObject();
    }
  }
}
