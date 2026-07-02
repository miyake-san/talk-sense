# ============================================================================
# Terraform Variables - Development Environment
# ============================================================================

location                  = "eastus2"
environment              = "dev"
project_name             = "voiceagent"
eventhub_sku             = "Standard"
eventhub_capacity        = 1
message_retention_days   = 7
partition_count          = 4
auto_inflate_enabled     = false
maximum_throughput_units = 0

tags = {
  CostCenter = "Analytics"
  Owner      = "DataEngineering"
}
