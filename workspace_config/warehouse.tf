# ==================================
# Databricks Workspace SQL Warehouse
# ==================================

resource "databricks_sql_endpoint" "this" {
  count = var.create_warehouse ? 1 : 0

  name                      = "${var.name}-sql-warehouse"
  cluster_size              = var.sql_warehouse_cluster_size
  max_num_clusters          = var.sql_warehouse_max_num_clusters
  auto_stop_mins            = var.sql_warehouse_auto_stop_mins
  enable_serverless_compute = var.serverless

  provider = databricks.workspace
}

# Grant administrators and users SQL warehouse permissions
#
# NOTE: This resource is authoritative (i.e. all warehouse permissions should be added to this resource)
# NOTE: Additional "databrick_permissions" resources for the same warehouse will cause issues
resource "databricks_permissions" "sql_warehouse_permissions" {
  count = (var.create_warehouse && (length(var.workspace_admins) > 0 || length(var.workspace_users) > 0)) ? 1 : 0

  sql_endpoint_id = databricks_sql_endpoint.this[0].id

  # Administrator Permissions
  dynamic "access_control" {
    for_each = var.workspace_admins
    content {
      group_name       = access_control.value
      permission_level = "CAN_MANAGE"
    }
  }

  # User Permissions
  dynamic "access_control" {
    for_each = var.workspace_users
    content {
      group_name       = access_control.value
      permission_level = "CAN_USE"
    }
  }

  provider = databricks.workspace
}
