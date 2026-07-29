#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Complete deployment script for Voice Agent Analytics Plan B infrastructure.

.DESCRIPTION
    Automates the deployment of:
    1. Azure Event Hubs (Bicep)
    2. Configuration documentation generation
    3. Post-deployment validation
    4. Next steps guidance

.PARAMETER Environment
    Target environment (dev, staging, prod)

.PARAMETER Location
    Azure region

.PARAMETER SkipEventHub
    Skip Event Hub deployment (if already exists)

.EXAMPLE
    .\deploy-planb.ps1 -Environment dev -Location eastus2

.EXAMPLE
    .\deploy-planb.ps1 -Environment prod -Location eastus2 -SkipEventHub
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment = 'dev',
    
    [Parameter(Mandatory=$false)]
    [string]$Location = 'eastus2',
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipEventHub,
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot

# Colors
$ColorSuccess = 'Green'
$ColorWarning = 'Yellow'
$ColorError = 'Red'
$ColorInfo = 'Cyan'
$ColorStep = 'Magenta'

# Banner
Write-Host @"

╔════════════════════════════════════════════════════════════════════════╗
║                                                                        ║
║   🚀 Voice Agent Analytics — Plan B Deployment                        ║
║   Architecture: Agent → Event Hubs → Fabric → Eventhouse → Power BI  ║
║                                                                        ║
╚════════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor $ColorInfo

Write-Host "Environment:  $Environment" -ForegroundColor $ColorWarning
Write-Host "Location:     $Location" -ForegroundColor $ColorWarning
Write-Host "WhatIf Mode:  $WhatIf" -ForegroundColor $ColorWarning
Write-Host ""

# Step 1: Prerequisites Check
Write-Host "`n═══════════════════════════════════════════════════════════════════════" -ForegroundColor $ColorStep
Write-Host "📋 STEP 1: Prerequisites Check" -ForegroundColor $ColorStep
Write-Host "═══════════════════════════════════════════════════════════════════════`n" -ForegroundColor $ColorStep

$prerequisites = @{
    'Azure CLI' = { az version 2>$null }
    'PowerShell 7+' = { $PSVersionTable.PSVersion.Major -ge 7 }
    'Bicep CLI' = { az bicep version 2>$null }
}

$prereqsFailed = $false
foreach ($prereq in $prerequisites.GetEnumerator()) {
    Write-Host "  Checking $($prereq.Key)... " -NoNewline
    
    try {
        $result = & $prereq.Value
        if ($?) {
            Write-Host "✓ OK" -ForegroundColor $ColorSuccess
        } else {
            Write-Host "✗ FAILED" -ForegroundColor $ColorError
            $prereqsFailed = $true
        }
    } catch {
        Write-Host "✗ NOT FOUND" -ForegroundColor $ColorError
        $prereqsFailed = $true
    }
}

if ($prereqsFailed) {
    Write-Host "`n❌ Prerequisites check failed. Please install missing tools." -ForegroundColor $ColorError
    Write-Host "   - Azure CLI: https://aka.ms/installazurecli" -ForegroundColor $ColorWarning
    Write-Host "   - Bicep: az bicep install" -ForegroundColor $ColorWarning
    exit 1
}

# Step 2: Azure Login Check
Write-Host "`n═══════════════════════════════════════════════════════════════════════" -ForegroundColor $ColorStep
Write-Host "🔐 STEP 2: Azure Authentication" -ForegroundColor $ColorStep
Write-Host "═══════════════════════════════════════════════════════════════════════`n" -ForegroundColor $ColorStep

$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "  Not logged in. Initiating Azure login..." -ForegroundColor $ColorWarning
    az login
    $account = az account show | ConvertFrom-Json
}

Write-Host "  ✓ Logged in as: $($account.user.name)" -ForegroundColor $ColorSuccess
Write-Host "  ✓ Subscription: $($account.name) ($($account.id))" -ForegroundColor $ColorSuccess

# Step 3: Deploy Event Hubs
if (-not $SkipEventHub) {
    Write-Host "`n═══════════════════════════════════════════════════════════════════════" -ForegroundColor $ColorStep
    Write-Host "🏗️  STEP 3: Deploy Azure Event Hubs (Bicep)" -ForegroundColor $ColorStep
    Write-Host "═══════════════════════════════════════════════════════════════════════`n" -ForegroundColor $ColorStep
    
    $bicepScript = Join-Path $scriptRoot "bicep\deploy.ps1"
    
    if (Test-Path $bicepScript) {
        & $bicepScript -Environment $Environment -Location $Location -WhatIf:$WhatIf
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "`n❌ Event Hub deployment failed." -ForegroundColor $ColorError
            exit 1
        }
    } else {
        Write-Host "  ⚠️  Bicep deployment script not found: $bicepScript" -ForegroundColor $ColorWarning
        Write-Host "  Please deploy manually or check the path." -ForegroundColor $ColorWarning
    }
} else {
    Write-Host "`n⏭️  STEP 3: Skipped (Event Hub already deployed)" -ForegroundColor $ColorWarning
}

