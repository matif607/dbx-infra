locals {

  # Flatten the catalog map into individual external location entries
  glue_external_locations = merge([
    for catalog_key, catalog in var.glue_catalogs : {
      for path in catalog.AuthorizedPaths :
      "${catalog_key}/${path}" => {
        catalog_key = catalog_key
        path        = path
        catalog     = catalog
      }
    } if catalog.CreateExternalLocations
  ]...)

  # Determine if any catalog needs service credentials
  any_glue_catalog = length(var.glue_catalogs) > 0

  # Determine if any catalog is local (needs storage credentials)
  any_local_catalog = anytrue([for c in var.glue_catalogs : c.Local])

  # Catalogs that need connections created
  glue_connections = {
    for k, v in var.glue_catalogs : k => v if v.CreateConnection
  }

  #  Create a list of instance profile / group pairings
  instance_profile_group_pairs = flatten([
    for profile_key, profile in var.instance_profiles : [
      for group in profile.Groups : {
        key         = "${profile_key}-${group}"
        profile_key = profile_key
        group_name  = group
      }
    ]
  ])

}

