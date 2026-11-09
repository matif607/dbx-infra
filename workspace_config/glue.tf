# ======================================================
# Glue Catalog Integration with Databricks Unity Catalog
# ======================================================

locals {
  uc_role_name = split("/", var.unity_catalog_role_arn)[1]
}

# ==========================================
# Glue S3 Read Access - Shared Managed Policy
# ==========================================

# A single managed policy for S3 read access, shared across all Glue catalogs.
# This avoids the 10KB inline policy size limit when catalogs have many AuthorizedPaths.
# Unity Catalog's AuthorizedPaths still enforces bucket-level access control.

resource "aws_iam_policy" "glue_s3_read" {
  count = local.any_glue_catalog ? 1 : 0

  name        = "${var.name}-glue-s3-read-access"
  description = "S3 read access for Glue catalog integration in ${var.name} workspace"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ReadAccess"
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = ["*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_s3_read" {
  count = local.any_glue_catalog ? 1 : 0

  role       = local.uc_role_name
  policy_arn = aws_iam_policy.glue_s3_read[0].arn
}

# ===========================
# Glue Access IAM Role Policy
# ===========================

# One inline policy per catalog entry for Glue metadata, S3 writes, and KMS.
# S3 read access is handled by the shared managed policy above.

resource "aws_iam_role_policy" "glue_policy" {
  for_each = var.glue_catalogs

  name = "${var.name}-glue-${each.key}-access-policy"
  role = local.uc_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid    = "GlueMetadataAccess"
          Effect = "Allow"
          Action = [
            "glue:GetDatabase",
            "glue:GetDatabases",
            "glue:GetTable",
            "glue:GetTables",
            "glue:GetPartition",
            "glue:GetPartitions",
            "glue:BatchGetPartition"
          ]
          Resource = [
            "arn:aws:glue:${each.value.Region}:${each.value.AccountId}:catalog",
            "arn:aws:glue:${each.value.Region}:${each.value.AccountId}:database/*",
            "arn:aws:glue:${each.value.Region}:${each.value.AccountId}:table/*/*"
          ]
        }
      ],
      length(each.value.WritablePaths) > 0 ? [
        {
          Sid    = "S3WriteAccess"
          Effect = "Allow"
          Action = [
            "s3:PutObject",
            "s3:PutObjectAcl",
            "s3:DeleteObject",
            "s3:AbortMultipartUpload",
            "s3:ListMultipartUploadParts",
            "s3:GetLifecycleConfiguration",
            "s3:PutLifecycleConfiguration"
          ]
          Resource = flatten([
            for path in each.value.WritablePaths : [
              "arn:aws:s3:::${path}",
              "arn:aws:s3:::${path}/*"
            ]
          ])
        }
      ] : [],
      length(each.value.KeyArns) > 0 ? [
        {
          Sid    = "KMSAccess"
          Effect = "Allow"
          Action = concat(
            [
              "kms:Decrypt",
              "kms:DescribeKey"
            ],
            length(each.value.WritablePaths) > 0 ? [
              "kms:Encrypt",
              "kms:GenerateDataKey*",
              "kms:ReEncrypt*"
            ] : []
          )
          Resource = each.value.KeyArns
        }
      ] : []
    )
  })
}

# Sleep for 60s to allow for IAM eventual consistency

resource "time_sleep" "wait_for_glue_policy" {
  for_each = var.glue_catalogs

  create_duration = "60s"

  depends_on = [
    aws_iam_role_policy.glue_policy,
    aws_iam_role_policy_attachment.glue_s3_read
  ]
}

# ======================================
# Glue Connection Databricks Credentials
# ======================================

# Service credential: one per workspace, shared across all Glue connections

resource "databricks_credential" "glue_service_creds" {
  count = local.any_glue_catalog ? 1 : 0

  name = "${var.name}-glue-service-creds"

  aws_iam_role {
    role_arn = var.unity_catalog_role_arn
  }

  purpose = "SERVICE"
  comment = "Used by Glue connections for ${var.name} workspace to create foreign catalogs in Unity Catalog."

  depends_on = [time_sleep.wait_for_glue_policy]

  provider = databricks.workspace
}

resource "databricks_grants" "glue_service_creds_access" {
  count = local.any_glue_catalog ? 1 : 0

  credential = databricks_credential.glue_service_creds[0].id

  dynamic "grant" {
    for_each = var.workspace_admins
    content {
      principal  = grant.value
      privileges = ["ALL_PRIVILEGES", "MANAGE"]
    }
  }

  dynamic "grant" {
    for_each = var.workspace_users
    content {
      principal  = grant.value
      privileges = ["ACCESS"]
    }
  }

  provider = databricks.workspace
}

# Storage credential: only for local (same-account) catalogs

