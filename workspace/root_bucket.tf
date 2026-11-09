# ======================
# Databricks Root Bucket
# ======================

# Registers the AWS S3 bucket as the root bucket for the Databricks workspace.
# This bucket hosts the Databricks File System (DBFS) root, which stores
# system-level metadata, cluster logs, and workspace library files.

resource "databricks_mws_storage_configurations" "this" {
  provider                   = databricks.mws
  account_id                 = var.databricks_account
  storage_configuration_name = "${var.name}-storage"
  bucket_name                = var.root_bucket
}

resource "aws_s3_object" "workspace_prefixes" {
  for_each = toset(var.bucket_prefixes)
  bucket   = var.root_bucket
  key      = "${each.value}/"
  content  = ""
}
