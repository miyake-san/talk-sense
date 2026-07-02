// ============================================================================
// Azure Event Hubs Infrastructure for Voice Agent Analytics - Plan B
// ============================================================================
// This template deploys the ingestion infrastructure for the Plan B architecture:
// Agent → Event Hubs → Fabric Eventstream → Eventhouse → Power BI
//
// Based on: ADR-002 - Ingestion via Fabric RTI
// ============================================================================

targetScope = 'resourceGroup'

// Parameters
@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment name (e.g., dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Project name prefix')
param projectName string = 'voiceagent'

@description('Event Hub namespace SKU')
@allowed(['Basic', 'Standard', 'Premium'])
param eventHubSku string = 'Standard'

@description('Event Hub capacity (Throughput Units)')
@minValue(1)
@maxValue(20)
param eventHubCapacity int = 1

@description('Event Hub message retention in days')
@minValue(1)
@maxValue(7)
param messageRetentionDays int = 7

@description('Event Hub partition count')
@minValue(2)
@maxValue(32)
param partitionCount int = 4

@description('Enable auto-inflate for Event Hub namespace')
param autoInflateEnabled bool = false

@description('Maximum throughput units when auto-inflate is enabled')
param maximumThroughputUnits int = 0

@description('Tags to apply to all resources')
param tags object = {
  Project: 'VoiceAgentAnalytics'
  Environment: environment
  ManagedBy: 'IaC-Bicep'
  Architecture: 'PlanB-FabricRTI'
}

// Variables
var nameSuffix = '${projectName}-${environment}-${uniqueString(resourceGroup().id)}'
var eventHubNamespaceName = 'evhns-${nameSuffix}'
var eventHubName = 'evh-voiceagent-telemetry'
var consumerGroupFabric = 'fabric-eventstream'
var consumerGroupMonitoring = 'monitoring'

// ============================================================================
// Event Hub Namespace
// ============================================================================
resource eventHubNamespace 'Microsoft.EventHub/namespaces@2024-01-01' = {
  name: eventHubNamespaceName
  location: location
  tags: tags
  sku: {
    name: eventHubSku
    tier: eventHubSku
    capacity: eventHubCapacity
  }
  properties: {
    isAutoInflateEnabled: autoInflateEnabled
    maximumThroughputUnits: autoInflateEnabled ? maximumThroughputUnits : 0
    zoneRedundant: environment == 'prod' ? true : false
    kafkaEnabled: true // Enable Kafka protocol
    disableLocalAuth: false // Keep SAS for initial POC; disable in production
    publicNetworkAccess: 'Enabled' // TODO: Change to 'Disabled' with Private Endpoint in prod
    minimumTlsVersion: '1.2'
  }
}

// ============================================================================
// Event Hub (Telemetry Stream)
// ============================================================================
resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = {
  parent: eventHubNamespace
  name: eventHubName
  properties: {
    messageRetentionInDays: messageRetentionDays
    partitionCount: partitionCount
    status: 'Active'
    captureDescription: null // No capture to storage for Plan B (Fabric handles persistence)
  }
}

// ============================================================================
// Consumer Groups
// ============================================================================
resource consumerGroupFabricResource 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2024-01-01' = {
  parent: eventHub
  name: consumerGroupFabric
  properties: {}
}

resource consumerGroupMonitoringResource 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2024-01-01' = {
  parent: eventHub
  name: consumerGroupMonitoring
  properties: {}
}

// ============================================================================
// Authorization Rules
// ============================================================================
// Send-only policy for the voice agent
resource sendOnlyPolicy 'Microsoft.EventHub/namespaces/eventhubs/authorizationRules@2024-01-01' = {
  parent: eventHub
  name: 'VoiceAgentSendPolicy'
  properties: {
    rights: ['Send']
  }
}

// Listen policy for Fabric Eventstream
resource fabricListenPolicy 'Microsoft.EventHub/namespaces/eventhubs/authorizationRules@2024-01-01' = {
  parent: eventHub
  name: 'FabricEventstreamPolicy'
  properties: {
    rights: ['Listen']
  }
}

// Manage policy for administration
resource managePolicy 'Microsoft.EventHub/namespaces/authorizationRules@2024-01-01' = {
  parent: eventHubNamespace
  name: 'AdminManagePolicy'
  properties: {
    rights: ['Send', 'Listen', 'Manage']
  }
}

// ============================================================================
// Diagnostic Settings (send metrics to Log Analytics)
// ============================================================================
// Note: Requires a Log Analytics workspace - uncomment and configure when ready
/*
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: eventHubNamespace
  name: 'EventHubDiagnostics'
  properties: {
    workspaceId: logAnalyticsWorkspaceId // Define this parameter
    logs: [
      {
        category: 'ArchiveLogs'
        enabled: true
      }
      {
        category: 'OperationalLogs'
        enabled: true
      }
      {
        category: 'AutoScaleLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}
*/

// ============================================================================
// Outputs
// ============================================================================
output eventHubNamespaceName string = eventHubNamespace.name
output eventHubNamespaceId string = eventHubNamespace.id
output eventHubName string = eventHub.name
output eventHubId string = eventHub.id

output voiceAgentConnectionString string = sendOnlyPolicy.listKeys().primaryConnectionString
output fabricEventstreamConnectionString string = fabricListenPolicy.listKeys().primaryConnectionString

output eventHubEndpoint string = eventHubNamespace.properties.serviceBusEndpoint
output kafkaEndpoint string = replace(eventHubNamespace.properties.serviceBusEndpoint, 'https://', '')

output consumerGroups array = [
  consumerGroupFabric
  consumerGroupMonitoring
]

output deploymentInfo object = {
  eventHubNamespace: eventHubNamespace.name
  eventHub: eventHub.name
  sku: eventHubSku
  capacity: eventHubCapacity
  partitions: partitionCount
  retention: messageRetentionDays
  consumerGroups: [consumerGroupFabric, consumerGroupMonitoring]
}
