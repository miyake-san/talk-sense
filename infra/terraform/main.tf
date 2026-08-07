# ============================================================================
# Azure Event Hubs Infrastructure for Voice Agent Analytics - Plan B
# ============================================================================
# Terraform configuration for:
# Agent → Event Hubs → Fabric Eventstream → Eventhouse → Power BI
#
# Based on: ADR-004 - Real-Time Metrics with Event Hubs and Fabric
# ============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# ============================================================================
# Variables
# ============================================================================

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus2"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "voiceagent"
}

variable "eventhub_sku" {
  description = "Event Hub namespace SKU"
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.eventhub_sku)
    error_message = "SKU must be Basic, Standard, or Premium."
  }
}

variable "eventhub_capacity" {
  description = "Event Hub capacity (Throughput Units)"
  type        = number
  default     = 1

  validation {
    condition     = var.eventhub_capacity >= 1 && var.eventhub_capacity <= 20
    error_message = "Capacity must be between 1 and 20."
  }
}

variable "message_retention_days" {
  description = "Event Hub message retention in days"
  type        = number
  default     = 7

  validation {
    condition     = var.message_retention_days >= 1 && var.message_retention_days <= 7
    error_message = "Retention must be between 1 and 7 days."
  }
}

variable "partition_count" {
  description = "Event Hub partition count"
  type        = number
  default     = 4

  validation {
    condition     = var.partition_count >= 2 && var.partition_count <= 32
    error_message = "Partition count must be between 2 and 32."
  }
}

variable "auto_inflate_enabled" {
  description = "Enable auto-inflate for Event Hub namespace"
  type        = bool
  default     = false
}

variable "maximum_throughput_units" {
  description = "Maximum throughput units when auto-inflate is enabled"
  type        = number
  default     = 0
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ----------------------------------------------------------------------------
# Keyless authentication (Managed Identity / Entra ID) — no SAS keys allowed
# ----------------------------------------------------------------------------

variable "listener_principal_id" {
  description = "Object ID of the Fabric workspace identity that consumes telemetry. Required in production."
  type        = string
  default     = ""
}

variable "admin_principal_id" {
  description = "Object ID of an admin identity granted full data access (Data Owner). Empty = skip role assignment."
  type        = string
  default     = ""
}

variable "principal_type" {
  description = "Principal type for the optional administrative RBAC assignment."
  type        = string
  default     = "ServicePrincipal"

  validation {
    condition     = contains(["ServicePrincipal", "User", "Group"], var.principal_type)
    error_message = "principal_type must be ServicePrincipal, User, or Group."
  }
}

variable "log_retention_days" {
  description = "Log Analytics retention in days"
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "log_retention_days must be between 30 and 730."
  }
}

# ============================================================================
# Local Variables
# ============================================================================

locals {
  name_suffix = "${var.project_name}-${var.environment}-${random_string.suffix.result}"

  common_tags = merge(
    {
      Project      = "VoiceAgentAnalytics"
      Environment  = var.environment
      ManagedBy    = "Terraform"
      Architecture = "PlanB-FabricRTI"
    },
    var.tags
  )

  eventhub_namespace_name   = "evhns-${local.name_suffix}"
  eventhub_name             = "evh-voiceagent-telemetry"
  producer_identity_name    = "id-${local.name_suffix}-producer"
  log_analytics_name        = "log-${local.name_suffix}"
  consumer_group_fabric     = "fabric-eventstream"
  consumer_group_monitoring = "monitoring"
}

# ============================================================================
# Random Suffix
# ============================================================================

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ============================================================================
# Resource Group
# ============================================================================

resource "azurerm_resource_group" "main" {
  name     = "rg-voiceagent-analytics-${var.environment}"
  location = var.location
  tags     = local.common_tags
}

# ============================================================================
# Managed Identity and Observability
# ============================================================================

resource "azurerm_user_assigned_identity" "producer" {
  name                = local.producer_identity_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = local.log_analytics_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.common_tags
}

# ============================================================================
# Event Hub Namespace
# ============================================================================

resource "azurerm_eventhub_namespace" "main" {
  name                     = local.eventhub_namespace_name
  location                 = azurerm_resource_group.main.location
  resource_group_name      = azurerm_resource_group.main.name
  sku                      = var.eventhub_sku
  capacity                 = var.eventhub_capacity
  auto_inflate_enabled     = var.auto_inflate_enabled
  maximum_throughput_units = var.auto_inflate_enabled ? var.maximum_throughput_units : 0
  # Kafka protocol is auto-enabled for Standard/Premium namespaces (no argument in azurerm)

  # Security settings
  local_authentication_enabled  = false # No SAS keys — Entra ID (Managed Identity) only, per security policy
  public_network_access_enabled = true  # TODO: Change to false with Private Endpoint in prod
  minimum_tls_version           = "1.2"

  tags = local.common_tags

  lifecycle {
    precondition {
      condition     = var.environment != "prod" || var.listener_principal_id != ""
      error_message = "listener_principal_id is required for production deployments."
    }
  }
}

