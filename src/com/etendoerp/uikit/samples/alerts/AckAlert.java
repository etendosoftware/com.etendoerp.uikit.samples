package com.etendoerp.uikit.samples.alerts;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.Map;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.codehaus.jettison.json.JSONObject;
import org.openbravo.dal.core.OBContext;
import org.openbravo.erpCommon.utility.OBMessageUtils;

import com.etendoerp.uikit.server.UikAction;
import com.etendoerp.uikit.server.UikQuery;

/**
 * Acknowledges one alert: {@code NEW -> ACKNOWLEDGED}, and nothing else.
 *
 * The only write in the sample kit, so it is also the only place where the CSRF gate and the
 * scoped re-read are exercised rather than described. {@link UikAction} verifies the token in a
 * final {@code execute} before {@link #run(JSONObject, Map)} is entered; everything below assumes
 * the token was good and still trusts nothing else about the request.
 *
 * Three things arrive from the browser and exactly one of them is used: {@code id}. The client
 * also sends {@code status}, because the optimistic repaint needs a value to paint and the
 * manifest's replayable payload carries one, but this handler never reads it. A status supplied by
 * the caller would make the whole transition check a formality -- the caller would be asserting
 * the precondition it is being tested against.
 *
 * The transition table is a whitelist, not a guard. {@link #TRANSITIONS} maps the states a write
 * may start from to the state it produces; a status absent from the map is refused with the status
 * named in the message, so the four SUPPRESSED-to-ACKNOWLEDGED attempts a curious user will make
 * come back as a sentence instead of a 500.
 *
 * Idempotent on purpose: acknowledging an already-acknowledged alert succeeds with
 * {@code changed: false}. That is what makes the manifest's {@code writes[]} payload safe to
 * replay -- the gate posts it on every run -- and it is also the honest answer to a double click
 * that beat the in-flight guard by arriving from two tabs.
 *
 * No explicit commit. The DAL request filter commits the borrowed connection in
 * {@code DalThreadHandler.doFinal} when the request ends without error, and rolls it back
 * otherwise, so a raw-SQL update here participates in the request's own transaction.
 */
public class AckAlert extends UikAction {

  private static final Logger log = LogManager.getLogger();

  /**
   * The whitelist. Read it as the complete set of writes this handler can perform: one.
   *
   * SOLVED and SUPPRESSED are deliberately absent. Re-opening a resolved alert or un-silencing a
   * suppressed one are different decisions with different consequences, and a window whose single
   * button quietly performs whichever of them the row happens to need is a window nobody can
   * reason about.
   */
  private static final Map<String, String> TRANSITIONS = Map.of("NEW", "ACKNOWLEDGED");

  @Override
  protected JSONObject run(JSONObject payload, Map<String, Object> parameters) throws Exception {
    final String id = payload.optString("id", "").trim();
    if (id.isEmpty()) {
      return reject("ETDEMO_AlertsNotVisible", null);
    }
    final Connection conn = UikQuery.connection();

    // The authorization. Fact F6: the window granted the caller nothing, so this scoped read --
    // the same predicate the inbox reads with -- is the entire access decision, and an id that
    // does not come back is answered exactly like an id that does not exist.
    final String current = visibleStatus(conn, id);
    if (current == null) {
      log.warn("AckAlert refused: alert {} not visible to role {}", id,
          OBContext.getOBContext().getRole().getId());
      return reject("ETDEMO_AlertsNotVisible", null);
    }

    final String target = TRANSITIONS.get(current);
    if (target == null) {
      if ("ACKNOWLEDGED".equals(current)) {
        return done(id, current, false);
      }
      return reject("ETDEMO_AlertsBadTransition", current);
    }

    // Re-stated in the UPDATE itself. The read above and the write below are two statements, and
    // between them another session can acknowledge the same row; repeating the status and the
    // visibility predicate in the WHERE makes the update a no-op in that case instead of a second
    // acknowledgement, and zero rows affected is then reported rather than claimed as a success.
    if (apply(conn, id, current, target) != 1) {
      log.warn("AckAlert affected no row for alert {}; status changed underneath the read", id);
      return reject("ETDEMO_AlertsBadTransition", current);
    }
    return done(id, target, true);
  }

  /** The row's normalised status if this role may see it, {@code null} if it may not. */
  private String visibleStatus(Connection conn, String id) throws Exception {
    final String sql = "select " + AlertInbox.ST + " as st" + AlertInbox.FROM
        + " where " + AlertInbox.VIS + " and a.ad_alert_id = ?";
    try (PreparedStatement st = conn.prepareStatement(sql)) {
      final int i = AlertInbox.bindVis(st, 1);
      st.setString(i, id);
      try (ResultSet rs = st.executeQuery()) {
        return rs.next() ? rs.getString("st") : null;
      }
    }
  }

  /**
   * The write. Scoped, status-guarded, and single-row by primary key.
   *
   * The EXISTS subquery re-opens {@code ad_alert} under the same alias, so its {@code a}
   * shadows the one being updated. That is deliberate: the subquery is a self-contained
   * "is this id visible" test with the id bound again, not a correlation, and writing it any
   * other way would mean keeping a second copy of the visibility predicate under a second
   * alias.
   */
  private int apply(Connection conn, String id, String from, String to) throws Exception {
    final String sql = "update ad_alert a set status = ?, updated = now(), updatedby = ?"
        + " where a.ad_alert_id = ? and " + AlertInbox.ST + " = ?"
        + " and exists (select 1" + AlertInbox.FROM + " where " + AlertInbox.VIS
        + " and a.ad_alert_id = ?)";
    try (PreparedStatement st = conn.prepareStatement(sql)) {
      int i = 1;
      st.setString(i++, to);
      st.setString(i++, OBContext.getOBContext().getUser().getId());
      st.setString(i++, id);
      st.setString(i++, from);
      i = AlertInbox.bindVis(st, i);
      st.setString(i, id);
      return st.executeUpdate();
    }
  }

  private JSONObject done(String id, String status, boolean changed) throws Exception {
    return new JSONObject().put("id", id).put("status", status).put("changed", changed);
  }

  /**
   * A domain rejection, and a framework wart worth knowing about: {@link UikAction} stamps
   * {@code success: true} onto whatever {@code run} returns, so this envelope carries both that
   * marker and an {@code error} key. Both readers that matter check {@code error} first -- the
   * runtime's {@code envelopeError} and the window gate's {@code rejection()} -- so the rejection
   * is read as a rejection. The alternative, throwing, would be reduced to the generic
   * {@code ETUIK_Failed} message and lose the reason.
   */
  private JSONObject reject(String code, String detail) throws Exception {
    String message = OBMessageUtils.messageBD(code);
    if (message == null || message.trim().isEmpty()) {
      message = code;
    }
    if (detail != null) {
      message = message + " " + detail + ".";
    }
    return new JSONObject().put("error", new JSONObject().put("code", code)
        .put("message", message));
  }
}
