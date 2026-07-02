#!/usr/bin/env pwsh
# ============================================================================
# Deploy Event Hubs Infrastructure for Voice Agent Analytics - Plan B
# ============================================================================

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment = 'dev',
    
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "rg-voiceagent-analytics-$Environment",
    
    [Parameter(Mandatory=$false)]
    [string]$Location = 'eastus2',
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

Write-Host "🚀 Deploying Voice Agent Analytics Infrastructure - Plan B" -ForegroundColor Cyan
Write-Host "Environment: $Environment" -ForegroundColor Yellow
Write-Host "Location: $Location" -ForegroundColor Yellow

# Set subscription if provided
if ($SubscriptionId) {
    Write-Host "Setting subscription: $SubscriptionId" -ForegroundColor Yellow
    az account set --subscription $SubscriptionId
}

# Get current subscription
$currentSub = az account show --query "{name:name, id:id}" -o json | ConvertFrom-Json
Write-Host "Using subscription: $($currentSub.name) ($($currentSub.id))" -ForegroundColor Green

# Create resource group if it doesn't exist
Write-Host "`n📦 Ensuring resource group exists: $ResourceGroupName" -ForegroundColor Cyan
az group create `
    --name $ResourceGroupName `
    --location $Location `
    --tags Project=VoiceAgentAnalytics Environment=$Environment ManagedBy=IaC-Bicep

# Deploy Bicep template
Write-Host "`n🏗️  Deploying Event Hubs infrastructure..." -ForegroundColor Cyan

$deploymentName = "voiceagent-planb-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$bicepFile = Join-Path $PSScriptRoot "main.bicep"
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
    'az', 'deployment', 'group', 'create'
    '--name', $deploymentName
    '--resource-group', $ResourceGroupName
    '--template-file', $bicepFile
)

if ($parametersFile) {
    $deployCmd += '--parameters', $parametersFile
}

if ($WhatIf) {
    $deployCmd += '--what-if'
    Write-Host "Running in WhatIf mode..." -ForegroundColor Yellow
}

Write-Host "Deployment command: $($deployCmd -join ' ')" -ForegroundColor Gray

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
    Write-Host "Kafka Endpoint: $($outputs.kafkaEndpoint.value)" -ForegroundColor White
    
    Write-Host "`n🔑 Connection Strings (SENSITIVE - Store securely):" -ForegroundColor Yellow
    Write-Host "Voice Agent (Send): $($outputs.voiceAgentConnectionString.value)" -ForegroundColor Gray
    Write-Host "Fabric Eventstream (Listen): $($outputs.fabricEventstreamConnectionString.value)" -ForegroundColor Gray
    
    Write-Host "`n📝 Next Steps:" -ForegroundColor Cyan
    Write-Host "1. Configure Fabric Eventstream to consume from this Event Hub" -ForegroundColor White
    Write-Host "2. Set up Eventhouse (KQL Database) in Fabric" -ForegroundColor White
    Write-Host "3. Configure the voice agent to send telemetry using the connection string" -ForegroundColor White
    Write-Host "4. See docs/event-hub-message-format.md for message schema" -ForegroundColor White
    
    # Save outputs to file
    $outputsFile = Join-Path $PSScriptRoot "deployment-outputs-$Environment.json"
    $outputs | ConvertTo-Json -Depth 10 | Out-File $outputsFile -Encoding utf8
    Write-Host "`n💾 Outputs saved to: $outputsFile" -ForegroundColor Green
}

Write-Host "`n✨ Done!" -ForegroundColor Cyan
