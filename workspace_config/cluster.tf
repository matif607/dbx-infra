# ======================================
# Databricks All Purpose Compute Cluster
# ======================================

# Create all-purpose cluster
resource "databricks_cluster" "all_purpose" {
  count = var.create_cluster ? 1 : 0

  cluster_name  = "${var.name}-cluster"
  spark_version = var.cluster_spark_version
  node_type_id  = var.cluster_node_type

  autoscale {
    min_workers = var.cluster_autoscale_min_workers
    max_workers = var.cluster_autoscale_max_workers
  }

  autotermination_minutes = var.cluster_autotermination_minutes

  # Enable Unity Catalog support
  data_security_mode = "USER_ISOLATION"

  # Attach additional custom tags to the cluster
  custom_tags = var.aws_tags

  # AWS specific attributes
  aws_attributes {
    availability           = "SPOT_WITH_FALLBACK"
    zone_id                = "auto"
    first_on_demand        = 1
    spot_bid_price_percent = 100
  }

  provider = databricks.workspace
}

# Grant administrators and users cluster permissions
#
# NOTE: This resource is authoritative (i.e. all cluster permissions should be added to this resource)
# NOTE: Additional "databrick_permissions" resources for the same cluster will cause issues
resource "databricks_permissions" "all_purpose_cluster_permissions" {
  count = (var.create_cluster && (length(var.workspace_admins) > 0 || length(var.workspace_users) > 0)) ? 1 : 0

  cluster_id = databricks_cluster.all_purpose[0].id

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
      permission_level = "CAN_ATTACH_TO"
    }
  }

  provider = databricks.workspace
}

