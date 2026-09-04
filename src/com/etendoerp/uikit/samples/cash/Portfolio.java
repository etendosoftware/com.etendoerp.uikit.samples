package com.etendoerp.uikit.samples.cash;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.LinkedHashMap;
import java.util.Map;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.codehaus.jettison.json.JSONArray;
import org.codehaus.jettison.json.JSONObject;
import org.openbravo.client.kernel.BaseActionHandler;

import com.etendoerp.uikit.server.UikQuery;

/**
 * Datasource ETDEMO_CashPortfolio: the whole receivable/payable portfolio for one side, one
 * currency and one reference date, in a single call.
 *
 * Reached at {@code org.openbravo.client.kernel?action=com.etendoerp.uikit.samples.cash.Portfolio}.
 * KernelServlet resolves an action handler by class name, so this endpoint needs no AD row.
 *
 * Accepted parameters, all optional:
 *
 * <ul>
 * <li>{@code side} -- {@code AP} (the default) or {@code AR}. See section 0 of
 * docs/samples/cash-portfolio.md for why the default is the payables side.</li>
 * <li>{@code asOf} -- {@code yyyy-MM-dd}. Absent, the reference date is the newest due date in
 * the readable outstanding portfolio; see {@link UikQuery#asOf}. A malformed value is treated as
 * absent rather than as an error: the answer carries {@code asOfSource}, so the screen can always
 * say which date is in force and where it came from.</li>
 * <li>{@code cur} -- a {@code C_Currency_ID}. Absent, the currency carrying the largest
 * outstanding amount on the side. Rows in any other currency are excluded and counted, never
 * summed with these: a total across currencies is a number with no meaning.</li>
 * <li>{@code bucket} -- one of {@code cur d30 d60 d90 d90p}. It narrows {@code partners} and
 * {@code rows} and nothing else. {@code buckets}, {@code total}, {@code currencies},
 * {@code sides} and {@code series} are computed over the whole side, ignoring it, because the
 * rail has to keep showing the reader what they are not looking at.</li>
 * </ul>
 *
 * Every query is scoped with {@link UikQuery#scopeClause}: fact F6 records that ViewComponent
 * serves a view without consulting OBUIAPP_View_Role_Access, so this is the only place the
 * portfolio is filtered by who is asking. The scope actually applied is reported back under
 * {@code meta}, which is what lets the window's gate recompute the arithmetic independently.
 */
public class Portfolio extends BaseActionHandler {

  private static final Logger log = LogManager.getLogger();

  /**
   * Core window ids for the two invoice windows. Only the *window* is a constant here; the tab is
   * resolved from the dictionary by {@link UikQuery#tabFor}, because c_invoice is shown by several
   * tabs and the wrong one opens the wrong document type on the right record.
   */
  private static final String WINDOW_PURCHASE_INVOICE = "183";
  private static final String WINDOW_SALES_INVOICE = "167";

  private static final String[] BUCKETS = { "cur", "d30", "d60", "d90", "d90p" };
  private static final int MONTHS = 12;
  private static final DateTimeFormatter MONTH = DateTimeFormatter.ofPattern("yyyy-MM");

