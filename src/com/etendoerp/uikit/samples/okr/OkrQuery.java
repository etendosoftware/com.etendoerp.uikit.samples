package com.etendoerp.uikit.samples.okr;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import org.codehaus.jettison.json.JSONArray;
import org.codehaus.jettison.json.JSONObject;
import org.openbravo.dal.core.OBContext;
import org.openbravo.dal.service.OBDal;

/**
 * Shared SQL plumbing for the OKR review datasources.
 *
 * The ETOKRS_* tables are not mapped as DAL entities on purpose: this sample exists to show that a
 * uikit window needs no generated entities, no build and no Tomcat restart. Reads go through the
 * connection DAL already owns, so they join the current transaction and honour its isolation.
 *
 * Every query is scoped to the readable clients and organizations of the session role. That is the
 * only place access is enforced -- fact F6 records that ViewComponent does not consult
 * OBUIAPP_View_Role_Access, so filtering in the UI would be decoration, not security.
 */
class OkrQuery {

  private OkrQuery() {
  }

  /**
   * Renders {@code count} bind placeholders: {@code ?,?,?}. An empty scope renders {@code null}, so
   * the resulting {@code in (null)} matches no row -- which is what an empty scope means.
   */
  static String marks(int count) {
    return count < 1 ? "null" : "?" + ",?".repeat(count - 1);
  }

  static String[] readableClients() {
    return OBContext.getOBContext().getReadableClients();
  }

  static String[] readableOrgs() {
    return OBContext.getOBContext().getReadableOrganizations();
  }

  /** Binds the readable-scope arrays starting at {@code from}; returns the next free index. */
  static int bindScope(PreparedStatement st, int from) throws Exception {
    int i = from;
    for (String c : readableClients()) {
      st.setString(i++, c);
    }
    for (String o : readableOrgs()) {
      st.setString(i++, o);
    }
    return i;
  }

  static String scopeClause(String alias) {
    return alias + ".ad_client_id in (" + marks(readableClients().length) + ") and " + alias
        + ".ad_org_id in (" + marks(readableOrgs().length) + ") and " + alias + ".isactive = 'Y'";
  }

  /** DAL owns this connection: borrow it, never close it. */
  static Connection connection() {
    return OBDal.getInstance().getConnection(false);
  }

  static String param(Map<String, Object> parameters, String key) {
    final Object raw = parameters.get(key);
    if (raw == null) {
      return null;
    }
    final String value = raw.toString().trim();
    return value.isEmpty() || "all".equals(value) || "null".equals(value) ? null : value;
  }

  /** Maps a result set to a JSON array, one object per row, using the given column list. */
  static JSONArray rows(ResultSet rs, Col... cols) throws Exception {
    final JSONArray out = new JSONArray();
    while (rs.next()) {
      final JSONObject row = new JSONObject();
      for (Col col : cols) {
        col.put(rs, row);
      }
      out.put(row);
    }
    return out;
  }

  static List<Col> list(Col... cols) {
    final List<Col> out = new ArrayList<>();
    for (Col c : cols) {
      out.add(c);
    }
    return out;
  }

  /** One column of a result set, and how it lands in JSON. */
  interface Col {
    void put(ResultSet rs, JSONObject row) throws Exception;
  }

  static Col str(String key, String column) {
    return (rs, row) -> row.put(key, rs.getString(column) == null ? "" : rs.getString(column));
  }

  static Col num(String key, String column) {
    return (rs, row) -> {
      final java.math.BigDecimal v = rs.getBigDecimal(column);
      row.put(key, v == null ? JSONObject.NULL : v.doubleValue());
    };
  }

  static Col date(String key, String column) {
    return (rs, row) -> {
      final java.sql.Timestamp v = rs.getTimestamp(column);
      row.put(key, v == null ? JSONObject.NULL : v.toLocalDateTime().toLocalDate().toString());
    };
  }
}
