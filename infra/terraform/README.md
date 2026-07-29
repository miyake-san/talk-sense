# Voice Agent Analytics - Plan B Infrastructure (Terraform)

This directory contains Terraform configuration to deploy the **Plan B** architecture for Voice Agent Analytics:

```
Agent → Event Hubs → Fabric Eventstream → Eventhouse → Power BI
```

## Architecture

Based on [ADR-004](../../docs/adr/adr-004-real-time-metrics-event-hubs-fabric.md), this infrastructure implements the Fabric Real-Time Intelligence (RTI) ingestion pattern.

### Components Deployed

1. **Azure Event Hubs Namespace** - Message ingestion layer
2. **Event Hub (evh-voiceagent-telemetry)** - Telemetry stream
3. **Consumer Groups** - fabric-eventstream, monitoring
4. **Authorization Rules** - Send-only, Listen-only, Manage policies

### Not Included (Manual Configuration Required)

- Microsoft Fabric Workspace
- Fabric Eventstream configuration
- Eventhouse (KQL Database) setup
- Power BI reports

## Prerequisites

- Azure CLI installed and authenticated
- Terraform >= 1.5.0
- Appropriate Azure subscription permissions (Contributor or Owner)

## Quick Start

### 1. Initialize Terraform

```bash
cd infra/terraform
terraform init
```

### 2. Review the Plan

```bash
terraform plan
```

### 3. Deploy

```bash
terraform apply
```

### 4. View Outputs

```bash
# Show all outputs
terraform output

# Show specific sensitive output
terraform output -raw voice_agent_connection_string
terraform output -raw fabric_eventstream_connection_string
```

## Configuration

Edit `terraform.tfvars` to customize the deployment:

```hcl
location                  = "eastus2"
environment              = "dev"
project_name             = "voiceagent"
eventhub_sku             = "Standard"  # Basic, Standard, or Premium
eventhub_capacity        = 1           # Throughput Units (1-20)
message_retention_days   = 7           # 1-7 days
partition_count          = 4           # 2-32 partitions
auto_inflate_enabled     = false
maximum_throughput_units = 0
```

## Outputs

After deployment, the following outputs are available:

| Output | Description | Sensitive |
|--------|-------------|-----------|
| `resource_group_name` | Resource group name | No |
| `eventhub_namespace_name` | Event Hub namespace | No |
| `eventhub_name` | Event Hub name | No |
| `kafka_endpoint` | Kafka endpoint | No |
| `voice_agent_connection_string` | Agent send connection string | Yes |
| `fabric_eventstream_connection_string` | Fabric listen connection string | Yes |
| `consumer_groups` | List of consumer groups | No |
| `deployment_info` | Full deployment details | No |

## Post-Deployment Steps

After Terraform completes:

### 1. Configure Fabric Eventstream

1. Navigate to your Microsoft Fabric workspace
2. Create a new **Eventstream**
3. Add source: **Azure Event Hubs**
   - Use `fabric_eventstream_connection_string` output
   - Select consumer group: `fabric-eventstream`
4. Add destination: **Eventhouse** (create if needed)

### 2. Configure Eventhouse

1. Create or select an Eventhouse
2. Create a KQL Database
3. Define tables following the schema in `../docs/event-hub-message-format.md`
4. Enable OneLake availability for Power BI Direct Lake

### 3. Configure Voice Agent

1. Get the connection string:
   ```bash
   terraform output -raw voice_agent_connection_string
   ```
2. Configure agent to send events to Event Hub
3. Follow message format in `../docs/event-hub-message-format.md`

### 4. Configure Power BI

1. Connect to Eventhouse via DirectQuery/KQL or Direct Lake
2. Import DAX measures from `../../docs/powerbi-prompts.md`
3. Build dashboards following `../../docs/plano-telemetria-analytics.md`

## Security Considerations

### For POC/Development

- SAS authentication enabled (`local_auth_enabled = true`)
- Public network access enabled
- Standard SKU for cost optimization

### For Production

Update the following:

```hcl
# In main.tf, update these properties:
local_auth_enabled            = false  # Use Managed Identity
public_network_access_enabled = false  # Require Private Endpoint
zone_redundant                = true   # Enable zone redundancy
eventhub_sku                  = "Premium"  # For Private Endpoint support

# Add Private Endpoint configuration
# Add Log Analytics workspace for diagnostics
# Implement Key Vault for secrets
# Configure Network Security Group rules
```

## Cost Estimation

### Development (Standard SKU, 1 TU)

- Event Hub Namespace: ~$25/month
- Event Hub: Included
- Ingress: $0.028/million events
- Storage: ~$0.10/GB/month (7-day retention)

**Estimated total**: $30-50/month for moderate traffic

### Production (Premium SKU, zone-redundant)

- Event Hub Namespace (Premium): ~$670/month per Processing Unit
- Additional costs for Private Endpoint, monitoring

**Estimated total**: $700-1000/month

> Use [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/) for precise estimates.

## Troubleshooting

### Authentication Errors

```bash
# Login to Azure
az login

# Set subscription
az account set --subscription "Your-Subscription-ID"

# Verify credentials
az account show
```

### State Management

```bash
# View state
terraform show

# Refresh state
terraform refresh

# Import existing resource
terraform import azurerm_eventhub_namespace.main /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.EventHub/namespaces/{name}
```

### Clean Up

```bash
# Destroy all resources
terraform destroy

# Destroy specific resource
terraform destroy -target=azurerm_eventhub.telemetry
```

## Related Documentation

- [Main Telemetry Plan](../../docs/plano-telemetria-analytics.md)
- [Architecture Decision Records](../../docs/adr/README.md)
- [ADR-004: Event Hubs and Fabric Metrics](../../docs/adr/adr-004-real-time-metrics-event-hubs-fabric.md)
- [Event Hub Message Format](../docs/event-hub-message-format.md)
- [Power BI Configuration](../../docs/powerbi-prompts.md)

## Support

For issues or questions:

1. Review [Azure Event Hubs documentation](https://docs.microsoft.com/azure/event-hubs/)
2. Check [Fabric Real-Time Intelligence docs](https://learn.microsoft.com/fabric/real-time-intelligence/)
3. Consult [Terraform Azure Provider docs](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
