#!/usr/bin/env pwsh
# ============================================================================
# Deploy Event Hubs Infrastructure for Voice Agent Analytics - Plan B
# ============================================================================

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment = 'dev',
    
    [Parameter(Mandatory=$false)]
    [string]$TenantId = '1a828a01-604c-42e6-86dd-a5fcc38a6969',

    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId = '401f453f-7b92-4e20-9c55-265205a1b26f',
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "rg-voiceagent-analytics-$Environment",
    
    [Parameter(Mandatory=$false)]
    [string]$Location = 'eastus2',

    [Parameter(Mandatory=$false)]
    [string]$FabricWorkspacePrincipalId = '',

    [Parameter(Mandatory=$false)]
    [string]$AdminPrincipalId = '',
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

if ($Environment -eq 'prod' -and [string]::IsNullOrWhiteSpace($FabricWorkspacePrincipalId)) {
    throw 'FabricWorkspacePrincipalId is required for production deployments.'
}

Write-Host "🚀 Deploying Voice Agent Analytics Infrastructure - Plan B" -ForegroundColor Cyan
Write-Host "Environment: $Environment" -ForegroundColor Yellow
Write-Host "Location: $Location" -ForegroundColor Yellow

# Select and verify the approved Azure context.
Write-Host "Setting subscription: $SubscriptionId" -ForegroundColor Yellow
az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) {
    throw "Unable to select subscription $SubscriptionId. Authenticate with: az login --tenant $TenantId"
}

# Get current subscription
$currentSub = az account show --query "{name:name, id:id, tenantId:tenantId}" -o json | ConvertFrom-Json
if ($currentSub.id -ne $SubscriptionId -or $currentSub.tenantId -ne $TenantId) {
    throw "Azure context mismatch. Expected tenant $TenantId and subscription $SubscriptionId; got tenant $($currentSub.tenantId) and subscription $($currentSub.id)."
}
Write-Host "Using subscription: $($currentSub.name) ($($currentSub.id))" -ForegroundColor Green

# Deploy Bicep template
Write-Host "`n🏗️  Deploying Event Hubs infrastructure..." -ForegroundColor Cyan

$deploymentName = "voiceagent-planb-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$bicepFile = Join-Path $PSScriptRoot "main.subscription.bicep"
$parametersFile = Join-Path $PSScriptRoot "main.parameters.$Environment.json"

if (-not (Test-Path $bicepFile)) {
    Write-Error "Bicep file not found: $bicepFile"
    exit 1
}

if (-not (Test-Path $parametersFile)) {
    Write-Warning "Parameters file not found: $parametersFile. Using defaults."
    $parametersFile = $null
}

$deployCmd = @(
    'az', 'deployment', 'sub', 'create'
    '--name', $deploymentName
    '--location', $Location
    '--template-file', $bicepFile
)

if ($parametersFile) {
    $deployCmd += '--parameters', $parametersFile
}

$deployCmd += '--parameters', "resourceGroupName=$ResourceGroupName", "listenerPrincipalId=$FabricWorkspacePrincipalId", "adminPrincipalId=$AdminPrincipalId"

if ($WhatIf) {
    $deployCmd += '--what-if'
    Write-Host "Running in WhatIf mode..." -ForegroundColor Yellow
}

Write-Host "Deployment command: $($deployCmd -join ' ')" -ForegroundColor Gray

if ($WhatIf) {
    & $deployCmd[0] $deployCmd[1..($deployCmd.Length-1)]
    if ($LASTEXITCODE -ne 0) {
        throw "WhatIf failed with exit code $LASTEXITCODE"
    }

    Write-Host "`n✨ WhatIf completed. No resources were changed." -ForegroundColor Cyan
    return
}

$deployment = & $deployCmd[0] $deployCmd[1..($deployCmd.Length-1)] | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) {
    Write-Error "Deployment failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

if (-not $WhatIf) {
    Write-Host "`n✅ Deployment completed successfully!" -ForegroundColor Green
    Write-Host "`n📋 Deployment Outputs:" -ForegroundColor Cyan
    
    $outputs = $deployment.properties.outputs
    
    Write-Host "Event Hub Namespace: $($outputs.eventHubNamespaceName.value)" -ForegroundColor White
    Write-Host "Event Hub Name: $($outputs.eventHubName.value)" -ForegroundColor White
    Write-Host "Namespace FQDN: $($outputs.eventHubNamespaceFqdn.value)" -ForegroundColor White
    Write-Host "Kafka Endpoint: $($outputs.kafkaEndpoint.value)" -ForegroundColor White
    Write-Host "Producer Managed Identity Client ID: $($outputs.producerIdentityClientId.value)" -ForegroundColor White
    Write-Host "Log Analytics Workspace: $($outputs.logAnalyticsWorkspaceId.value)" -ForegroundColor White
    
    Write-Host "`n🔐 Auth: Managed Identity / Entra ID (keyless — SAS/local auth disabled):" -ForegroundColor Yellow
    Write-Host "Assign these built-in roles to your managed identities (or pass them as deployment params):" -ForegroundColor Gray
    Write-Host "  - Sender (voice agent): 'Azure Event Hubs Data Sender'   on the Event Hub" -ForegroundColor Gray
    Write-Host "  - Listener (Fabric):    'Azure Event Hubs Data Receiver' on the Event Hub" -ForegroundColor Gray
    
    Write-Host "`n📝 Next Steps:" -ForegroundColor Cyan
    Write-Host "1. Configure Fabric Eventstream to consume from this Event Hub (Managed Identity / Entra ID)" -ForegroundColor White
    Write-Host "2. Set up Eventhouse (KQL Database) in Fabric" -ForegroundColor White
    Write-Host "3. Configure the voice agent to send telemetry using its Managed Identity (DefaultAzureCredential + namespace FQDN)" -ForegroundColor White
    Write-Host "4. See docs/event-hub-message-format.md for message schema" -ForegroundColor White
    
    # Save outputs to file
    $outputsFile = Join-Path $PSScriptRoot "deployment-outputs-$Environment.json"
    $outputs | ConvertTo-Json -Depth 10 | Out-File $outputsFile -Encoding utf8
    Write-Host "`n💾 Outputs saved to: $outputsFile" -ForegroundColor Green
}

Write-Host "`n✨ Done!" -ForegroundColor Cyan
