variable "region" {
  description = "AWS region for the Databricks workspace"
  type        = string
}

variable "name" {
  description = "Name for metastore"
  type        = string
}

variable "bucket_path" {
  description = "Configs for the root S3 bucket where Databricks workspace data will be stored. Example 's3://<bucket_name>/<prefix>'"
  type        = string
}

variable "databricks_host" {
  description = "Databricks account URL "
  type        = string
}

variable "databricks_account" {
  description = "Databricks account ID"
  type        = string
}

variable "databricks_service_principal" {
  description = "Service principal client ID"
  type        = string
}

variable "databricks_service_principal_secret" {
  description = "Service principal secret"
  type        = string
}