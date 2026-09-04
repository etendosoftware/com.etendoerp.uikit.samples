package com.etendoerp.uikit.samples.okr;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.List;
import java.util.Map;

import org.codehaus.jettison.json.JSONArray;

import com.etendoerp.uikit.server.UikQuery;

/**
 * The plumbing this class used to hold now lives in {@link UikQuery}, where every uikit window can
 * reach it. This shim stays so the OKR sample and the gates that pin it keep compiling and reading
 * exactly as they did.
 */
class OkrQuery {

  private OkrQuery() {
  }

  static String marks(int count) {
    return UikQuery.marks(count);
  }

  static String[] readableClients() {
    return UikQuery.readableClients();
  }

  static String[] readableOrgs() {
    return UikQuery.readableOrgs();
  }

  static int bindScope(PreparedStatement st, int from) throws Exception {
    return UikQuery.bindScope(st, from);
  }

  static String scopeClause(String alias) {
    return UikQuery.scopeClause(alias);
  }

  static Connection connection() {
    return UikQuery.connection();
  }

  static String param(Map<String, Object> parameters, String key) {
    return UikQuery.param(parameters, key);
  }

  static JSONArray rows(ResultSet rs, UikQuery.Col... cols) throws Exception {
    return UikQuery.rows(rs, cols);
  }

  static List<UikQuery.Col> list(UikQuery.Col... cols) {
    return UikQuery.list(cols);
  }

  /** Kept as a name, not a second contract: {@code OkrQuery.Col} still names the uikit column. */
  interface Col extends UikQuery.Col {
  }

  static UikQuery.Col str(String key, String column) {
    return UikQuery.str(key, column);
  }

  static UikQuery.Col num(String key, String column) {
    return UikQuery.num(key, column);
  }

  static UikQuery.Col date(String key, String column) {
    return UikQuery.date(key, column);
  }
}
