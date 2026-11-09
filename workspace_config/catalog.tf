# ========================
# Databricks Unity Catalog
# ========================

# Create Unity Catalog catalogs dynamically
resource "databricks_catalog" "workspace_catalog" {
  name          = "${var.name}-catalog"
  comment       = "Catalog for ${var.name} workspace"
  force_destroy = true

  provider = databricks.workspace
}

# Grant catalog permissions to workspace admins, users, and service principal
resource "databricks_grants" "catalog_grants" {
  catalog = databricks_catalog.workspace_catalog.name

  # Workspace admin groups
  dynamic "grant" {
    for_each = var.workspace_admins
    content {
      principal  = grant.value
      privileges = ["CREATE_SCHEMA", "MODIFY", "SELECT", "USE_CATALOG", "USE_SCHEMA"]
    }
  }

  # Workspace user groups (read-only)
  dynamic "grant" {
    for_each = var.workspace_users
    content {
      principal  = grant.value
      privileges = ["SELECT", "USE_CATALOG", "USE_SCHEMA"]
    }
  }

  # Service Principal (admin access for Terraform automation)
  dynamic "grant" {
    for_each = [var.databricks_service_principal]
    content {
      principal  = grant.value
      privileges = ["CREATE_SCHEMA", "MODIFY", "SELECT", "USE_CATALOG", "USE_SCHEMA"]
    }
  }

  provider = databricks.workspace
}

# Grant permissions on Metastore for users to create external locations
resource "databricks_grants" "metastore_grants" {
  metastore = var.metastore_id

  # Admin groups - full metastore access
  dynamic "grant" {
    for_each = var.workspace_admins
    content {
      principal  = grant.value
      privileges = ["CREATE_CATALOG", "CREATE_EXTERNAL_LOCATION", "CREATE_STORAGE_CREDENTIAL"]
    }
  }

  # User groups - limited metastore access (cannot create catalogs)
  dynamic "grant" {
    for_each = var.workspace_users
    content {
      principal  = grant.value
      privileges = ["CREATE_EXTERNAL_LOCATION", "CREATE_STORAGE_CREDENTIAL"]
    }
  }

  provider = databricks.workspace
}

resource "databricks_grants" "storage_credential_access" {
  for_each = {
    for k, v in var.external_locations : k => v if v.StorageCredentialName != "" || v.StorageCredential != null
  }

  storage_credential = each.value.StorageCredential != null ? databricks_storage_credential.external_location[each.key].name : each.value.StorageCredentialName

  dynamic "grant" {
    for_each = var.workspace_admins
    content {
      principal  = grant.value
      privileges = ["ALL_PRIVILEGES"]
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

resource "databricks_external_location" "s3_external" {
  for_each = var.external_locations

  name            = each.value.Name
  url             = each.value.BucketPath
  credential_name = each.value.StorageCredential != null ? databricks_storage_credential.external_location[each.key].name : each.value.StorageCredentialName
  comment         = each.value.Comment
  force_destroy   = true
  force_update    = true
  skip_validation = true

  isolation_mode     = each.value.IsolationMode
  enable_file_events = each.value.EnableFileEvents
  read_only          = each.value.ReadOnly

  dynamic "file_event_queue" {
    for_each = each.value.EnableFileEvents ? [1] : []
    content {
      managed_sqs {}
    }
  }

  provider = databricks.workspace
}

resource "databricks_grants" "s3_external_access" {
  for_each = {
    for k, v in databricks_external_location.s3_external : k => v if var.external_locations[k].IngestServicePrincipalId == ""
  }

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
      privileges = ["READ_FILES", "WRITE_FILES", "CREATE_EXTERNAL_TABLE"]
    }
  }

  provider = databricks.workspace
}
