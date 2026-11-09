# ===============
# Backend Details
# ===============

variable "databricks_service_principal" {
  description = "Service principal client ID"
  type        = string
}

variable "databricks_service_principal_secret" {
  description = "Service principal secret"
  type        = string
}

variable "databricks_workspace_id" {
  description = "The Databricks workspace ID, used for catalog workspace bindings"
  type        = string
  default     = ""
}

variable "databricks_workspace_host" {
  description = "Databricks Workspace URL"
  type        = string
}

# ============
# Team Details
# ============

variable "name" {
  description = "Name to use as the root prefix in S3"
  type        = string
}

# =============================================
# Databricks Workspace Administrators and Users
# =============================================

variable "workspace_admins" {
  description = "List of workspace admin email addresses to grant full catalog permissions"
  type        = list(string)
}

variable "workspace_users" {
  description = "List of workspace user email addresses to grant read-only catalog permissions"
  type        = list(string)
}

# ====================================
# Databricks Workspace Cluster Details
# ====================================

variable "create_cluster" {
  type    = bool
  default = false
}

variable "cluster_spark_version" {
  description = "Spark version for the cluster (e.g., '13.3.x-scala2.12')"
  type        = string
  default     = "13.3.x-scala2.12"
}

variable "cluster_node_type" {
  description = "Node type for cluster instances (e.g., 'i3.xlarge', 'm5d.large')"
  type        = string
  default     = "i3.xlarge"
}

variable "cluster_autoscale_min_workers" {
  description = "Minimum number of worker nodes for autoscaling"
  type        = number
  default     = 1
}

variable "cluster_autoscale_max_workers" {
  description = "Maximum number of worker nodes for autoscaling"
  type        = number
  default     = 4
}

variable "cluster_autotermination_minutes" {
  description = "Auto-termination time in minutes (0 to disable)"
  type        = number
  default     = 30
}

variable "aws_tags" {
  description = "Map of custom tags to apply to AWS resources used by the cluster along with default Databricks cluster tags"
  type        = map(string)
}

variable "serverless" {
  description = "Enable serverless compute for SQL warehouses and clusters"
  type        = bool
  default     = false
}

# ================================
# Databricks SQL Warehouse Details
# ================================

variable "create_warehouse" {
  type    = bool
  default = false
}

variable "sql_warehouse_cluster_size" {
  description = "Size of the SQL warehouse cluster (2X-Small, X-Small, Small, Medium, Large, X-Large, 2X-Large, 3X-Large, 4X-Large)"
  type        = string
  default     = "2X-Small"
}

variable "sql_warehouse_max_num_clusters" {
  description = "Maximum number of clusters for auto-scaling (1 means no scaling)"
  type        = number
  default     = 1
}

variable "sql_warehouse_auto_stop_mins" {
  description = "Auto-stop time in minutes for SQL warehouse"
  type        = number
  default     = 10
}

# ====================
# Databricks Metastore
# ====================

variable "metastore_id" {
  description = "The ID of the Databricks Metastore."
  type        = string
}

# ================================
# Databricks Unity Catalog Details
# ================================

variable "unity_catalog_role_arn" {
  description = "The ARN of the IAM role used by Unity Catalog for data access"
  type        = string
}

# ===================================
# Databricks Glue Catalog Integration
# ===================================

variable "glue_catalogs" {
  description = "Map of Glue catalog integrations. Each key is a logical name for the catalog."
  type = map(object({
    CatalogName             = string
    ConnectionName          = string
    AccountId               = string
    Region                  = string
    AuthorizedPaths         = list(string)               # S3 bucket names for Databricks external locations & foreign catalog authorized_paths
    WritablePaths           = optional(list(string), []) # S3 bucket/prefix paths for IAM write access (e.g. ["my-bucket/prefix"])
    KeyArns                 = optional(list(string), [])
    Local                   = optional(string, "false")
    CreateExternalLocations = optional(string, "true")
    CreateConnection        = optional(string, "true")
    IsolationMode           = optional(string, "ISOLATED") # "ISOLATED" restricts to bound workspaces; "OPEN" makes visible to all metastore workspaces
  }))
  default = {}
}

# ====================================
# Databricks External Locations
# ====================================

variable "external_locations" {
  description = "Map of external locations to create with associated storage credentials"
  type = map(object({
    Name                     = string
    Comment                  = optional(string, "")
    StorageCredentialName    = optional(string, "")
    BucketPath               = string
    EnableFileEvents         = optional(bool, false)
    ReadOnly                 = optional(bool, false)
    IsolationMode            = optional(string, "ISOLATION_MODE_OPEN")
    IngestServicePrincipalId = optional(string, "")
    StorageCredential = optional(object({
      Name    = string
      Comment = optional(string, "")
      RoleArn = string
    }), null)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.external_locations :
      v.StorageCredential != null || v.StorageCredentialName != ""
    ])
    error_message = "Either StorageCredential or StorageCredentialName must be provided."
  }

  validation {
    condition = alltrue([
      for k, v in var.external_locations :
      v.StorageCredential == null || v.StorageCredentialName == ""
    ])
    error_message = "StorageCredentialName must not be set when StorageCredential is provided."
  }
}


# ====================================
# Databricks Instance Profile Details
# ====================================

variable "instance_profiles" {
  description = "Map of instance profiles to register with Databricks workspace and assign to groups"
  type = map(object({
    Arn            = string
    Groups         = optional(list(string), [])
    SkipValidation = optional(string, "false")
  }))
  default = {}
}
