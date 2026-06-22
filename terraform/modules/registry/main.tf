variable "name"                { type = string }
variable "location"            { type = string }
variable "resource_group_name" { type = string }
variable "tags"                { type = map(string) }

resource "azurerm_container_registry" "this" {
  name                = replace("acr${var.name}", "-", "")
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Standard"
  admin_enabled       = false
  tags                = var.tags

  retention_policy {
    days    = 30
    enabled = true
  }
}

output "id"           { value = azurerm_container_registry.this.id }
output "name"         { value = azurerm_container_registry.this.name }
output "login_server" { value = azurerm_container_registry.this.login_server }
