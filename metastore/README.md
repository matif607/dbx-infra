# Databricks Metastore Terraform Module

This module automates the deployment of a [Unity Catalog Metastore](https://docs.databricks.com/aws/en/data-governance/unity-catalog/), the central governance layer for Databricks. It enables the three-level namespace (`catalog.schema.table`) and provides a unified location to manage metadata and access controls across multiple workspaces.

## Usage

```hcl
module "databricks_metastore" {
  source = "../metastore"

  provider_configs = {
    Host         = "https://accounts.cloud.databricks.com"
    Account      = "123456789012"
    Client       = "xxxx"
    ClientSecret = "xxxx"
  }

  name        = "test-warp-metastore"
  region      = "us-east-1"
  bucket_path = "s3://test/test/databricks"
}
```

<!-- BEGIN_TF_DOCS -->

## Input Variables

| Name                      | Description                                              | Type     | Required | Example                                      |
|---------------------------|----------------------------------------------------------|----------|----------|----------------------------------------------|
| `region`                  | AWS region where the Databricks workspace will be deployed | `string` | yes      | `us-east-1`                                  |
| `name`                    | Name of the Databricks metastore                         | `string` | yes      | `my-metastore`                               |
| `bucket_path`             | Root S3 bucket path for Databricks data (`s3://<bucket>/<prefix>`) | `string` | yes      | `s3://my-bucket/metastore`                   |
| `provider_host`           | Databricks account or workspace URL                      | `string` | yes      | `https://accounts.cloud.databricks.com`      |
| `provider_account`        | Databricks account ID                                    | `string` | yes      | `123456789012`                               |
| `provider_client`         | Service principal client ID                              | `string` | yes      | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`       |
| `provider_client_secret`  | Service principal secret                                 | `string` | yes      | `********`                                   |

---

## Outputs

| Name               | Description                                                                 | Type                                              | 
|--------------------|-----------------------------------------------------------------------------|---------------------------------------------------|
| `metastore_id`     | The ID of the Databricks metastore to be used with Unity Catalog            | `string`                                          | 

<!-- END_TF_DOCS -->