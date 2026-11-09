output "cross_account_role_arn" {
  description = "The ARN of the cross-account IAM role"
  value       = var.serverless ? null : aws_iam_role.cross_account_role[0].arn
}

output "unity_catalog_data_access_role_arn" {
  description = "The ARN of the IAM role used by Unity Catalog for data access purposes"
  value       = local.data_access_role_arn
}

output "workspace_id" {
  description = "Databricks workspace ID"
  value       = databricks_mws_workspaces.this.workspace_id
}

output "storage_credential_name" {
  description = "The name of the Unity Catalog storage credential"
  value       = databricks_storage_credential.external_storage.name
}

output "workspace_url" {
  description = "Databricks workspace URL"
  value       = databricks_mws_workspaces.this.workspace_url
}
