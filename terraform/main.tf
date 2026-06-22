resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
  numeric = true
}

locals {
  name = "${var.prefix}-${var.environment}-${random_string.suffix.result}"

  base_tags = merge(var.tags, {
    environment = var.environment
    stack       = "observability"
  })
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${local.name}"
  location = var.location
  tags     = local.base_tags
}

# ────────────────────────────────────────────────────────────────────
#  Networking
# ────────────────────────────────────────────────────────────────────
module "networking" {
  source              = "./modules/networking"
  name                = local.name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  vnet_cidr           = var.vnet_cidr
  aks_subnet_cidr     = var.aks_subnet_cidr
  ingress_subnet_cidr = var.ingress_subnet_cidr
  tags                = local.base_tags
}

# ────────────────────────────────────────────────────────────────────
#  Container Registry — hosts the demo app image + future workloads
# ────────────────────────────────────────────────────────────────────
module "registry" {
  source              = "./modules/registry"
  name                = local.name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.base_tags
}

# ────────────────────────────────────────────────────────────────────
#  Key Vault — Grafana admin secret, Alertmanager webhooks, etc.
# ────────────────────────────────────────────────────────────────────
module "keyvault" {
  source              = "./modules/keyvault"
  name                = local.name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.base_tags
}

# ────────────────────────────────────────────────────────────────────
#  Observability — Log Analytics workspace + Container Insights DCR
# ────────────────────────────────────────────────────────────────────
resource "azurerm_log_analytics_workspace" "this" {
  name                = "law-${local.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.base_tags
}

resource "azurerm_application_insights" "this" {
  name                = "appi-${local.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
  tags                = local.base_tags
}

# Azure Monitor Workspace — the managed Prometheus endpoint.
resource "azurerm_monitor_workspace" "this" {
  name                = "amw-${local.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.base_tags
}

# ────────────────────────────────────────────────────────────────────
#  AKS cluster + node pools
# ────────────────────────────────────────────────────────────────────
module "aks" {
  source                          = "./modules/aks"
  name                            = local.name
  location                        = var.location
  resource_group_name             = azurerm_resource_group.this.name
  kubernetes_version              = var.kubernetes_version
  subnet_id                       = module.networking.aks_subnet_id
  log_analytics_workspace_id      = azurerm_log_analytics_workspace.this.id
  acr_id                          = module.registry.id
  monitor_workspace_id            = azurerm_monitor_workspace.this.id
  enable_azure_rbac               = var.enable_azure_rbac
  admin_group_object_ids          = var.admin_group_object_ids

  system_node_count = var.system_node_count
  system_node_size  = var.system_node_size

  user_node_min  = var.user_node_min
  user_node_max  = var.user_node_max
  user_node_size = var.user_node_size

  observability_node_min  = var.observability_node_min
  observability_node_max  = var.observability_node_max
  observability_node_size = var.observability_node_size

  tags = local.base_tags
}

# Grant the AKS kubelet identity Key Vault Secrets User so the CSI driver
# can pull secrets at runtime.
resource "azurerm_role_assignment" "kubelet_keyvault_secrets_user" {
  scope                = module.keyvault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.aks.kubelet_identity_object_id
}

# ────────────────────────────────────────────────────────────────────
#  Data Collection Rule — Container Insights → Log Analytics
# ────────────────────────────────────────────────────────────────────
resource "azurerm_monitor_data_collection_rule" "container_insights" {
  name                = "dcr-${local.name}-ci"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  kind                = "Linux"
  tags                = local.base_tags

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.this.id
      name                  = "law-dest"
    }
  }

  data_flow {
    streams      = ["Microsoft-ContainerInsights-Group-Default"]
    destinations = ["law-dest"]
  }

  data_sources {
    extension {
      streams        = ["Microsoft-ContainerInsights-Group-Default"]
      extension_name = "ContainerInsights"
      name           = "ContainerInsightsExtension"
    }
  }
}

resource "azurerm_monitor_data_collection_rule_association" "container_insights" {
  name                    = "dcra-${local.name}-ci"
  target_resource_id      = module.aks.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.container_insights.id
}

# Diagnostic settings on the AKS control plane.
resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                       = "diag-${local.name}-aks"
  target_resource_id         = module.aks.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log { category = "kube-apiserver" }
  enabled_log { category = "kube-controller-manager" }
  enabled_log { category = "kube-scheduler" }
  enabled_log { category = "kube-audit-admin" }
  enabled_log { category = "cluster-autoscaler" }
  enabled_log { category = "guard" }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
