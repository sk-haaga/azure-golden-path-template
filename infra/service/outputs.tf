output "url" {
  description = "Public HTTPS URL of the service."
  value       = module.app.url
}

output "app_name" {
  value = module.app.app_name
}

output "resource_group_name" {
  value = data.azurerm_resource_group.this.name
}

output "latest_revision_name" {
  value = module.app.latest_revision_name
}
