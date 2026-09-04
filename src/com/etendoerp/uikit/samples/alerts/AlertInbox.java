package com.etendoerp.uikit.samples.alerts;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.List;
import java.util.Map;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.codehaus.jettison.json.JSONArray;
import org.codehaus.jettison.json.JSONObject;
import org.openbravo.client.kernel.BaseActionHandler;
import org.openbravo.dal.core.OBContext;

import com.etendoerp.uikit.server.UikQuery;

/**
 * Datasource ETDEMO_Alerts: the administrator's alert inbox, grouped by rule.
 *
 * Reached at {@code org.openbravo.client.kernel?_action=} plus this class's fully qualified name.
 * KernelServlet resolves an action handler by class name and only gates portal roles, so no
 * dictionary row publishes this endpoint.
 *
 * Accepted parameters: {@code status} (one of {@link #STATUSES}, anything else means no filter)
 * and {@code rule} (an {@code ad_alertrule_id}). Both are optional and both narrow the detail list
 * only.
 *
 * The asymmetry this datasource exists to demonstrate:
 *
 * <ul>
 * <li>{@code statuses} and {@code rules} ignore both filters entirely. They are the navigation
 * rail, and a rail that only counts what is already on screen cannot tell a reader what they are
 * not looking at -- which is the single question an inbox exists to answer.</li>
 * <li>{@code rows} honours both.</li>
 * </ul>
 *
 * {@link #VIS}, {@link #ST} and {@link #FROM} are shared with {@link AckAlert} on purpose: the
 * write re-reads its target through the very same predicate the read used, so the two cannot
 * drift apart into a window that shows a row it refuses to touch, or worse, touches a row it
 * would not show.
 */
public class AlertInbox extends BaseActionHandler {

  private static final Logger log = LogManager.getLogger();

  /**
   * The values {@code ad_alert.status} takes in this instance's dictionary. There is no
   * {@code ACK}: the acknowledged state is spelled {@code ACKNOWLEDGED}.
   */
  static final List<String> STATUSES = List.of("NEW", "ACKNOWLEDGED", "SOLVED", "SUPPRESSED");

  /**
   * {@code ad_alert.status} is nullable, and core's own alert datasource reads a null one as
   * {@code NEW} ({@code coalesce(to_char(status), 'NEW')} in ADAlertDatasourceService), so every
   * query here goes through the same normalisation instead of leaking a JSON null to the client.
   */
  static final String ST = "coalesce(nullif(trim(a.status), ''), 'NEW')";

  /** Alert, its rule, and the rule's tab -- joined on the tab's primary key, so never fanned. */
  static final String FROM = " from ad_alert a"
      + " join ad_alertrule r on r.ad_alertrule_id = a.ad_alertrule_id"
      + " left join ad_tab t on t.ad_tab_id = r.ad_tab_id and t.isactive = 'Y'";

  /**
   * Who may see one alert. Scope on the alert and on its rule, plus a recipient predicate, and
   * fact F6 is why the second half is not optional: the window granted the caller nothing, so
   * this clause is the whole access decision.
   *
   * Two ways to be a recipient, because the schema has two. An alert can be addressed directly,
   * through {@code ad_alert.ad_user_id} or {@code ad_alert.ad_role_id} -- which is how the 26
   * dictionary alerts in this instance reach the System Administrator role -- and a rule can
   * carry a recipient list in {@code ad_alertrecipient}, which is the arm core's own datasource
   * implements and the only one that reaches the business rules.
   *
   * Bind order, and every query built on this repeats it: scope(a), scope(r), user, role, user,
   * role.
   */
  static final String VIS = UikQuery.scopeClause("a") + " and " + UikQuery.scopeClause("r")
      + " and (a.ad_user_id = ?"
      + "   or (a.ad_user_id is null and a.ad_role_id = ?)"
      + "   or exists (select 1 from ad_alertrecipient p"
      + "        where p.ad_alertrule_id = r.ad_alertrule_id and p.isactive = 'Y'"
      + "        and (p.ad_user_id = ? or (p.ad_user_id is null and p.ad_role_id = ?))))";

  /** Binds {@link #VIS} starting at {@code from}; returns the next free index. */
  static int bindVis(PreparedStatement st, int from) throws Exception {
    int i = UikQuery.bindScope(st, from);
    i = UikQuery.bindScope(st, i);
    final String user = OBContext.getOBContext().getUser().getId();
    final String role = OBContext.getOBContext().getRole().getId();
    st.setString(i++, user);
    st.setString(i++, role);
    st.setString(i++, user);
    st.setString(i++, role);
    return i;
  }

  @Override
  protected JSONObject execute(Map<String, Object> parameters, String content) {
    try {
      final Connection conn = UikQuery.connection();
      final String raw = UikQuery.param(parameters, "status");
      final String status = raw != null && STATUSES.contains(raw) ? raw : null;
      final String rule = UikQuery.param(parameters, "rule");
      final int limit = UikQuery.page(parameters)[0];

      final JSONObject counts = statuses(conn);
      long total = 0;
      for (String s : STATUSES) {
        total += counts.getLong(s);
      }
      final JSONArray statusList = new JSONArray();
      for (String s : STATUSES) {
        statusList.put(new JSONObject().put("status", s).put("n", counts.getLong(s)));
      }

      final JSONArray rows = rows(conn, status, rule, limit);
      return new JSONObject()
          .put("statuses", statusList)
          .put("rules", rules(conn))
          .put("total", total)
          .put("rows", rows)
          .put("meta", new JSONObject()
              .put("role", OBContext.getOBContext().getRole().getId())
              .put("user", OBContext.getOBContext().getUser().getId())
              .put("statusList", new JSONArray(STATUSES))
              .put("filter", new JSONObject()
                  .put("status", status == null ? "" : status)
                  .put("rule", rule == null ? "" : rule))
              .put("limit", limit)
              .put("truncated", rows.length() >= limit)
              .put("scope", new JSONObject()
                  .put("clients", new JSONArray(List.of(UikQuery.readableClients())))
                  .put("orgs", new JSONArray(List.of(UikQuery.readableOrgs())))));
    } catch (Exception e) {
      log.error("ETDEMO_Alerts failed: {}", e.getMessage(), e);
      return error(e);
    }
  }

