# ====================
# Databricks Workspace
# ====================

# Create Databricks workspace in customer-managed VPC
resource "databricks_mws_workspaces" "this" {
  provider = databricks.mws

  account_id     = var.databricks_account
  workspace_name = var.name
  aws_region     = var.region

  compute_mode             = var.serverless ? "SERVERLESS" : null
  credentials_id           = var.serverless ? null : databricks_mws_credentials.this[0].credentials_id
  storage_configuration_id = var.serverless ? null : databricks_mws_storage_configurations.this.storage_configuration_id
  network_id               = var.serverless ? null : databricks_mws_networks.this[0].network_id

  custom_tags = var.aws_tags
}
