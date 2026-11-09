resource "databricks_storage_credential" "external_location" {
  for_each = {
    for k, v in var.external_locations : k => v if v.StorageCredential != null
  }

  name = each.value.StorageCredential.Name

  aws_iam_role {
    role_arn = each.value.StorageCredential.RoleArn
  }

  comment = each.value.StorageCredential.Comment

  provider = databricks.workspace
}

resource "databricks_grants" "s3_external_ingest_access" {
  for_each = {
    for k, v in var.external_locations : k => v if v.IngestServicePrincipalId != ""
  }

  external_location = databricks_external_location.s3_external[each.key].id

  grant {
    principal  = each.value.IngestServicePrincipalId
    privileges = ["READ_FILES"]
  }

  provider = databricks.workspace
}
