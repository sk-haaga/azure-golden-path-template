output "app_name" {
  value = azurerm_container_app.this.name
}

output "fqdn" {
  value = azurerm_container_app.this.ingress[0].fqdn
}

output "url" {
  value = "https://${azurerm_container_app.this.ingress[0].fqdn}"
}

output "latest_revision_name" {
  value = azurerm_container_app.this.latest_revision_name
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.this.id
}
