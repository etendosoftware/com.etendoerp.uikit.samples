package com.etendoerp.uikit.samples.picking;

import java.sql.Connection;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.codehaus.jettison.json.JSONArray;
import org.codehaus.jettison.json.JSONObject;
import org.openbravo.advpaymentmngt.ProcessOrderUtil;
import org.openbravo.base.secureApp.VariablesSecureApp;
import org.openbravo.base.weld.WeldUtils;
import org.openbravo.dal.core.OBContext;
import org.openbravo.erpCommon.utility.OBError;
import org.openbravo.erpCommon.utility.OBMessageUtils;
import org.openbravo.service.db.DalConnectionProvider;
import org.openbravo.client.kernel.RequestContext;

import com.etendoerp.uikit.server.UikAction;
import com.etendoerp.uikit.server.UikQuery;

/**
 * Runs one document action on one sales order: {@code DR -> CO}, or {@code CO -> RE}. The only
 * sample write that mutates a real ERP document, through the very process core's own Sales Order
 * window calls.
 *
 * Payload: {@code orderId}, optionally {@code action}, optionally {@code dryRun}.
 *
 * <b>The dry run is the default, and that is the whole safety story.</b> A payload without
 * {@code dryRun}, with a malformed one, or with anything that is not literally false, simulates:
 * it re-reads the order, asks core which actions it would accept, reports the verdict and touches
 * nothing. Only an explicit {@code dryRun: false} -- which the window sends from a second,
 * separate, deliberately ugly control -- reaches {@link ProcessOrderUtil}. Fail-safe by
 * construction rather than by the caller remembering a flag.
 *
 * {@code action} is checked, never obeyed. {@link PickList#TRANSITIONS} decides what runs; if the
 * browser named a different action the request is refused instead of quietly doing the whitelisted
 * one, because a caller asking for {@code VO} and getting {@code CO} was lied to.
 *
 * Order of operations, and it is not negotiable:
 *
 * <ol>
 * <li>Every read the response needs happens <em>before</em> {@code process()}.
 * {@link ProcessOrderUtil} calls {@code commitAndClose()} on the DAL session, so the connection
 * this handler was reading on is gone by the time it returns -- ProcessOrderUtil.java line 124,
 * {@code commitAndClose()} -- and any lazily-fetched field would explode.</li>
 * <li>The post-state, which the screen shows next to the pre-state, is read on a connection
 * opened afterwards by a fresh {@link DalConnectionProvider}.</li>
 * <li>The processor is obtained through Weld and never with {@code new}: it injects an
 * {@code Instance<ProcessOrderHook>} and a hand-built one would have a null hook list.</li>
 * </ol>
 *
 * The ERP's own message is passed through verbatim. {@code OBError.getMessage()} is what core
 * decided to tell the user -- "The order cannot be booked because it has no lines", translated
 * through core's own message table -- and rewriting, prefixing or prettifying it would replace a
 * true statement about the document with a guess.
 */
public class ConfirmOrder extends UikAction {

  private static final Logger log = LogManager.getLogger();

  /** {@code C_Order}. The reference list core keys document actions by is {@code 135}. */
  private static final String ORDER_TABLE = "259";

