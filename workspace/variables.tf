# ===================
# Provider Attributes
# ===================

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

# ================
# Basic Attributes
# ================

variable "region" {
  description = "AWS region for the Databricks workspace"
  type        = string
}

variable "name" {
  description = "Name of the Workspace"
  type        = string
}

variable "metastore_id" {
  description = "The ID of the Databricks metastore to be used with the workspace for data governance with Unity Catalog."
  type        = string
}

# ======================
# Network Configurations
# ======================

variable "vpc_id" {
  description = "VPC ID where Databricks clusters will run. Not required for serverless-only workspaces."
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of private subnet IDs for Databricks clusters (minimum 2 subnets required). Not required for serverless-only workspaces."
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "List of security group IDs for Databricks clusters"
  type        = list(string)
  default     = []
}

variable "serverless" {
  description = "Enable serverless-only workspace (skips customer-managed VPC, cross-account role, and network configuration)"
  type        = bool
  default     = false
}

# ==========================
# Root Bucket Configurations
# ==========================

variable "root_bucket" {
  description = "Name of the S3 datalake bucket where Databricks workspace data will be stored"
  type        = string
}

variable "bucket_prefixes" {
  description = "List of Bucket Prefixes"
  type        = list(string)
  default     = []
}

variable "kms_key_arn" {
  description = "KMS key ARN for S3 bucket encryption (required if bucket uses KMS encryption, especially for cross-account buckets)"
  type        = string
  default     = ""
}

# ==========================
# Databricks Workspace Users
# ==========================

variable "workspace_admins" {
  description = "List of SAML group names to assign as workspace admins"
  type        = list(string)
  default     = []
}

variable "workspace_users" {
  description = "List of SAML group names to assign as workspace users"
  type        = list(string)
  default     = []
}

# =================
# Instance Profiles
# =================

variable "instance_profile_arns" {
  description = "List of IAM instance profile role ARNs that Databricks needs iam:PassRole permission for"
  type        = list(string)
  default     = []
}

variable "data_access_role_arn" {
  description = "ARN of an existing IAM role to use for Unity Catalog data access. If provided, the module skips creating the role and policies."
  type        = string
  default     = ""
}

# =======
# Tagging
# =======

variable "aws_tags" {
  description = "Tags to apply to AWS resources"
  type        = map(string)
}
