# =============================
# Databricks Cross-Account Role
# =============================

# The Databricks cross-account role is used by the Databricks control plane to access
# resources in the workspace's AWS account on behalf of the user(s). For example, a user
# can launch a cluster via the Databricks workspace UI and the Databricks control plane
# will use this role to launch the cluster in the workspace's AWS account. The cross-account
# role is registered with the Databricks account as the credentials to be used to manage the
# workspace's compute and network resources securely.
#
# Note: This role is separate from Unity Catalog storage roles, which manage access to data in S3.

# ===============
# Local Variables
# ===============

locals {
  # The name of the Databricks crossaccount role
  cross_account_role_name = "${var.name}-compute-access"
}

# =====================
# Workspace Credentials
# =====================

# This credential securely configures the Databricks account with the cross-account IAM role
# i.e. Databricks control plane can use this set of registered credentials to access/manage AWS resources
# in the workspace AWS account on behalf of the workspace's user(s)

resource "databricks_mws_credentials" "this" {
  count    = var.serverless ? 0 : 1
  provider = databricks.mws

  role_arn         = aws_iam_role.cross_account_role[0].arn
  credentials_name = "${var.name}-creds"

  depends_on = [
    time_sleep.wait_for_iam_propagation
  ]
}

resource "time_sleep" "wait_for_iam_propagation" {
  count           = var.serverless ? 0 : 1
  depends_on      = [aws_iam_role.cross_account_role]
  create_duration = "30s"
}

# =================
# IAM Data Policies
# =================

data "databricks_aws_assume_role_policy" "trust_policy" {
  count       = var.serverless ? 0 : 1
  provider    = databricks.mws
  external_id = var.databricks_account
}

data "databricks_aws_crossaccount_policy" "cross_account_policy" {
  count       = var.serverless ? 0 : 1
  provider    = databricks.mws
  policy_type = "customer"
}

# ========
# IAM Role
# ========

resource "aws_iam_role" "cross_account_role" {
  count              = var.serverless ? 0 : 1
  name               = local.cross_account_role_name
  assume_role_policy = data.databricks_aws_assume_role_policy.trust_policy[0].json
  description        = <<EOT
  This role is assumed by the Databricks control plane to access and manage resources in the
  workspace's AWS account on behalf of the Databricks user(s).
  EOT
  tags               = var.aws_tags
}

# ============
# IAM Policies
# ============

resource "aws_iam_role_policy" "compute_policy" {
  count  = var.serverless ? 0 : 1
  name   = "${var.name}-databricks-compute-policy"
  role   = aws_iam_role.cross_account_role[0].id
  policy = data.databricks_aws_crossaccount_policy.cross_account_policy[0].json
}

resource "aws_iam_role_policy" "compute_access_role_root_bucket_access" {
  count = var.serverless ? 0 : 1
  name  = "${var.name}-root-bucket-access"
  role  = aws_iam_role.cross_account_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
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

# =========================================
# Instance Profile PassRole Policy
# =========================================

# When Databricks registers an instance profile, the control plane assumes the
# cross-account role and calls iam:PassRole to validate access. This policy
# grants that permission for each instance profile ARN provided.

resource "aws_iam_role_policy" "instance_profile_passrole" {
  count = var.serverless ? 0 : (length(var.instance_profile_arns) > 0 ? 1 : 0)

  name = "${var.name}-instance-profile-passrole"
  role = aws_iam_role.cross_account_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "PassRoleForInstanceProfiles"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = [for arn in var.instance_profile_arns : replace(arn, ":instance-profile/", ":role/")]
      }
    ]
  })
}