  @Override
  protected JSONObject execute(Map<String, Object> parameters, String content) {
    try {
      final Connection conn = UikQuery.connection();
      final String side = "AR".equals(UikQuery.param(parameters, "side")) ? "AR" : "AP";
      // Whitelisted from our own two constants, never from the request: it reaches SQL inline.
      final String sotrx = "AR".equals(side) ? "Y" : "N";
      final String bucket = bucketParam(UikQuery.param(parameters, "bucket"));

      final JSONObject ref = UikQuery.asOf(conn, isoDate(UikQuery.param(parameters, "asOf")),
          maxDateSql());
      final String asOf = ref.getString("asOf");

      final JSONObject out = new JSONObject();
      out.put("asOf", asOf);
      out.put("asOfSource", ref.getString("asOfSource"));
      out.put("side", side);
      out.put("bucket", bucket == null ? JSONObject.NULL : bucket);
      out.put("sides", sides(conn));

      final JSONArray currencies = currencies(conn, asOf, sotrx);
      final JSONObject currency = pickCurrency(currencies, UikQuery.param(parameters, "cur"));
      out.put("currencies", currencies);
      out.put("currency", currency == null ? JSONObject.NULL : currency);
      out.put("excluded", excluded(currencies, currency));
      if (currency == null) {
        // Nothing readable on this side: every list is empty and the view renders its own note.
        out.put("buckets", buckets(new JSONArray()));
        out.put("total", new JSONObject().put("docs", 0).put("amount", 0));
        out.put("partners", new JSONArray());
        out.put("rows", new JSONArray());
        out.put("series", series(conn, asOf, sotrx, null));
        out.put("meta", meta(conn, side));
        return out;
      }
      final String cur = currency.getString("id");
      out.put("buckets", buckets(bucketRows(conn, asOf, sotrx, cur)));
      out.put("total", total(conn, asOf, sotrx, cur));
      out.put("partners", partners(conn, asOf, sotrx, cur, bucket));
      out.put("rows", rows(conn, asOf, sotrx, cur, bucket));
      out.put("series", series(conn, asOf, sotrx, cur));
      out.put("meta", meta(conn, side));
      return out;
    } catch (Exception e) {
      log.error("ETDEMO_CashPortfolio failed: {}", e.getMessage(), e);
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

  /* ------------------------------------------------------------------ parameter hygiene */

  /** {@code yyyy-MM-dd} or null. A malformed date is "not supplied", never a SQL error. */
  private static String isoDate(String raw) {
    if (raw == null || !raw.matches("\\d{4}-\\d{2}-\\d{2}")) {
      return null;
    }
    try {
      return LocalDate.parse(raw).toString();
    } catch (Exception e) {
      return null;
    }
  }

  /** One of the five bucket ids, or null for "every bucket". */
  private static String bucketParam(String raw) {
    for (String id : BUCKETS) {
      if (id.equals(raw)) {
        return id;
      }
    }
    return null;
  }

  /* ---------------------------------------------------------------------------- the SQL */

  /**
   * The reference-date fallback {@link UikQuery#asOf} runs when the caller passed none: the newest
   * due date still outstanding in the readable portfolio, both sides together.
   *
   * Both sides on purpose. The reference date is a property of the instance's data, not of which
   * half of it is on screen, so flipping the side must not move the date under the reader -- and a
   * side with no outstanding documents at all would otherwise fall through to {@code today}, which
   * on this 2021 dataset is exactly the lie decision D5 exists to prevent.
   */
  private static String maxDateSql() {
    return "select max(ps.duedate) from fin_payment_schedule ps"
        + " join c_invoice i on i.c_invoice_id = ps.c_invoice_id" + " where "
        + UikQuery.scopeClause("ps") + " and i.isactive = 'Y' and ps.outstandingamt > 0";
  }

  /**
   * The common table expression every portfolio query reads: one row per outstanding payment
   * schedule of one side, with its age in days against the reference date and the bucket that age
   * falls in. Bind index 1 is the reference date; {@link UikQuery#bindScope} starts at 2.
   *
   * The age is computed once and the bucket derived from it, rather than repeating the date in
   * five comparisons: one bind, one definition, and the gate can recompute it from the same
   * sentence. {@code cur} is "not due yet" -- a negative age -- so a document due exactly on the
   * reference date is already in the first overdue bucket.
   */
  private static String base(String sotrx) {
    return "with base as (select ps.fin_payment_schedule_id as id, i.c_invoice_id as invoice,"
        + " i.documentno as documentno, i.dateinvoiced as dateinvoiced, ps.duedate as duedate,"
        + " ps.outstandingamt as amount, ps.c_currency_id as currency,"
        + " i.c_bpartner_id as partner, bp.name as partnername,"
        + " (?::date - ps.duedate::date) as days"
        + " from fin_payment_schedule ps"
        + " join c_invoice i on i.c_invoice_id = ps.c_invoice_id"
        + " join c_bpartner bp on bp.c_bpartner_id = i.c_bpartner_id" + " where "
        + UikQuery.scopeClause("ps") + " and i.isactive = 'Y' and ps.outstandingamt > 0"
        + " and i.issotrx = '" + sotrx + "'"
        + "), aged as (select b.*, case when b.days < 0 then 'cur'"
        + " when b.days <= 30 then 'd30' when b.days <= 60 then 'd60'"
        + " when b.days <= 90 then 'd90' else 'd90p' end as bucket from base b) ";
  }

  /**
   * Both sides, always both rows, so the switch can state the imbalance instead of hiding it. No
   * amount: the two sides span different currencies and adding them would produce a number that
   * means nothing.
   */
  private JSONArray sides(Connection conn) throws Exception {
    final String sql = "select i.issotrx as sotrx, count(*) as docs,"
        + " count(distinct i.c_bpartner_id) as partners,"
        + " count(distinct ps.c_currency_id) as currencies,"
        + " min(ps.duedate) as oldest, max(ps.duedate) as newest"
        + " from fin_payment_schedule ps"
        + " join c_invoice i on i.c_invoice_id = ps.c_invoice_id" + " where "
        + UikQuery.scopeClause("ps") + " and i.isactive = 'Y' and ps.outstandingamt > 0"
        + " group by 1";
    final Map<String, JSONObject> found = new LinkedHashMap<>();
    try (PreparedStatement st = conn.prepareStatement(sql)) {
      UikQuery.bindScope(st, 1);
      try (ResultSet rs = st.executeQuery()) {
        final JSONArray raw = UikQuery.rows(rs, UikQuery.str("sotrx", "sotrx"),
            UikQuery.num("docs", "docs"), UikQuery.num("partners", "partners"),
            UikQuery.num("currencies", "currencies"), UikQuery.date("oldest", "oldest"),
            UikQuery.date("newest", "newest"));
        for (int i = 0; i < raw.length(); i++) {
          final JSONObject row = raw.getJSONObject(i);
          found.put("Y".equals(row.getString("sotrx")) ? "AR" : "AP", row);
        }
      }
    }
    final JSONArray out = new JSONArray();
    for (String id : new String[] { "AR", "AP" }) {
      final JSONObject row = found.get(id);
      if (row != null) {
        // issotrx was only the group-by key; the answer speaks of AR and AP, not of a flag.
        row.remove("sotrx");
      }
      out.put(row == null ? emptySide(id) : row.put("id", id));
    }
    return out;
  }

  private static JSONObject emptySide(String id) throws Exception {
    return new JSONObject().put("id", id).put("docs", 0).put("partners", 0).put("currencies", 0)
        .put("oldest", JSONObject.NULL).put("newest", JSONObject.NULL);
  }

  /** Every currency present on the side, largest outstanding first. Ignores the bucket filter. */
  private JSONArray currencies(Connection conn, String asOf, String sotrx) throws Exception {
    final String sql = base(sotrx) + "select a.currency as id, c.iso_code as iso,"
        + " coalesce(nullif(c.cursymbol, ''), c.iso_code) as symbol,"
        + " count(*) as docs, sum(a.amount) as amount"
        + " from aged a join c_currency c on c.c_currency_id = a.currency"
        + " group by 1, 2, 3 order by sum(a.amount) desc, c.iso_code";
    try (PreparedStatement st = conn.prepareStatement(sql)) {
      st.setString(1, asOf);
      UikQuery.bindScope(st, 2);
      try (ResultSet rs = st.executeQuery()) {
        return UikQuery.rows(rs, UikQuery.str("id", "id"), UikQuery.str("iso", "iso"),
            UikQuery.str("symbol", "symbol"), UikQuery.num("docs", "docs"),
            UikQuery.num("amount", "amount"));
      }
    }
  }

  /** The requested currency when it exists on the side, else the largest, else null. */
  private static JSONObject pickCurrency(JSONArray currencies, String requested) throws Exception {
    if (currencies.length() == 0) {
      return null;
    }
    if (requested != null) {
      for (int i = 0; i < currencies.length(); i++) {
        if (requested.equals(currencies.getJSONObject(i).getString("id"))) {
          return currencies.getJSONObject(i);
        }
      }
    }
    return currencies.getJSONObject(0);
  }

  /**
   * How many documents the currency filter is hiding, and in which currencies. A count, never a
   * sum: the whole reason these rows are out is that their amounts do not add to the ones in.
   */
  private static JSONObject excluded(JSONArray currencies, JSONObject kept) throws Exception {
    final JSONArray others = new JSONArray();
    int docs = 0;
    for (int i = 0; i < currencies.length(); i++) {
      final JSONObject row = currencies.getJSONObject(i);
      if (kept != null && kept.getString("id").equals(row.getString("id"))) {
        continue;
      }
      docs += (int) row.getDouble("docs");
      others.put(new JSONObject().put("iso", row.getString("iso")).put("docs",
          row.getDouble("docs")));
    }
    return new JSONObject().put("docs", docs).put("currencies", others);
  }

  private JSONArray bucketRows(Connection conn, String asOf, String sotrx, String cur)
      throws Exception {
    final String sql = base(sotrx) + "select a.bucket as bucket, count(*) as docs,"
        + " sum(a.amount) as amount from aged a where a.currency = ? group by 1";
    try (PreparedStatement st = conn.prepareStatement(sql)) {
      st.setString(1, asOf);
      st.setString(UikQuery.bindScope(st, 2), cur);
      try (ResultSet rs = st.executeQuery()) {
        return UikQuery.rows(rs, UikQuery.str("bucket", "bucket"), UikQuery.num("docs", "docs"),
            UikQuery.num("amount", "amount"));
      }
    }
  }

  /**
   * The five buckets in age order, with the empty ones filled in here rather than dropped by the
   * {@code group by}. A rail missing its zero buckets tells the reader the bucket does not exist
   * instead of that it is empty, and the bars would silently change width between two loads.
   */
  private static JSONArray buckets(JSONArray found) throws Exception {
    final Map<String, JSONObject> byId = new LinkedHashMap<>();
    for (int i = 0; i < found.length(); i++) {
      byId.put(found.getJSONObject(i).getString("bucket"), found.getJSONObject(i));
    }
    final JSONArray out = new JSONArray();
    for (String id : BUCKETS) {
      final JSONObject row = byId.get(id);
      out.put(new JSONObject().put("id", id)
          .put("docs", row == null ? 0 : (int) row.getDouble("docs"))
          .put("amount", row == null ? 0 : row.getDouble("amount")));
    }
    return out;
  }

  /** The side's own total, queried on its own so that "the buckets add up" is a real assertion. */
  private JSONObject total(Connection conn, String asOf, String sotrx, String cur)
      throws Exception {
    final String sql = base(sotrx) + "select count(*) as docs,"
        + " coalesce(sum(a.amount), 0) as amount from aged a where a.currency = ?";
    try (PreparedStatement st = conn.prepareStatement(sql)) {
      st.setString(1, asOf);
      st.setString(UikQuery.bindScope(st, 2), cur);
      try (ResultSet rs = st.executeQuery()) {
        final JSONArray one = UikQuery.rows(rs, UikQuery.num("docs", "docs"),
            UikQuery.num("amount", "amount"));
        return one.length() == 0 ? new JSONObject().put("docs", 0).put("amount", 0)
            : one.getJSONObject(0);
      }
    }
  }

  private JSONArray partners(Connection conn, String asOf, String sotrx, String cur, String bucket)
      throws Exception {
    final String sql = base(sotrx) + "select a.partner as id, a.partnername as name,"
        + " count(*) as docs, sum(a.amount) as amount, min(a.duedate) as oldest,"
        + " max(a.days) as maxdays from aged a where a.currency = ?"
        + (bucket == null ? "" : " and a.bucket = ?")
        + " group by 1, 2 order by sum(a.amount) desc, a.partnername";
    try (PreparedStatement st = conn.prepareStatement(sql)) {
      st.setString(1, asOf);
      int i = UikQuery.bindScope(st, 2);
      st.setString(i++, cur);
      if (bucket != null) {
        st.setString(i, bucket);
      }
      try (ResultSet rs = st.executeQuery()) {
        return UikQuery.rows(rs, UikQuery.str("id", "id"), UikQuery.str("name", "name"),
            UikQuery.num("docs", "docs"), UikQuery.num("amount", "amount"),
            UikQuery.date("oldest", "oldest"), UikQuery.num("maxDays", "maxdays"));
      }
    }
  }

  private JSONArray rows(Connection conn, String asOf, String sotrx, String cur, String bucket)
      throws Exception {
    final String sql = base(sotrx) + "select a.id as id, a.invoice as invoice,"
        + " a.documentno as documentno, a.dateinvoiced as dateinvoiced, a.duedate as duedate,"
        + " a.amount as amount, a.partner as partner, a.partnername as partnername,"
        + " a.days as days, a.bucket as bucket, a.currency as currency from aged a"
        + " where a.currency = ?" + (bucket == null ? "" : " and a.bucket = ?")
        + " order by a.partnername, a.duedate, a.documentno";
    try (PreparedStatement st = conn.prepareStatement(sql)) {
      st.setString(1, asOf);
      int i = UikQuery.bindScope(st, 2);
      st.setString(i++, cur);
      if (bucket != null) {
        st.setString(i, bucket);
      }
      try (ResultSet rs = st.executeQuery()) {
        return UikQuery.rows(rs, UikQuery.str("id", "id"), UikQuery.str("invoice", "invoice"),
            UikQuery.str("doc", "documentno"), UikQuery.date("invoiced", "dateinvoiced"),
            UikQuery.date("due", "duedate"), UikQuery.num("amount", "amount"),
            UikQuery.str("partner", "partner"), UikQuery.str("partnerName", "partnername"),
            UikQuery.num("days", "days"), UikQuery.str("bucket", "bucket"),
            UikQuery.str("currency", "currency"));
      }
    }
  }

  /**
   * Twelve consecutive months of settled cash, oldest first, ending in the month of the reference
   * date. fin_payment is the only dense series in this instance -- roughly twenty movements a
   * month from 2011 to mid-2021 -- and it tells receipts from payments by {@code isreceipt}, not
   * by {@code issotrx}.
   *
   * The months are generated here and the SQL result merged into them, because a {@code group by
   * month} returns no row for a month with no payments and a sparkline over a gapped series lies
   * about the spacing: nine points drawn across twelve months puts the line's last step three
   * months early. Filling in SQL would need a generate_series join for one number per month; the
   * calendar is the client's problem, so it is solved on the client's side of the query.
   */
  private JSONArray series(Connection conn, String asOf, String sotrx, String cur)
      throws Exception {
    final Map<String, JSONObject> found = new LinkedHashMap<>();
    if (cur != null) {
      final String sql = "select to_char(date_trunc('month', p.paymentdate), 'YYYY-MM') as m,"
          + " count(*) as docs, sum(p.amount) as amount from fin_payment p" + " where "
          + UikQuery.scopeClause("p") + " and p.isreceipt = '" + sotrx + "'"
          + " and p.c_currency_id = ? and p.paymentdate is not null"
          + " and p.paymentdate >= date_trunc('month', ?::date) - interval '11 months'"
          + " and p.paymentdate < date_trunc('month', ?::date) + interval '1 month'"
          + " group by 1";
      try (PreparedStatement st = conn.prepareStatement(sql)) {
        int i = UikQuery.bindScope(st, 1);
        st.setString(i++, cur);
        st.setString(i++, asOf);
        st.setString(i, asOf);
        try (ResultSet rs = st.executeQuery()) {
          final JSONArray raw = UikQuery.rows(rs, UikQuery.str("month", "m"),
              UikQuery.num("docs", "docs"), UikQuery.num("amount", "amount"));
          for (int r = 0; r < raw.length(); r++) {
            found.put(raw.getJSONObject(r).getString("month"), raw.getJSONObject(r));
          }
        }
      }
    }
    final JSONArray out = new JSONArray();
    LocalDate month = LocalDate.parse(asOf).withDayOfMonth(1).minusMonths(MONTHS - 1L);
    for (int m = 0; m < MONTHS; m++) {
      final String key = month.format(MONTH);
      final JSONObject row = found.get(key);
      out.put(new JSONObject().put("month", key)
          .put("docs", row == null ? 0 : (int) row.getDouble("docs"))
          .put("amount", row == null ? 0 : row.getDouble("amount")));
      month = month.plusMonths(1);
    }
    return out;
  }

  /**
   * What the client cannot work out for itself: the tab to drill down to, and the scope this
   * answer was computed under.
   *
   * The tab comes from the dictionary and may be null -- an uninstalled or renamed window -- in
   * which case the view renders the document reference as plain text. An unavailable link is a
   * smaller failure than a wrong one. The scope is reported so the window's gate can recompute the
   * arithmetic in SQL under the same restriction instead of guessing at OBContext.
   */
  private JSONObject meta(Connection conn, String side) throws Exception {
    final String window = "AR".equals(side) ? WINDOW_SALES_INVOICE : WINDOW_PURCHASE_INVOICE;
    final String tab = UikQuery.tabFor(conn, window, "c_invoice");
    final JSONArray clients = new JSONArray();
    for (String c : UikQuery.readableClients()) {
      clients.put(c);
    }
    final JSONArray orgs = new JSONArray();
    for (String o : UikQuery.readableOrgs()) {
      orgs.put(o);
    }
    return new JSONObject().put("invoiceWindow", window)
        .put("invoiceTab", tab == null ? JSONObject.NULL : tab)
        .put("scopeClients", clients).put("scopeOrgs", orgs);
  }
}
