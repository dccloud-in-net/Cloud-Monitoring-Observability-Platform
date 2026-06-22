variable "name"                { type = string }
variable "location"            { type = string }
variable "resource_group_name" { type = string }
variable "tags"                { type = map(string) }

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "this" {
  name                       = substr(replace("kv${var.name}", "-", ""), 0, 24)
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  enable_rbac_authorization  = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  tags                       = var.tags
}

# Grant the Terraform principal Key Vault Administrator so it can seed secrets.
resource "azurerm_role_assignment" "tf_admin" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "random_password" "grafana_admin" {
  length  = 24
  special = true
}

resource "azurerm_key_vault_secret" "grafana_admin_password" {
  name         = "grafana-admin-password"
  value        = random_password.grafana_admin.result
  key_vault_id = azurerm_key_vault.this.id

  depends_on = [azurerm_role_assignment.tf_admin]
}

output "id"   { value = azurerm_key_vault.this.id }
output "name" { value = azurerm_key_vault.this.name }
output "uri"  { value = azurerm_key_vault.this.vault_uri }