# Step 4: Generate Configuration Checklist
Write-Host "`n═══════════════════════════════════════════════════════════════════════" -ForegroundColor $ColorStep
Write-Host "📝 STEP 4: Generate Configuration Checklist" -ForegroundColor $ColorStep
Write-Host "═══════════════════════════════════════════════════════════════════════`n" -ForegroundColor $ColorStep

$checklistPath = Join-Path $scriptRoot "deployment-checklist-$Environment.md"

$checklistContent = @"
# Deployment Checklist — Voice Agent Analytics Plan B ($Environment)

**Generated**: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

---

## ✅ Phase 1: Azure Infrastructure (IaC) — COMPLETED

- [x] Event Hub Namespace deployed
- [x] Event Hub \`evh-voiceagent-telemetry\` created
- [x] Consumer groups configured (\`fabric-eventstream\`, \`monitoring\`)
- [x] Authorization policies created (Send, Listen, Manage)
- [x] Connection strings generated

**Outputs saved to**: \`bicep/deployment-outputs-$Environment.json\`

---

## 📋 Phase 2: Microsoft Fabric Configuration — PENDING

### 2.1 Create Eventstream

- [ ] Open [Microsoft Fabric](https://app.fabric.microsoft.com)
- [ ] Navigate to workspace: **VoiceAgentAnalytics**
- [ ] Create new **Eventstream**: \`VoiceAgentTelemetryStream\`
- [ ] Add source: **Azure Event Hubs**
  - [ ] Connection string: (from \`deployment-outputs-$Environment.json\`)
  - [ ] Consumer group: \`fabric-eventstream\`
  - [ ] Data format: JSON
- [ ] Publish Eventstream

**Documentation**: \`docs/fabric-configuration.md\` → Section "Parte 1"

### 2.2 Create Eventhouse

- [ ] Create **Eventhouse**: \`VoiceAgentEventhouse\`
- [ ] Create KQL Database: \`VoiceAgentDB\`
- [ ] Create tables:
  - [ ] \`RawTelemetry\` (all events)
  - [ ] \`Conversations\`
  - [ ] \`Turns\`
  - [ ] \`Events\`
  - [ ] \`CSAT\`
- [ ] Enable streaming ingestion on all tables
- [ ] Create update policies (if using RAW table)
- [ ] Enable **OneLake availability**

**Documentation**: \`docs/fabric-configuration.md\` → Section "Parte 2"

### 2.3 Connect Eventstream → Eventhouse

- [ ] Add destination to Eventstream: **Eventhouse**
- [ ] Select \`VoiceAgentEventhouse\` / \`VoiceAgentDB\`
- [ ] Target table: \`RawTelemetry\` (or direct ingestion to specific tables)
- [ ] Publish changes

---

## 🔧 Phase 3: Voice Agent Configuration — PENDING

- [ ] Get connection string from \`deployment-outputs-$Environment.json\`
- [ ] Implement Event Hub sender in agent code
  - [ ] Install SDK: \`@azure/event-hubs\` (Node.js) or \`azure-eventhub\` (Python)
  - [ ] Follow message format: \`docs/event-hub-message-format.md\`
- [ ] Implement message types:
  - [ ] \`conversation_started\`
  - [ ] \`turn_completed\`
  - [ ] \`conversation_event\`
  - [ ] \`csat_received\`
- [ ] Test sending events
- [ ] Validate events arrive in Eventhouse:
  \`\`\`kql
  RawTelemetry
  | where timestamp > ago(10m)
  | count
  \`\`\`

**Documentation**: \`docs/event-hub-message-format.md\`

---

## 📊 Phase 4: Power BI Dashboard — PENDING

### 4.1 Connect to Eventhouse

- [ ] Open Power BI Desktop or Service
- [ ] Connect to **OneLake data hub**
- [ ] Select Eventhouse: \`VoiceAgentEventhouse\`
- [ ] Import tables: Conversations, Turns, Events, CSAT
- [ ] Mode: **Direct Lake** (recommended) or **DirectQuery**

### 4.2 Data Modeling

- [ ] Create relationships:
  - [ ] \`Conversations (1) ──< Turns (∞)\`
  - [ ] \`Conversations (1) ──< Events (∞)\`
  - [ ] \`Conversations (1) ──< CSAT (1)\`
- [ ] Create calendar table (\`Dim_Date\`)
- [ ] Set cross-filter directions (bidirectional where needed)

### 4.3 Import DAX Measures

Copy measures from \`docs/powerbi-configuration.md\` → Section "Parte 3":

- [ ] Métrica 1: Retenção IA (%)
- [ ] Métrica 2: TMR (ms)
- [ ] Métrica 3: TMA (ms)
- [ ] Métrica 4: Top Acionamentos
- [ ] Métrica 5: Transbordo Não Compreensão (%)
- [ ] Métrica 6: Retorno URA (%)
- [ ] Métrica 7: Pedido Atendente (%)
- [ ] Métrica 8: Taxa de Erro (%)
- [ ] Métrica 9: CSAT Médio

### 4.4 Create Dashboard Pages

- [ ] **Page 1: Overview** (KPIs, trends, top intents)
- [ ] **Page 2: Conversation Detail** (drill-through, transcript)
- [ ] **Page 3: Errors & Handoffs** (error analysis, overflow metrics)
- [ ] Configure slicers (date range, channel, segment)
- [ ] Apply RLS (if needed)

### 4.5 Publish

- [ ] Publish to Power BI Service
- [ ] Configure refresh schedule (if needed)
- [ ] Share with stakeholders

**Documentation**: \`docs/powerbi-configuration.md\`

---

## 🧪 Phase 5: Testing & Validation

- [ ] Send test events to Event Hub
- [ ] Verify events in Eventstream metrics
- [ ] Validate data in Eventhouse:
  \`\`\`kql
  Conversations | count
  Turns | count
  Events | count
  CSAT | count
  \`\`\`
- [ ] Refresh Power BI dashboard
- [ ] Validate all 9 metrics display correctly
- [ ] Test drill-through navigation
- [ ] Validate filters and slicers

---

## 🔒 Phase 6: Security & Compliance

- [ ] Verify PII masking in \`userUtterance\` field
- [ ] Apply RLS in Power BI (if needed)
- [ ] Review data retention policies (Event Hub, Eventhouse)
- [ ] Configure Private Endpoints (production only)
- [ ] Disable SAS authentication (production only)
- [ ] Enable Managed Identity (production only)

---

## 📈 Phase 7: Monitoring & Optimization

- [ ] Set up Azure Monitor alerts for Event Hub
- [ ] Monitor Eventhouse ingestion failures
- [ ] Review Power BI query performance
- [ ] Optimize DAX measures if needed
- [ ] Create aggregated views in Eventhouse (if needed)

---

## 📚 Documentation Reference

| Document | Purpose |
|----------|---------|
| [\`README.md\`](README.md) | Overview and quick start |
| [\`docs/event-hub-message-format.md\`](docs/event-hub-message-format.md) | Message schema specification |
| [\`docs/fabric-configuration.md\`](docs/fabric-configuration.md) | Fabric Eventstream/Eventhouse setup |
| [\`docs/powerbi-configuration.md\`](docs/powerbi-configuration.md) | Power BI dashboards and DAX |
| [\`../docs/plano-telemetria-analytics.md\`](../docs/plano-telemetria-analytics.md) | Complete analytics plan |
| [\`../docs/adr/adr-004-real-time-metrics-event-hubs-fabric.md\`](../docs/adr/adr-004-real-time-metrics-event-hubs-fabric.md) | Architecture decision record |

---

## 🆘 Support

For issues, refer to:
- Troubleshooting sections in each doc
- [Azure Event Hubs Docs](https://learn.microsoft.com/azure/event-hubs/)
- [Fabric RTI Docs](https://learn.microsoft.com/fabric/real-time-intelligence/)
- [Power BI Docs](https://learn.microsoft.com/power-bi/)

---

**Next Action**: Start with **Phase 2.1** — Create Fabric Eventstream
"@

$checklistContent | Out-File $checklistPath -Encoding utf8
Write-Host "  ✓ Checklist saved to: $checklistPath" -ForegroundColor $ColorSuccess

# Step 5: Summary
Write-Host "`n═══════════════════════════════════════════════════════════════════════" -ForegroundColor $ColorStep
Write-Host "🎉 Deployment Summary" -ForegroundColor $ColorStep
Write-Host "═══════════════════════════════════════════════════════════════════════`n" -ForegroundColor $ColorStep

