# ==========================================
# Databricks Serverless Budget Policies
# ==========================================

resource "databricks_budget_policy" "serverless" {
  count = var.serverless ? 1 : 0

  binding_workspace_ids = [databricks_mws_workspaces.this.workspace_id]
  policy_name           = "${var.name}-serverless-budget-policy"

  custom_tags = [
    for k, v in var.aws_tags : {
      key   = k
      value = v
    }
  ]

  provider = databricks.mws
}
