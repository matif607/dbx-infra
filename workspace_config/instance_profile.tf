# ========================================
# Databricks Instance Profile Registration
# ========================================

resource "databricks_instance_profile" "instance_profile" {
  provider             = databricks.workspace
  for_each             = var.instance_profiles
  instance_profile_arn = each.value.Arn
  skip_validation      = try(each.value.SkipValidation, false)
}

# =============================================
# Databricks Group Lookup
# =============================================

data "databricks_group" "ad_group" {
  provider     = databricks.workspace
  for_each     = toset(flatten([for p in var.instance_profiles : p.Groups]))
  display_name = each.value
}

# =============================================
# Instance Profile Group Permission Assignment
# =============================================

resource "databricks_group_role" "group_instance_profile" {
  provider = databricks.workspace
  for_each = { for pair in local.instance_profile_group_pairs : pair.key => pair }
  group_id = data.databricks_group.ad_group[each.value.group_name].id
  role     = databricks_instance_profile.instance_profile[each.value.profile_key].id
}
