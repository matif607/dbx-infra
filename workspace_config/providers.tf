terraform {
  required_version = ">= 1.3.0"

  required_providers {
    databricks = {
      source = "databricks/databricks"
      # Version pinned in module because Bricks doesn't support
      # configuration_aliases without an explicit version constraint
      version               = "~> 1.115.0"
      configuration_aliases = [databricks.workspace]
    }
  }
}

# Workspace-level provider
provider "databricks" {
  alias         = "workspace"
  host          = var.databricks_workspace_host
  client_id     = var.databricks_service_principal
  client_secret = var.databricks_service_principal_secret
}
