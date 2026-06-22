variable "prefix" {
  description = "Short, DNS-safe prefix used as a base for all resource names."
  type        = string
  default     = "obsplat"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,12}$", var.prefix))
    error_message = "prefix must be 3-13 chars, start with a letter, lowercase/digits/hyphen only."
  }
}

variable "environment" {
  description = "Deployment environment (dev / staging / prod)."
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "eastus"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version. Leave null to use AKS default channel."
  type        = string
  default     = null
}

variable "system_node_count" {
  description = "Node count for the system node pool (control-plane add-ons)."
  type        = number
  default     = 2
}

variable "system_node_size" {
  description = "VM SKU for the system node pool."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "user_node_min" {
  description = "Minimum node count for the user (workload) pool — autoscaler floor."
  type        = number
  default     = 2
}

variable "user_node_max" {
  description = "Maximum node count for the user pool — autoscaler ceiling."
  type        = number
  default     = 5
}

variable "user_node_size" {
  description = "VM SKU for the user (workload) node pool."
  type        = string
  default     = "Standard_D4s_v5"
}

variable "observability_node_min" {
  description = "Minimum node count for the dedicated observability node pool."
  type        = number
  default     = 1
}

variable "observability_node_max" {
  description = "Maximum node count for the dedicated observability node pool."
  type        = number
  default     = 3
}

variable "observability_node_size" {
  description = "VM SKU for the observability node pool — sized for Prometheus + OTel + Loki."
  type        = string
  default     = "Standard_D4s_v5"
}

variable "vnet_cidr" {
  description = "CIDR for the VNet hosting AKS."
  type        = string
  default     = "10.40.0.0/16"
}

variable "aks_subnet_cidr" {
  description = "CIDR for the AKS node subnet."
  type        = string
  default     = "10.40.0.0/22"
}

variable "ingress_subnet_cidr" {
  description = "CIDR for ingress / load balancer subnet."
  type        = string
  default     = "10.40.4.0/24"
}

variable "log_retention_days" {
  description = "Log Analytics workspace retention in days."
  type        = number
  default     = 30
}

variable "enable_azure_rbac" {
  description = "Whether AKS should use Azure RBAC for Kubernetes authorization."
  type        = bool
  default     = true
}

variable "admin_group_object_ids" {
  description = "AAD group object IDs granted cluster-admin via AKS Azure RBAC."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    project    = "cloud-observability-platform"
    owner      = "platform-eng"
    managed_by = "terraform"
    cost_code  = "platform"
  }
}
