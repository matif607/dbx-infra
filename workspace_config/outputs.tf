output "cluster_id" {
  description = "ID of the all-purpose cluster"
  value       = var.create_cluster ? databricks_cluster.all_purpose[0].id : null
}

output "cluster_name" {
  description = "Name of the all-purpose cluster"
  value       = var.create_cluster ? databricks_cluster.all_purpose[0].cluster_name : null
}

output "sql_warehouse_id" {
  description = "ID of the SQL warehouse"
  value       = var.create_warehouse ? databricks_sql_endpoint.this[0].id : null
}

output "sql_warehouse_jdbc_url" {
  description = "JDBC URL for SQL warehouse connection"
  value       = var.create_warehouse ? databricks_sql_endpoint.this[0].jdbc_url : null
  sensitive   = true
}

output "external_location_urls" {
  description = "Map of external location keys to their S3 URLs"
  value       = { for k, v in databricks_external_location.s3_external : k => v.url }
}

output "storage_credential_names" {
  description = "Map of external location keys to their created storage credential names"
  value       = { for k, v in databricks_storage_credential.external_location : k => v.name }
}

output "storage_credential_ids" {
  description = "Map of external location keys to their created storage credential IDs"
  value       = { for k, v in databricks_storage_credential.external_location : k => v.id }
}