# ============================================================================
# Event Hub (Telemetry Stream)
# ============================================================================

resource "azurerm_eventhub" "telemetry" {
  name                = local.eventhub_name
  namespace_name      = azurerm_eventhub_namespace.main.name
  resource_group_name = azurerm_resource_group.main.name
  partition_count     = var.partition_count
  message_retention   = var.message_retention_days
  status              = "Active"
}

# ============================================================================
# Consumer Groups
# ============================================================================

resource "azurerm_eventhub_consumer_group" "fabric" {
  name                = local.consumer_group_fabric
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.telemetry.name
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_eventhub_consumer_group" "monitoring" {
  name                = local.consumer_group_monitoring
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.telemetry.name
  resource_group_name = azurerm_resource_group.main.name
}

# ============================================================================
# RBAC Role Assignments (Managed Identity — keyless auth)
# ============================================================================
# SAS authorization rules were removed: local auth is disabled, so access is
# granted exclusively via Microsoft Entra ID using the built-in data roles below.
# The producer identity is created by Terraform. The Fabric workspace identity
# is managed by Fabric and supplied as a principal ID for receiver access.

# Send-only access for the voice agent (scoped to the Event Hub)
resource "azurerm_role_assignment" "sender" {
  scope                = azurerm_eventhub.telemetry.id
  role_definition_name = "Azure Event Hubs Data Sender"
  principal_id         = azurerm_user_assigned_identity.producer.principal_id
  principal_type       = "ServicePrincipal"
}

# Listen/receive access for Fabric Eventstream (scoped to the Event Hub)
resource "azurerm_role_assignment" "listener" {
  count                = var.listener_principal_id == "" ? 0 : 1
  scope                = azurerm_eventhub.telemetry.id
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = var.listener_principal_id
  principal_type       = "ServicePrincipal"
}

# Full data access for administration (scoped to the namespace)
resource "azurerm_role_assignment" "admin" {
  count                = var.admin_principal_id == "" ? 0 : 1
  scope                = azurerm_eventhub_namespace.main.id
  role_definition_name = "Azure Event Hubs Data Owner"
  principal_id         = var.admin_principal_id
  principal_type       = var.principal_type
}

# ============================================================================
# Diagnostic Settings
# ============================================================================

resource "azurerm_monitor_diagnostic_setting" "eventhub" {
  name                       = "event-hubs-to-log-analytics"
  target_resource_id         = azurerm_eventhub_namespace.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# ============================================================================
# Outputs
# ============================================================================

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "eventhub_namespace_name" {
  description = "Name of the Event Hub namespace"
  value       = azurerm_eventhub_namespace.main.name
}

output "eventhub_namespace_id" {
  description = "ID of the Event Hub namespace"
  value       = azurerm_eventhub_namespace.main.id
}

output "eventhub_name" {
  description = "Name of the Event Hub"
  value       = azurerm_eventhub.telemetry.name
}

output "eventhub_id" {
  description = "ID of the Event Hub"
  value       = azurerm_eventhub.telemetry.id
}

output "producer_identity_id" {
  description = "Resource ID of the producer user-assigned managed identity"
  value       = azurerm_user_assigned_identity.producer.id
}

output "producer_identity_client_id" {
  description = "Client ID used to select the producer user-assigned managed identity"
  value       = azurerm_user_assigned_identity.producer.client_id
}

output "producer_identity_principal_id" {
  description = "Principal ID granted Azure Event Hubs Data Sender"
  value       = azurerm_user_assigned_identity.producer.principal_id
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

# No connection-string outputs: local auth is disabled (keyless). Clients authenticate
# with Microsoft Entra ID (Managed Identity) against the fully-qualified namespace below.
output "eventhub_namespace_fqdn" {
  description = "Fully-qualified Event Hub namespace for Entra ID (Managed Identity) auth"
  value       = "${azurerm_eventhub_namespace.main.name}.servicebus.windows.net"
}

output "local_auth_disabled" {
  description = "Whether SAS/local auth is disabled on the namespace"
  value       = !azurerm_eventhub_namespace.main.local_authentication_enabled
}

output "kafka_endpoint" {
  description = "Kafka endpoint for Event Hub namespace"
  value       = "${azurerm_eventhub_namespace.main.name}.servicebus.windows.net:9093"
}

output "consumer_groups" {
  description = "List of consumer groups"
  value = [
    azurerm_eventhub_consumer_group.fabric.name,
    azurerm_eventhub_consumer_group.monitoring.name
  ]
}

output "deployment_info" {
  description = "Deployment information"
  value = {
    eventhub_namespace = azurerm_eventhub_namespace.main.name
    eventhub           = azurerm_eventhub.telemetry.name
    sku                = var.eventhub_sku
    capacity           = var.eventhub_capacity
    partitions         = var.partition_count
    retention_days     = var.message_retention_days
    consumer_groups    = [local.consumer_group_fabric, local.consumer_group_monitoring]
    location           = var.location
    environment        = var.environment
  }
}