  @Override
  protected JSONObject run(JSONObject payload, Map<String, Object> parameters) throws Exception {
    final String id = payload.optString("orderId", "").trim();
    if (id.isEmpty()) {
      return reject("ETDEMO_PickingNotVisible", null);
    }
    final boolean dry = isDryRun(payload);
    final Connection conn = UikQuery.connection();

    // The authorization. Fact F6: the window granted the caller nothing, so this scoped re-read
    // -- the same predicate, the same SQL, that the selector listed with -- is the entire access
    // decision, and an id that does not come back is answered exactly like one that never
    // existed.
    final JSONObject head = PickList.head(conn, id);
    if (head == null) {
      log.warn("ConfirmOrder refused: order {} not visible to role {}", id,
          OBContext.getOBContext().getRole().getId());
      return reject("ETDEMO_PickingNotVisible", null);
    }

    final String current = head.getString("status");
    final String target = PickList.TRANSITIONS.get(current);
    if (target == null) {
      return reject("ETDEMO_PickingBadTransition", current);
    }
    final String asked = payload.optString("action", "").trim();
    if (!asked.isEmpty() && !asked.equals(target)) {
      log.warn("ConfirmOrder refused: order {} is {}, caller asked for {}", id, current, asked);
      return reject("ETDEMO_PickingBadAction", asked);
    }

    // Read before writing, always: core's own opinion of what this state accepts. Reported in
    // both modes, so the simulation shows the reader what the real run will be allowed to do.
    final JSONArray allowed = allowed(current, target, head.optString("processing", "N"));

    final JSONObject out = new JSONObject()
        .put("orderId", id)
        .put("documentNo", head.getString("documentNo"))
        .put("action", target)
        .put("dryRun", dry)
        .put("before", current)
        .put("allowed", allowed);

    if (dry) {
      // Nothing was touched, and nothing will be. The verdict is core's own action list.
      return out.put("applied", false).put("after", current)
          .put("permitted", contains(allowed, target))
          .put("message", OBMessageUtils.messageBD("ETDEMO_PickingDryDone"));
    }

    final VariablesSecureApp vars = RequestContext.get().getVariablesSecureApp();
    final ProcessOrderUtil processor =
        WeldUtils.getInstanceFromStaticBeanManager(ProcessOrderUtil.class);
    final OBError result = processor.process(id, target, vars, new DalConnectionProvider(false));

    // Past this line the session the reads above used is committed and closed. Everything the
    // response still needs either lives in `out` already or comes off a new connection.
    final String after = statusNow(id, current);
    out.put("after", after).put("applied", !current.equals(after));
    if (result != null && "Error".equalsIgnoreCase(result.getType())) {
      // The document refused. ProcessOrderUtil already rolled its transaction back, so `after`
      // equals `before` and the row is intact; the only thing to report is what core said.
      log.info("ConfirmOrder: {} on order {} refused by the ERP: {}", target, id,
          result.getMessage());
      return out.put("error", new JSONObject().put("code", "ETDEMO_PickingErpError")
          .put("message", verbatim(result)));
    }
    return out.put("message", verbatim(result));
  }

  /**
   * True unless the caller said, in so many words, that this is not a simulation.
   *
   * Deliberately not {@code optBoolean("dryRun", true)}: that helper reads a missing key and a
   * malformed one the same way it reads {@code false} in some spellings, and the direction a
   * parsing mistake falls in has to be "simulate", never "mutate".
   */
  private boolean isDryRun(JSONObject payload) {
    final Object flag = payload.opt("dryRun");
    if (Boolean.FALSE.equals(flag)) {
      return false;
    }
    return !"false".equalsIgnoreCase(String.valueOf(flag));
  }

  /**
   * What core would accept from this state, straight from the dictionary's action list.
   *
   * Guarded: {@code ActionButtonUtility.docAction} returns null from its own catch block, and
   * {@code getDocumentActionList} then iterates it and throws a NullPointerException. An empty
   * list is the honest answer -- "core told us nothing" -- and it is never used as permission to
   * proceed, only as information printed next to the verdict.
   */
  private JSONArray allowed(String current, String target, String processing) {
    final List<String> actions = new ArrayList<>();
    try {
      final List<String> core = ProcessOrderUtil.getDocumentActionList(current, target,
          "Y".equals(processing) ? "Y" : "N", ORDER_TABLE,
          RequestContext.get().getVariablesSecureApp(), new DalConnectionProvider(false));
      if (core != null) {
        actions.addAll(core);
      }
    } catch (RuntimeException e) {
      log.warn("ConfirmOrder: core's action list for status {} is unavailable: {}", current,
          e.toString());
    }
    return new JSONArray(actions);
  }

  private boolean contains(JSONArray list, String value) {
    for (int i = 0; i < list.length(); i++) {
      if (value.equals(list.optString(i))) {
        return true;
      }
    }
    return false;
  }

  /**
   * The order's status after the process, on a connection opened after it. A failure to re-read
   * degrades to the status read before: reporting the old value is wrong by at most one refresh,
   * while failing the whole request would hide a mutation that did happen.
   */
  private String statusNow(String id, String fallback) {
    try (Connection fresh = new DalConnectionProvider(false).getConnection()) {
      final JSONObject head = PickList.head(fresh, id);
      return head == null ? fallback : head.getString("status");
    } catch (Exception e) {
      log.warn("ConfirmOrder: post-state of order {} unreadable: {}", id, e.toString());
      return fallback;
    }
  }

  /** The ERP's sentence, exactly as the ERP wrote it. */
  private String verbatim(OBError result) {
    if (result == null) {
      return "";
    }
    final String message = result.getMessage();
    return message == null ? "" : message;
  }

  /**
   * A domain rejection: {@code error} in the envelope, which {@link UikAction} stamps
   * {@code success: false}, and never a throw -- BaseActionHandler would reduce every reason to
   * the generic ETUIK_Failed and the reader would learn nothing.
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
