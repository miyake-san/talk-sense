targetScope = 'subscription'

@description('Resource group that owns the TalkSense Azure resources')
param resourceGroupName string

@description('Location for the resource group and all resources')
param location string = 'eastus2'

@description('Environment name')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Project name prefix')
param projectName string = 'voiceagent'

@description('Event Hub namespace SKU')
@allowed(['Basic', 'Standard', 'Premium'])
param eventHubSku string = 'Standard'

@description('Event Hub capacity')
param eventHubCapacity int = 1

@description('Event Hub message retention in days')
param messageRetentionDays int = 7

@description('Event Hub partition count')
param partitionCount int = 4

@description('Enable Event Hubs auto-inflate')
param autoInflateEnabled bool = false

@description('Maximum throughput units when auto-inflate is enabled')
param maximumThroughputUnits int = 0

@description('Fabric workspace identity object ID')
param listenerPrincipalId string = ''

@description('Optional administrative principal object ID')
param adminPrincipalId string = ''

@description('Principal type for the optional administrative assignment')
@allowed(['ServicePrincipal', 'User', 'Group'])
param principalType string = 'ServicePrincipal'

@description('Log Analytics retention in days')
param logRetentionDays int = 30

@description('Tags applied to all resources')
param tags object = {
  Project: 'VoiceAgentAnalytics'
  Environment: environment
  ManagedBy: 'IaC-Bicep'
  Architecture: 'PlanB-FabricRTI'
}

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module talkSense 'main.bicep' = {
  name: 'talksense-${environment}'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    projectName: projectName
    eventHubSku: eventHubSku
    eventHubCapacity: eventHubCapacity
    messageRetentionDays: messageRetentionDays
    partitionCount: partitionCount
    autoInflateEnabled: autoInflateEnabled
    maximumThroughputUnits: maximumThroughputUnits
    listenerPrincipalId: listenerPrincipalId
    adminPrincipalId: adminPrincipalId
    principalType: principalType
    logRetentionDays: logRetentionDays
    tags: tags
  }
}

output resourceGroupId string = resourceGroup.id
output eventHubNamespaceName string = talkSense.outputs.eventHubNamespaceName
output eventHubName string = talkSense.outputs.eventHubName
output eventHubNamespaceFqdn string = talkSense.outputs.eventHubNamespaceFqdn
output kafkaEndpoint string = talkSense.outputs.kafkaEndpoint
output producerIdentityClientId string = talkSense.outputs.producerIdentityClientId
output producerIdentityPrincipalId string = talkSense.outputs.producerIdentityPrincipalId
output logAnalyticsWorkspaceId string = talkSense.outputs.logAnalyticsWorkspaceId
output localAuthDisabled bool = talkSense.outputs.localAuthDisabled
