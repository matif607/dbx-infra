terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    databricks = {
      source = "databricks/databricks"
      # Version pinned in module because Bricks doesn't support
      # configuration_aliases without an explicit version constraint
      version               = "~> 1.115.0"
      configuration_aliases = [databricks.mws]
    }
  }
}

provider "databricks" {
  alias         = "mws"
  host          = var.databricks_host
  account_id    = var.databricks_account
  client_id     = var.databricks_service_principal
  client_secret = var.databricks_service_principal_secret
}
