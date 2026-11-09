# Databricks Workspace Config Module

## Overview

This module configures the internal resources of an existing Databricks workspace:

1. **Unity Catalog**: Creates a workspace catalog with grants for admins, users, and the service principal
2. **All-Purpose Cluster**: Optionally provisions an autoscaling compute cluster with Unity Catalog support
3. **SQL Warehouse**: Optionally provisions a SQL warehouse endpoint
4. **Glue Catalog Integration**: Connects AWS Glue catalogs as foreign catalogs in Unity Catalog, with IAM policies, service/storage credentials, external locations, and workspace bindings
5. **Instance Profiles**: Registers IAM instance profiles and assigns them to workspace groups
6. **External Locations**: Creates external locations referencing existing storage credentials for accessing S3 data outside the workspace root bucket

## Usage

```hcl
module "databricks_workspace_config" {
  source = "git@gitlab.spectrumflow.net:pi-pipeline/foundation/infrastructure.git//terraform/databricks/databricks_workspace_config?ref=1.0.0"

  # Provider Attributes
  databricks_service_principal        = "<client-id>"
  databricks_service_principal_secret = "<client-secret>"
  databricks_workspace_host           = "https://dbc-abc123.cloud.databricks.com"
  databricks_workspace_id             = "1234567890123456"

  # Basic Attributes
  name         = "example-team"
  metastore_id = "abc123-metastore-id"

  # Access Control
  workspace_admins = ["admins-group"]
  workspace_users  = ["users-group"]

  # Unity Catalog
  unity_catalog_role_arn = "arn:aws:iam::123456789012:role/unity-catalog-role"

  # Cluster (optional)
  create_cluster                  = true
  cluster_spark_version           = "13.3.x-scala2.12"
  cluster_node_type               = "i3.xlarge"
  cluster_autoscale_min_workers   = 1
  cluster_autoscale_max_workers   = 4
  cluster_autotermination_minutes = 30

  # SQL Warehouse (optional)
  create_warehouse               = true
  serverless                     = true
  sql_warehouse_cluster_size     = "2X-Small"
  sql_warehouse_max_num_clusters = 1
  sql_warehouse_auto_stop_mins   = 10

  # Glue Catalog Integration (optional)
  glue_catalogs = {
    analytics = {
      CatalogName     = "analytics-catalog"
      ConnectionName  = "analytics-glue-conn"
      AccountId       = "123456789012"
      Region          = "us-east-1"
      AuthorizedPaths = ["my-data-bucket"]
      WritablePaths   = ["my-data-bucket/output"]
      KeyArns         = ["arn:aws:kms:us-east-1:123456789012:key/abc-123"]
      Local           = "true"
      IsolationMode   = "ISOLATED"
    }
  }

  # External Locations (optional)
  external_locations = {
    charter_bronze = {
      Name                  = "charter_bronze"
      StorageCredentialName = "example-team-storage-creds"
      BucketPath            = "s3://my-bucket/data/bronze/"
      RoleArn               = "arn:aws:iam::123456789012:role/data-access-role"
      Comment               = "A layer for raw ingestion"
    }
  }

  # Instance Profiles (optional)
  instance_profiles = {
    data_access = {
      Arn    = "arn:aws:iam::123456789012:instance-profile/databricks-data-access"
      Groups = ["data-engineers"]
    }
  }

  # Tags
  aws_tags = {
    Environment = "dev"
    Owner       = "data-platform"
  }
}
```

## Inputs

| Name                                  | Description                                                                         | Type                 | Default              |
|---------------------------------------|-------------------------------------------------------------------------------------|----------------------|----------------------|
| `databricks_service_principal`        | Service principal client ID                                                         | `string`             |                      |
| `databricks_service_principal_secret` | Service principal secret                                                            | `string`             |                      |
| `databricks_workspace_host`           | Databricks workspace URL                                                            | `string`             |                      |
| `databricks_workspace_id`             | Databricks workspace ID, used for catalog workspace bindings                        | `string`             | `""`                 |
| `name`                                | Name to use as the root prefix                                                      | `string`             |                      |
| `metastore_id`                        | The ID of the Databricks Metastore                                                  | `string`             |                      |
| `workspace_admins`                    | List of workspace admin group names to grant full permissions                       | `list(string)`       |                      |
| `workspace_users`                     | List of workspace user group names to grant read-only permissions                   | `list(string)`       |                      |
| `unity_catalog_role_arn`              | ARN of the IAM role used by Unity Catalog for data access                           | `string`             |                      |
| `create_cluster`                      | Whether to create an all-purpose compute cluster                                    | `bool`               | `false`              |
| `cluster_spark_version`               | Spark version for the cluster                                                       | `string`             | `"13.3.x-scala2.12"` |
| `cluster_node_type`                   | Node type for cluster instances                                                     | `string`             | `"i3.xlarge"`        |
| `cluster_autoscale_min_workers`       | Minimum number of worker nodes for autoscaling                                      | `number`             | `1`                  |
| `cluster_autoscale_max_workers`       | Maximum number of worker nodes for autoscaling                                      | `number`             | `4`                  |
| `cluster_autotermination_minutes`     | Auto-termination time in minutes (0 to disable)                                     | `number`             | `30`                 |
| `create_warehouse`                    | Whether to create a SQL warehouse                                                   | `bool`               | `false`              |
| `serverless`                          | Enable serverless compute for SQL warehouses and clusters                           | `bool`               | `false`              |
| `sql_warehouse_cluster_size`          | Size of the SQL warehouse cluster                                                   | `string`             | `"2X-Small"`         |
| `sql_warehouse_max_num_clusters`      | Maximum number of clusters for auto-scaling                                         | `number`             | `1`                  |
| `sql_warehouse_auto_stop_mins`        | Auto-stop time in minutes for SQL warehouse                                         | `number`             | `10`                 |
| `glue_catalogs`                       | Map of Glue catalog integrations with connection, IAM, and external location config | `map(object({...}))` | `{}`                 |
| `external_locations`                  | Map of external locations referencing existing storage credentials                   | `map(object({...}))` | `{}`                 |
| `instance_profiles`                   | Map of instance profiles to register and assign to groups                           | `map(object({...}))` | `{}`                 |
| `aws_tags`                            | Map of custom tags to apply to AWS resources                                        | `map(string)`        |                      |

## Outputs

| Name                     | Description                           |
|--------------------------|---------------------------------------|
| `cluster_id`             | ID of the all-purpose cluster         |
| `cluster_name`           | Name of the all-purpose cluster       |
| `sql_warehouse_id`       | ID of the SQL warehouse               |
| `sql_warehouse_jdbc_url` | JDBC URL for SQL warehouse connection |
