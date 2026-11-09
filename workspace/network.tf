# =======================================
# Databricks Customer-Managed VPC Network
# =======================================

# This resource registers existing AWS VPC/subnets with the Databricks Account API and
# associated workspace. This is a prerequisite for "Customer-Managed VPC" deployments,
# which allows Databricks to inject/manage cluster nodes in customer-owned networks.

resource "databricks_mws_networks" "this" {
  count              = var.serverless ? 0 : 1
  provider           = databricks.mws
  account_id         = var.databricks_account
  network_name       = "${var.name}-network"
  vpc_id             = var.vpc_id
  subnet_ids         = var.subnet_ids
  security_group_ids = var.security_group_ids
}