  private JSONObject error(Exception e) {
    try {
      return new JSONObject().put("error",
          new JSONObject().put("message", e.getMessage() == null ? e.toString() : e.getMessage()));
    } catch (Exception ignored) {
      return new JSONObject();
    }
  }

  /**
   * One count per status over the whole visible set, filter ignored. Every status of
   * {@link #STATUSES} is present even at zero: a bucket that disappears when it empties makes the
   * rail change shape under the reader, and "no solved alerts" is itself the answer to a question.
   */
  private JSONObject statuses(Connection conn) throws Exception {
    final JSONObject out = new JSONObject();
    for (String s : STATUSES) {
      out.put(s, 0L);
    }
    final String sql = "select " + ST + " as st, count(*) as n" + FROM + " where " + VIS
        + " group by " + ST;
    try (PreparedStatement st = conn.prepareStatement(sql)) {
      bindVis(st, 1);
      try (ResultSet rs = st.executeQuery()) {
        while (rs.next()) {
          out.put(rs.getString("st"), rs.getLong("n"));
        }
      }
    }
    return out;
  }

  /**
   * One row per rule that has any visible alert at all, with its per-status breakdown and the tab
   * its records live on. Filter ignored, for the same reason as {@link #statuses(Connection)}.
   *
   * Ordered by count descending, which puts the rule with the most to answer for first. On this
   * instance that is the purchase-order payment plan rule -- the only one of the three whose
   * records are business documents rather than dictionary metadata.
   */
  private JSONArray rules(Connection conn) throws Exception {
    final String sql = "select r.ad_alertrule_id as id, r.name as name,"
        + " max(t.ad_tab_id) as tab, count(*) as n,"
        + " count(*) filter (where " + ST + " = 'NEW') as n_new,"
        + " count(*) filter (where " + ST + " = 'ACKNOWLEDGED') as n_ack,"
        + " count(*) filter (where " + ST + " = 'SOLVED') as n_solved,"
        + " count(*) filter (where " + ST + " = 'SUPPRESSED') as n_suppressed"
        + FROM + " where " + VIS
        + " group by r.ad_alertrule_id, r.name order by count(*) desc, r.name";
    try (PreparedStatement st = conn.prepareStatement(sql)) {
      bindVis(st, 1);
      try (ResultSet rs = st.executeQuery()) {
        return UikQuery.rows(rs, UikQuery.str("id", "id"), UikQuery.str("name", "name"),
            UikQuery.str("tab", "tab"), UikQuery.num("n", "n"),
            UikQuery.num("NEW", "n_new"), UikQuery.num("ACKNOWLEDGED", "n_ack"),
            UikQuery.num("SOLVED", "n_solved"), UikQuery.num("SUPPRESSED", "n_suppressed"));
      }
    }
  }

  /**
   * The detail list, and the only output that narrows. {@code referencekey_id} is the record the
   * alert is about and {@code tab} the tab that shows it; either one missing means the client
   * renders plain text instead of a link, because an unavailable drill-down is a smaller failure
   * than a wrong one.
   */
  private JSONArray rows(Connection conn, String status, String rule, int limit) throws Exception {
    final String sql = "select a.ad_alert_id as id, " + ST + " as st,"
        + " r.ad_alertrule_id as rule, r.name as rulename,"
        + " coalesce(a.description, '') as description, coalesce(a.record_id, '') as record,"
        + " coalesce(a.referencekey_id, '') as refkey, t.ad_tab_id as tab,"
        + " coalesce(o.name, '') as orgname, a.created as created"
        + FROM + " left join ad_org o on o.ad_org_id = a.ad_org_id"
        + " where " + VIS
        + " and (?::text is null or " + ST + " = ?)"
        + " and (?::text is null or r.ad_alertrule_id = ?)"
        + " order by a.created desc, a.ad_alert_id limit ?";
    try (PreparedStatement st = conn.prepareStatement(sql)) {
      int i = bindVis(st, 1);
      st.setString(i++, status);
      st.setString(i++, status);
      st.setString(i++, rule);
      st.setString(i++, rule);
      st.setInt(i, limit);
      try (ResultSet rs = st.executeQuery()) {
        return UikQuery.rows(rs, UikQuery.str("id", "id"), UikQuery.str("status", "st"),
            UikQuery.str("rule", "rule"), UikQuery.str("ruleName", "rulename"),
            UikQuery.str("description", "description"), UikQuery.str("record", "record"),
            UikQuery.str("refkey", "refkey"), UikQuery.str("tab", "tab"),
            UikQuery.str("org", "orgname"), UikQuery.date("created", "created"));
      }
    }
  }
}
