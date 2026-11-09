# =============================================
# Databricks Workspace Administrators and Users
# =============================================

data "databricks_group" "workspace_admin_groups" {
  for_each     = toset(var.workspace_admins)
  display_name = each.value
  provider     = databricks.mws
}

data "databricks_group" "workspace_user_groups" {
  for_each     = toset(var.workspace_users)
  display_name = each.value
  provider     = databricks.mws
}

resource "databricks_mws_permission_assignment" "workspace_admins" {
  for_each = toset(var.workspace_admins)

  workspace_id = databricks_mws_workspaces.this.workspace_id
  principal_id = data.databricks_group.workspace_admin_groups[each.key].id
  permissions  = ["ADMIN"]

  provider = databricks.mws

  depends_on = [
    databricks_metastore_assignment.this
  ]
}

resource "databricks_mws_permission_assignment" "workspace_users" {
  for_each = toset(var.workspace_users)

  workspace_id = databricks_mws_workspaces.this.workspace_id
  principal_id = data.databricks_group.workspace_user_groups[each.key].id
  permissions  = ["USER"]

  provider = databricks.mws

  depends_on = [
    databricks_metastore_assignment.this
  ]
}