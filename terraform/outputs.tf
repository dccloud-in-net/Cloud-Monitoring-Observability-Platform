output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "aks_name" {
  value = module.aks.name
}

output "aks_id" {
  value = module.aks.id
}

output "aks_oidc_issuer_url" {
  value = module.aks.oidc_issuer_url
}

output "acr_name" {
  value = module.registry.name
}

output "acr_login_server" {
  value = module.registry.login_server
}

output "key_vault_name" {
  value = module.keyvault.name
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.this.id
}

output "log_analytics_workspace_name" {
  value = azurerm_log_analytics_workspace.this.name
}

output "app_insights_connection_string" {
  value     = azurerm_application_insights.this.connection_string
  sensitive = true
}

output "azure_monitor_workspace_id" {
  value = azurerm_monitor_workspace.this.id
}

output "azure_monitor_query_endpoint" {
  value = azurerm_monitor_workspace.this.query_endpoint
}

output "kube_config" {
  value     = module.aks.kube_config_raw
  sensitive = true
}
