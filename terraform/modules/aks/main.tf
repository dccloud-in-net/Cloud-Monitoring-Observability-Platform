variable "name"                       { type = string }
variable "location"                   { type = string }
variable "resource_group_name"        { type = string }
variable "kubernetes_version"         { type = string }
variable "subnet_id"                  { type = string }
variable "log_analytics_workspace_id" { type = string }
variable "acr_id"                     { type = string }
variable "monitor_workspace_id"       { type = string }
variable "enable_azure_rbac"          { type = bool }
variable "admin_group_object_ids" {
  type    = list(string)
  default = []
}

variable "system_node_count" { type = number }
variable "system_node_size"  { type = string }

variable "user_node_min"  { type = number }
variable "user_node_max"  { type = number }
variable "user_node_size" { type = string }

variable "observability_node_min"  { type = number }
variable "observability_node_max"  { type = number }
variable "observability_node_size" { type = string }

variable "tags" { type = map(string) }

resource "azurerm_user_assigned_identity" "cluster" {
  name                = "id-aks-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_kubernetes_cluster" "this" {
  name                              = "aks-${var.name}"
  location                          = var.location
  resource_group_name               = var.resource_group_name
  dns_prefix                        = var.name
  kubernetes_version                = var.kubernetes_version
  sku_tier                          = "Standard"
  azure_policy_enabled              = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true
  role_based_access_control_enabled = true
  local_account_disabled            = false
  tags                              = var.tags

  default_node_pool {
    name                 = "system"
    vm_size              = var.system_node_size
    node_count           = var.system_node_count
    vnet_subnet_id       = var.subnet_id
    os_disk_size_gb      = 64
    type                 = "VirtualMachineScaleSets"
    orchestrator_version = var.kubernetes_version
    only_critical_addons_enabled = true
    upgrade_settings {
      max_surge = "33%"
    }
    node_labels = {
      "workload" = "system"
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cluster.id]
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    load_balancer_sku = "standard"
    outbound_type     = "loadBalancer"
  }

  oms_agent {
    log_analytics_workspace_id      = var.log_analytics_workspace_id
    msi_auth_for_monitoring_enabled = true
  }

  monitor_metrics {
    annotations_allowed = null
    labels_allowed      = null
  }

  dynamic "azure_active_directory_role_based_access_control" {
    for_each = var.enable_azure_rbac ? [1] : []
    content {
      managed                = true
      azure_rbac_enabled     = true
      admin_group_object_ids = var.admin_group_object_ids
    }
  }

  auto_scaler_profile {
    balance_similar_node_groups   = true
    expander                      = "least-waste"
    max_graceful_termination_sec  = "600"
    scale_down_delay_after_add    = "10m"
    scale_down_unneeded           = "10m"
  }

  maintenance_window_auto_upgrade {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Sunday"
    start_time  = "03:00"
    utc_offset  = "+00:00"
  }

  lifecycle {
    ignore_changes = [
      default_node_pool[0].node_count,
      kubernetes_version,
    ]
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = var.user_node_size
  vnet_subnet_id        = var.subnet_id
  os_disk_size_gb       = 128
  mode                  = "User"

  enable_auto_scaling = true
  min_count           = var.user_node_min
  max_count           = var.user_node_max

  node_labels = {
    "workload" = "apps"
  }

  upgrade_settings {
    max_surge = "33%"
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [node_count]
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "observability" {
  name                  = "obs"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = var.observability_node_size
  vnet_subnet_id        = var.subnet_id
  os_disk_size_gb       = 256
  mode                  = "User"

  enable_auto_scaling = true
  min_count           = var.observability_node_min
  max_count           = var.observability_node_max

  node_labels = {
    "workload" = "observability"
  }

  node_taints = [
    "workload=observability:NoSchedule"
  ]

  upgrade_settings {
    max_surge = "33%"
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [node_count]
  }
}

# AKS needs Network Contributor on the subnet to wire up LoadBalancers
# and Private Endpoints.
resource "azurerm_role_assignment" "aks_network" {
  scope                = var.subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.cluster.principal_id
}

# Let kubelet pull from ACR without secrets.
resource "azurerm_role_assignment" "kubelet_acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}

# Managed Prometheus → AKS via Monitoring Data Reader role.
resource "azurerm_role_assignment" "aks_monitoring_reader" {
  scope                = var.monitor_workspace_id
  role_definition_name = "Monitoring Data Reader"
  principal_id         = azurerm_user_assigned_identity.cluster.principal_id
}

locals {
  # When Azure RBAC is enabled the admin config provides cluster-admin via
  # local accounts; otherwise the standard kube_config is the right one.
  effective_config = var.enable_azure_rbac && length(azurerm_kubernetes_cluster.this.kube_admin_config) > 0 ? azurerm_kubernetes_cluster.this.kube_admin_config[0] : azurerm_kubernetes_cluster.this.kube_config[0]
}

output "id"                         { value = azurerm_kubernetes_cluster.this.id }
output "name"                       { value = azurerm_kubernetes_cluster.this.name }
output "oidc_issuer_url"            { value = azurerm_kubernetes_cluster.this.oidc_issuer_url }
output "kubelet_identity_object_id" { value = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id }
output "cluster_identity_object_id" { value = azurerm_user_assigned_identity.cluster.principal_id }

output "kube_config" {
  value = {
    host                   = local.effective_config.host
    client_certificate     = local.effective_config.client_certificate
    client_key             = local.effective_config.client_key
    cluster_ca_certificate = local.effective_config.cluster_ca_certificate
  }
  sensitive = true
}

output "kube_config_raw" {
  value     = azurerm_kubernetes_cluster.this.kube_config_raw
  sensitive = true
}
