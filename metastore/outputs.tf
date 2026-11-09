output "metastore_id" {
  value       = databricks_metastore.metastore.id
  description = "The ID of the Databricks metastore to be used with Unity Catalog."
}
