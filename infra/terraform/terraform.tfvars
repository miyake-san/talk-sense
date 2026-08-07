# ============================================================================
# Terraform Variables - Development Environment
# ============================================================================

location                 = "eastus2"
environment              = "dev"
project_name             = "voiceagent"
eventhub_sku             = "Standard"
eventhub_capacity        = 1
message_retention_days   = 7
partition_count          = 4
auto_inflate_enabled     = false
maximum_throughput_units = 0
log_retention_days       = 30

# Keyless auth (Managed Identity / Entra ID). The producer identity is created
# by Terraform. Set the Fabric workspace identity Object ID for receiver access.
listener_principal_id = ""                 # Fabric Eventstream MI -> Azure Event Hubs Data Receiver
admin_principal_id    = ""                 # optional admin identity -> Azure Event Hubs Data Owner
principal_type        = "ServicePrincipal" # applies only to admin_principal_id

tags = {
  CostCenter = "Analytics"
  Owner      = "DataEngineering"
}
