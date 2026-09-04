package com.etendoerp.uikit.samples.modulescript;

import java.sql.PreparedStatement;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.openbravo.database.ConnectionProvider;
import org.openbravo.modulescript.ModuleScript;
import org.openbravo.modulescript.ModuleScriptExecutionLimits;

/**
 * Grants every active tenant role access to the sample windows (ETDEMO_*, ETOKRS_*).
 *
 * These rows do not decide whether a demo window renders: fact F6 records that
 * ViewComponent.generateView never consults OBUIAPP_View_Role_Access, so the view answers anyone
 * who reaches its URL and the datasources are what actually enforce scope. What the rows do decide
 * is whether the menu entry appears at all, which is the difference between a demo a user can find
 * and a demo they have to be handed a link to.
 *
 * It has to be a module script because export.database does not cover
 * OBUIAPP_View_Role_Access: there is no sourcedata file to commit, so this is the only way the
 * grants travel with the module instead of being clicked in by hand on every instance.
 */
public class GrantSampleViewAccess extends ModuleScript {

  private static final Logger log = LogManager.getLogger();

  private static final String MODULE_ID = "9B95C942C625D885CEA19119EA7FDC02";

  @Override
  protected ModuleScriptExecutionLimits getModuleScriptExecutionLimits() {
    return new ModuleScriptExecutionLimits(MODULE_ID, null, null);
  }

  @Override
  public void execute() {
    final ConnectionProvider cp = getConnectionProvider();
    PreparedStatement ps = null;
    try {
      // The not-exists guard is what makes a re-run a no-op: update.database replays module
      // scripts, and a second pass must not duplicate a grant an administrator may have revoked
      // on purpose -- an inactive row still counts as existing here.
      ps = cp.getPreparedStatement("INSERT INTO obuiapp_view_role_access "
          + "(obuiapp_view_role_access_id, ad_client_id, ad_org_id, isactive, "
          + " created, createdby, updated, updatedby, obuiapp_view_impl_id, ad_role_id) "
          + "SELECT get_uuid(), r.ad_client_id, '0', 'Y', "
          + "       now(), '0', now(), '0', v.obuiapp_view_impl_id, r.ad_role_id "
          + "FROM obuiapp_view_impl v, ad_role r "
          + "WHERE (v.name LIKE 'ETDEMO%' OR v.name LIKE 'ETOKRS%') "
          + "  AND v.isactive = 'Y' "
          + "  AND r.isactive = 'Y' "
          + "  AND r.ad_client_id <> '0' "
          + "  AND NOT EXISTS ("
          + "    SELECT 1 FROM obuiapp_view_role_access a "
          + "    WHERE a.obuiapp_view_impl_id = v.obuiapp_view_impl_id "
          + "      AND a.ad_role_id = r.ad_role_id"
          + "  )");
      final int created = ps.executeUpdate();
      log.info("GrantSampleViewAccess: granted {} sample view accesses", created);
    } catch (Exception e) {
      handleError(e);
    } finally {
      release(cp, ps);
    }
  }

  private void release(ConnectionProvider cp, PreparedStatement ps) {
    if (ps != null) {
      try {
        cp.releasePreparedStatement(ps);
      } catch (Exception e) {
        handleError(e);
      }
    }
  }
}
