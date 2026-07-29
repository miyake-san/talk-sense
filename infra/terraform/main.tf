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
  
  eventhub_namespace_name = "evhns-${local.name_suffix}"
  eventhub_name          = "evh-voiceagent-telemetry"
  consumer_group_fabric  = "fabric-eventstream"
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
  zone_redundant           = var.environment == "prod" ? true : false
  
  # Enable Kafka protocol
  kafka_enabled = true
  
  # Security settings
  local_auth_enabled     = true # Keep SAS for POC; disable in production
  public_network_access_enabled = true # TODO: Change to false with Private Endpoint in prod
  minimum_tls_version    = "1.2"
  
  tags = local.common_tags
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
# Authorization Rules
# ============================================================================

# Send-only policy for the voice agent
resource "azurerm_eventhub_authorization_rule" "voice_agent_send" {
  name                = "VoiceAgentSendPolicy"
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.telemetry.name
  resource_group_name = azurerm_resource_group.main.name
  
  listen = false
  send   = true
  manage = false
}

# Listen policy for Fabric Eventstream
resource "azurerm_eventhub_authorization_rule" "fabric_listen" {
  name                = "FabricEventstreamPolicy"
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.telemetry.name
  resource_group_name = azurerm_resource_group.main.name
  
  listen = true
  send   = false
  manage = false
}

# Manage policy for administration (namespace level)
resource "azurerm_eventhub_namespace_authorization_rule" "admin_manage" {
  name                = "AdminManagePolicy"
  namespace_name      = azurerm_eventhub_namespace.main.name
  resource_group_name = azurerm_resource_group.main.name
  
  listen = true
  send   = true
  manage = true
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

output "voice_agent_connection_string" {
  description = "Connection string for the voice agent (Send-only) - SENSITIVE"
  value       = azurerm_eventhub_authorization_rule.voice_agent_send.primary_connection_string
  sensitive   = true
}

output "fabric_eventstream_connection_string" {
  description = "Connection string for Fabric Eventstream (Listen-only) - SENSITIVE"
  value       = azurerm_eventhub_authorization_rule.fabric_listen.primary_connection_string
  sensitive   = true
}

output "eventhub_endpoint" {
  description = "Service Bus endpoint for Event Hub namespace"
  value       = azurerm_eventhub_namespace.main.default_primary_connection_string
  sensitive   = true
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
    eventhub          = azurerm_eventhub.telemetry.name
    sku               = var.eventhub_sku
    capacity          = var.eventhub_capacity
    partitions        = var.partition_count
    retention_days    = var.message_retention_days
    consumer_groups   = [local.consumer_group_fabric, local.consumer_group_monitoring]
    location          = var.location
    environment       = var.environment
  }
}
