// ============================================================================
// Azure Event Hubs Infrastructure for Voice Agent Analytics - Plan B
// ============================================================================
// This template deploys the ingestion infrastructure for the Plan B architecture:
// Agent → Event Hubs → Fabric Eventstream → Eventhouse → Power BI
//
// Based on: ADR-004 - Real-Time Metrics with Event Hubs and Fabric
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

// ----------------------------------------------------------------------------
// Keyless authentication (Managed Identity / Entra ID) — no SAS keys allowed
// ----------------------------------------------------------------------------
@description('Object ID (principalId) of the Fabric workspace identity that consumes telemetry. Required in production.')
param listenerPrincipalId string = ''

@description('Object ID (principalId) of an administrative identity granted full data access (Data Owner). Empty = skip the role assignment.')
param adminPrincipalId string = ''

@description('Principal type for the optional administrative RBAC assignment.')
@allowed(['ServicePrincipal', 'User', 'Group'])
param principalType string = 'ServicePrincipal'

@description('Log Analytics retention in days')
@minValue(30)
@maxValue(730)
param logRetentionDays int = 30

// Variables
var nameSuffix = '${projectName}-${environment}-${uniqueString(resourceGroup().id)}'
var eventHubNamespaceName = 'evhns-${nameSuffix}'
var eventHubName = 'evh-voiceagent-telemetry'
var producerIdentityName = 'id-${nameSuffix}-producer'
var logAnalyticsWorkspaceName = 'log-${nameSuffix}'
var consumerGroupFabric = 'fabric-eventstream'
var consumerGroupMonitoring = 'monitoring'

// Built-in Azure Event Hubs data-plane role definition IDs (RBAC — keyless)
var roleDataOwner = 'f526a384-b230-433a-b45c-95f59c4a2dec' // Azure Event Hubs Data Owner
var roleDataSender = '2b629674-e913-4c01-ae53-ef4638d8f975' // Azure Event Hubs Data Sender
var roleDataReceiver = 'a638d3c7-ab3a-418d-83e6-5f17a39d4fde' // Azure Event Hubs Data Receiver

// ============================================================================
// Managed Identity and Observability
// ============================================================================
resource producerIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: producerIdentityName
  location: location
  tags: tags
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionDays
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

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
    disableLocalAuth: true // No SAS keys — Microsoft Entra ID (Managed Identity) only, per security policy
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
// RBAC Role Assignments (Managed Identity — keyless auth)
// ============================================================================
// SAS authorization rules were removed: local auth is disabled, so access is
// granted exclusively via Microsoft Entra ID using the built-in data roles below.
// The producer identity is created by this template. The Fabric workspace identity
// is managed by Fabric and supplied as a principal ID for receiver access.

// Send-only access for the voice agent (scoped to the Event Hub)
resource sendRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(eventHub.id, producerIdentity.id, roleDataSender)
  scope: eventHub
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDataSender)
    principalId: producerIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Listen/receive access for Fabric Eventstream (scoped to the Event Hub)
resource listenRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(listenerPrincipalId)) {
  name: guid(eventHub.id, listenerPrincipalId, roleDataReceiver)
  scope: eventHub
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDataReceiver)
    principalId: listenerPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Full data access for administration (scoped to the namespace)
resource adminRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(adminPrincipalId)) {
  name: guid(eventHubNamespace.id, adminPrincipalId, roleDataOwner)
  scope: eventHubNamespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDataOwner)
    principalId: adminPrincipalId
    principalType: principalType
  }
}

// ============================================================================
// Diagnostic Settings
// ============================================================================
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: eventHubNamespace
  name: 'event-hubs-to-log-analytics'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
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

// ============================================================================
// Outputs
// ============================================================================
output eventHubNamespaceName string = eventHubNamespace.name
output eventHubNamespaceId string = eventHubNamespace.id
output eventHubName string = eventHub.name
output eventHubId string = eventHub.id
output producerIdentityId string = producerIdentity.id
output producerIdentityClientId string = producerIdentity.properties.clientId
output producerIdentityPrincipalId string = producerIdentity.properties.principalId
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

// No connection-string outputs: local auth is disabled (keyless). Clients authenticate
// with Microsoft Entra ID (Managed Identity) against the fully-qualified namespace below.
output eventHubNamespaceFqdn string = '${eventHubNamespace.name}.servicebus.windows.net'
output localAuthDisabled bool = eventHubNamespace.properties.disableLocalAuth

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