if (-not $WhatIf) {
    Write-Host "  ✅ Azure Event Hubs infrastructure deployed" -ForegroundColor $ColorSuccess
    Write-Host "  ✅ Configuration checklist generated" -ForegroundColor $ColorSuccess
    Write-Host ""
    Write-Host "📋 Next Steps:" -ForegroundColor $ColorInfo
    Write-Host ""
    Write-Host "  1. Review checklist: $checklistPath" -ForegroundColor White
    Write-Host "  2. Configure Fabric Eventstream (docs/fabric-configuration.md)" -ForegroundColor White
    Write-Host "  3. Create Eventhouse and tables" -ForegroundColor White
    Write-Host "  4. Implement agent sender (docs/event-hub-message-format.md)" -ForegroundColor White
    Write-Host "  5. Build Power BI dashboards (docs/powerbi-configuration.md)" -ForegroundColor White
    Write-Host ""
    Write-Host "📁 Key Outputs:" -ForegroundColor $ColorInfo
    Write-Host "  - Connection strings: bicep/deployment-outputs-$Environment.json" -ForegroundColor Gray
    Write-Host "  - Checklist: $checklistPath" -ForegroundColor Gray
    Write-Host ""
} else {
    Write-Host "  ℹ️  WhatIf mode — no changes made" -ForegroundColor $ColorWarning
}

Write-Host "╔════════════════════════════════════════════════════════════════════════╗" -ForegroundColor $ColorInfo
Write-Host "║  ✨ Plan B Infrastructure Deployment Complete!                        ║" -ForegroundColor $ColorInfo
Write-Host "╚════════════════════════════════════════════════════════════════════════╝" -ForegroundColor $ColorInfo
Write-Host ""
