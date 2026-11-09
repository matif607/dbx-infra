# =========================================
# Databricks Unity Catalog Data Access Role
# =========================================

# The Unity Catalog Data Access role is a specialized IAM role that provides the
# Unity Catalog service with the permissions necessary to access data stored in
# your S3 buckets.

# Unlike the Cross-Account Role—which manages compute infrastructure like EC2
# and VPCs—this role is strictly dedicated to data governance. When a user
# queries a table, the Unity Catalog service assumes this role on the backend
# to securely fetch data from S3. This architecture ensures that compute
# resources (clusters) do not need direct access to S3, creating a secure
# "firewall" between user code and your raw data files.

# This role is registered within a Databricks Workspace as a "Storage Credential"
# and is a fundamental requirement for implementing a governed Lakehouse
# architecture using Unity Catalog.

# ===============
# Local Variables
# ===============

data "aws_caller_identity" "current" {}

locals {
  # The name of the IAM role used by Unity Catalog to manage data access
  data_access_role_name = "${var.name}-data-access"

  # The AWS account ID of the account to create the Databricks workspace in
  aws_account_id = data.aws_caller_identity.current.account_id

  # Whether to create the data access role or use an existing one
  create_data_access_role = var.data_access_role_arn == ""

  # Resolved ARN: either the created role or the user-provided one
  data_access_role_arn = local.create_data_access_role ? aws_iam_role.data_access_role[0].arn : var.data_access_role_arn

  # Generate nested S3 paths: arn:aws:s3:::<bucket>/team=<team>/general/<category>/databricks/<workspace>/*
  prefix_resources = flatten([
    for prefix in var.bucket_prefixes : [
      "arn:aws:s3:::${var.root_bucket}/${prefix}/*"
    ]
  ])
}

# ========
# IAM Role
# ========

resource "aws_iam_role" "data_access_role" {
  count = local.create_data_access_role ? 1 : 0

  name               = local.data_access_role_name
  assume_role_policy = data.aws_iam_policy_document.unity_catalog_trust[0].json
  description        = <<EOT
  This role is assumed by Databricks Unity Catalog to access and manage data access in the workspace's
  AWS account on behalf of the Databricks user(s).
  EOT
  tags               = var.aws_tags
}

# ============
# IAM Policies
# ============

resource "aws_iam_role_policy" "data_access_role_root_bucket_access" {
  count = local.create_data_access_role ? 1 : 0

  name = "${var.name}-root-bucket-access"
  role = aws_iam_role.data_access_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:ListBucketMultipartUploads",
          "s3:ListMultipartUploadParts",
          "s3:AbortMultipartUpload"
        ]
        Resource = concat(
          [
            "arn:aws:s3:::${var.root_bucket}",
            "arn:aws:s3:::${var.root_bucket}/*"
          ],
          local.prefix_resources
        )
      }],
      var.kms_key_arn != "" ? [{
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = var.kms_key_arn
      }] : []
    )
  })
}


# ================
# IAM Trust Policy
# ================

data "aws_iam_policy_document" "unity_catalog_trust" {
  count = local.create_data_access_role ? 1 : 0

  # Classic compute: Unity Catalog master role
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.databricks_account]
    }
  }

  dynamic "statement" {
    for_each = var.serverless ? [1] : []
    content {
      sid     = "SelfAssume"
      effect  = "Allow"
      actions = ["sts:AssumeRole"]
      principals {
        type = "AWS"
        identifiers = [
          "arn:aws:iam::${local.aws_account_id}:role/${local.data_access_role_name}"
        ]
      }
    }
  }
}

# =========================================
# Databricks Workspace Metastore Assignment
# =========================================

# Assign Metastore to Workspace
resource "databricks_metastore_assignment" "this" {
  provider     = databricks.mws
  workspace_id = databricks_mws_workspaces.this.workspace_id
  metastore_id = var.metastore_id
}

# Storage Credential for Unity Catalog External Locations
resource "databricks_storage_credential" "external_storage" {
  provider = databricks.mws

  metastore_id = var.metastore_id
  name         = lower("${var.name}-storage-creds")
  comment      = "Storage credential for ${var.name} workspace S3 access via Unity Catalog"

  aws_iam_role {
    role_arn = local.data_access_role_arn
  }

  depends_on = [
    aws_iam_role_policy.data_access_role_root_bucket_access,
    databricks_metastore_assignment.this
  ]
}
