# Databricks Workspace Module

## Overview

This module creates the necessary AWS resources for a Databricks workspace:

1. **Cross-Account IAM Role**: Allows Databricks to assume a role in your AWS account (skipped for serverless)
2. **IAM Policies**: Standard Databricks policy + S3 bucket access with multipart upload support (skipped for serverless)
3. **S3 Prefix**: Creates team-specific prefix(es) in the root datalake bucket
4. **MWS Credentials**: Registers the cross-account role with Databricks (skipped for serverless)
5. **Customer-Managed VPC Network**: Registers VPC/subnets with Databricks (skipped for serverless)
6. **Unity Catalog Data Access Role**: IAM role with SelfAssume trust for Unity Catalog storage credential access (skipped when `data_access_role_arn` is provided)
7. **Storage Credential**: Registers the data access role as a Unity Catalog storage credential

## Usage

### Classic workspace (customer-managed VPC)

```hcl
module "databricks_workspace" {
  source = "../databricks/workspace"

  # Provider Attributes
  databricks_host                       = "https://accounts.cloud.databricks.com"
  databricks_account                    = "1234567890"
  databricks_service_principal          = "<client-id>"
  databricks_service_principal_secret   = "<client-secret>"

  # Basic Attributes
  region        = "us-west-2"
  name          = "example-workspace"
  metastore_id  = "abc123-metastore"

  # Networking
  vpc_id              = "vpc-123456"
  subnet_ids          = ["subnet-1", "subnet-2", "subnet-3"]
  security_group_ids  = ["sg-123456"]

  # Storage
  root_bucket     = "root-bucket"
  bucket_prefixes = ["raw", "processed", "analytics"]
  kms_key_arn     = "arn:aws:kms:us-west-2:123456:key/abc"

  # Access Control
  workspace_admins = ["admins-group"]
  workspace_users  = ["users-group"]

  # Instance Profiles
  instance_profile_arns = ["arn:aws:iam::123456:instance-profile/databricks-role"]

  # Tags
  aws_tags = {
    Environment = "dev"
    Owner       = "data-platform"
  }
}
```

### Serverless workspace

```hcl
module "databricks_workspace_serverless" {
  source = "../databricks/workspace"

  # Provider Attributes
  databricks_host                       = "https://accounts.cloud.databricks.com"
  databricks_account                    = "1234567890"
  databricks_service_principal          = "<client-id>"
  databricks_service_principal_secret   = "<client-secret>"

  # Basic Attributes
  region        = "us-west-2"
  name          = "example-serverless"
  metastore_id  = "abc123-metastore"
  serverless    = true

  # Storage
  root_bucket     = "root-bucket"
  bucket_prefixes = ["raw", "processed"]

  # Data Access (use existing role instead of creating one)
  data_access_role_arn = "arn:aws:iam::123456789012:role/existing-data-access-role"

  # Access Control
  workspace_admins = ["admins-group"]
  workspace_users  = ["users-group"]

  # Tags
  aws_tags = {
    Environment = "dev"
    Owner       = "data-platform"
  }
}
```

## Inputs

| Name                                  | Description                                                                    | Type           | Default |
| ------------------------------------- | ------------------------------------------------------------------------------ | -------------- | ------- |
| `databricks_host`                     | Databricks account URL                                                         | `string`       |         |
| `databricks_account`                  | Databricks account ID                                                          | `string`       |         |
| `databricks_service_principal`        | Service principal client ID                                                    | `string`       |         |
| `databricks_service_principal_secret` | Service principal secret                                                       | `string`       |         |
| `region`                              | AWS region for the Databricks workspace                                        | `string`       |         |
| `name`                                | Name of the Workspace                                                          | `string`       |         |
| `metastore_id`                        | Databricks Unity Catalog metastore ID                                          | `string`       |         |
| `vpc_id`                              | VPC ID where Databricks clusters will run (not required for serverless)        | `string`       | `""`    |
| `subnet_ids`                          | List of private subnet IDs (minimum 2 required, not required for serverless)   | `list(string)` | `[]`    |
| `security_group_ids`                  | List of security group IDs                                                     | `list(string)` | `[]`    |
| `serverless`                          | Enable serverless-only workspace (skips VPC, cross-account role, network, storage config) | `bool` | `false` |
| `root_bucket`                         | S3 bucket for Databricks workspace data                                        | `string`       |         |
| `bucket_prefixes`                     | List of S3 bucket prefixes                                                     | `list(string)` |         |
| `kms_key_arn`                         | KMS key ARN for bucket encryption                                              | `string`       | `""`    |
| `data_access_role_arn`                | ARN of an existing IAM role for Unity Catalog data access (skips role/policy creation if provided) | `string` | `""` |
| `workspace_admins`                    | SAML groups assigned as workspace admins                                       | `list(string)` | `[]`    |
| `workspace_users`                     | SAML groups assigned as workspace users                                        | `list(string)` | `[]`    |
| `instance_profile_arns`               | IAM instance profile ARNs for PassRole permission                              | `list(string)` | `[]`    |
| `aws_tags`                            | Tags to apply to AWS resources                                                 | `map(string)`  |         |

## Outputs

| Name                                 | Description                                                   |
| ------------------------------------ | ------------------------------------------------------------- |
| `cross_account_role_arn`             | The ARN of the cross-account IAM role (null for serverless)   |
| `unity_catalog_data_access_role_arn` | The ARN of the IAM role used by Unity Catalog for data access |
| `storage_credential_name`            | The name of the Unity Catalog storage credential              |
| `workspace_id`                       | Databricks workspace ID                                       |
| `workspace_url`                      | Databricks workspace URL                                      |