resource "databricks_credential" "glue_storage_creds" {
  count = local.any_local_catalog ? 1 : 0

  name = "${var.name}-glue-storage-creds"

  aws_iam_role {
    role_arn = var.unity_catalog_role_arn
  }

  purpose = "STORAGE"
  comment = "Used by Glue integration for ${var.name} workspace to access S3 data directly."

  depends_on = [time_sleep.wait_for_glue_policy]

  provider = databricks.workspace
}

resource "databricks_grants" "glue_storage_creds_access" {
  count = local.any_local_catalog ? 1 : 0

  credential = databricks_credential.glue_storage_creds[0].id

  dynamic "grant" {
    for_each = var.workspace_admins
    content {
      principal  = grant.value
      privileges = ["ALL_PRIVILEGES", "MANAGE"]
    }
  }

  dynamic "grant" {
    for_each = var.workspace_users
    content {
      principal  = grant.value
      privileges = ["READ_FILES", "WRITE_FILES"]
    }
  }

  provider = databricks.workspace
}

# =============================
# Glue Access External Locations
# =============================

# Conditional per catalog (CreateExternalLocations flag), per authorized path

resource "databricks_external_location" "glue_ext" {
  for_each = local.glue_external_locations

  name = "${var.name}-glue-${each.value.catalog_key}-ext-${replace(each.value.path, "/", "-")}"

  url = "s3://${each.value.path}"

  credential_name = databricks_credential.glue_service_creds[0].name
  comment         = "External location for Glue path ${each.value.path} (catalog: ${each.value.catalog_key}) in ${var.name} workspace"

  skip_validation = true
  force_destroy   = true

  depends_on = [time_sleep.wait_for_glue_policy]

  provider = databricks.workspace
}

resource "databricks_grants" "glue_ext_access" {
  for_each = databricks_external_location.glue_ext

  external_location = each.value.id

  dynamic "grant" {
    for_each = var.workspace_admins
    content {
      principal  = grant.value
      privileges = ["ALL_PRIVILEGES", "MANAGE"]
    }
  }

  dynamic "grant" {
    for_each = var.workspace_users
    content {
      principal  = grant.value
      privileges = length(local.glue_external_locations[each.key].catalog.WritablePaths) > 0 ? ["READ_FILES", "WRITE_FILES"] : ["READ_FILES"]
    }
  }

  provider = databricks.workspace
}

# ==========================
# Databricks Glue Connections
# ==========================

# Conditional per catalog (CreateConnection flag)

resource "databricks_connection" "glue" {
  for_each = local.glue_connections

  name            = each.value.ConnectionName
  connection_type = "GLUE"
  comment         = "Connection to AWS Glue catalog ${each.key} for ${var.name} workspace"

  options = {
    aws_account_id = each.value.AccountId
    aws_region     = each.value.Region
    credential     = databricks_credential.glue_service_creds[0].name
  }

  depends_on = [time_sleep.wait_for_glue_policy]

  provider = databricks.workspace
}

# ====================
# Glue Foreign Catalogs
# ====================

# One catalog per entry in glue_catalogs map

resource "databricks_catalog" "glue_foreign_catalog" {
  for_each = var.glue_catalogs

  name = each.value.CatalogName

  connection_name = each.value.ConnectionName
  comment         = "Foreign catalog mirroring AWS Glue (${each.key}) for ${var.name}"

  options = {
    authorized_paths = join(",", formatlist("s3://%s", each.value.AuthorizedPaths))
  }

  # Per-catalog isolation mode: "ISOLATED" restricts to bound workspaces, "OPEN" makes visible to all metastore workspaces
  isolation_mode = each.value.IsolationMode

  # Fix: explicit dependency ensures external locations exist before catalog is created/updated
  depends_on = [
    databricks_external_location.glue_ext,
    databricks_connection.glue
  ]

  provider = databricks.workspace
}

resource "databricks_grants" "glue_catalog_access" {
  for_each = databricks_catalog.glue_foreign_catalog

  catalog = each.value.name

  dynamic "grant" {
    for_each = var.workspace_admins
    content {
      principal  = grant.value
      privileges = ["ALL_PRIVILEGES", "MANAGE"]
    }
  }

  dynamic "grant" {
    for_each = var.workspace_users
    content {
      principal = grant.value
      privileges = [
        "USE_CATALOG",
        "USE_SCHEMA",
        "SELECT",
        "BROWSE"
      ]
    }
  }

  provider = databricks.workspace
}

# ================================
# Catalog Workspace Bindings
# ================================

# Bind each ISOLATED foreign catalog to this specific workspace only.
# OPEN catalogs are visible to all workspaces on the metastore and don't need bindings.

resource "databricks_workspace_binding" "glue_catalog_binding" {
  for_each = {
    for k, v in databricks_catalog.glue_foreign_catalog : k => v
    if var.databricks_workspace_id != "" && var.glue_catalogs[k].IsolationMode != "OPEN"
  }

  securable_name = each.value.name
  securable_type = "catalog"
  workspace_id   = var.databricks_workspace_id
  binding_type   = "BINDING_TYPE_READ_WRITE"

  provider = databricks.workspace
}
