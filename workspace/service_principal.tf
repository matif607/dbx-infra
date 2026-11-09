# ============================
# Databricks Service Principal
# ============================

# Look up the service principal to get its numeric ID (not the same ID as Client ID)
data "databricks_service_principal" "service_principal" {
  provider       = databricks.mws
  application_id = var.databricks_service_principal
}

# Assign service principal as workspace admin for Terraform operations
resource "databricks_mws_permission_assignment" "service_principal" {
  provider     = databricks.mws
  workspace_id = databricks_mws_workspaces.this.workspace_id
  principal_id = data.databricks_service_principal.service_principal.sp_id
  permissions  = ["ADMIN"]

  depends_on = [
    time_sleep.wait_for_federation
  ]
}

# Wait for identity federation to activate in Databrick's backend (roughly 30s to 60s)
resource "time_sleep" "wait_for_federation" {
  depends_on      = [databricks_metastore_assignment.this]
  create_duration = "60s"
}