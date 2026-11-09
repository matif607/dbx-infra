# ====================
# Databricks Metastore
# ====================

resource "databricks_metastore" "metastore" {
  name         = var.name
  region       = var.region
  storage_root = var.bucket_path
}