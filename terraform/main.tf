# =============================================================================
# Kong Gateway + New Relic Distributed Tracing Infrastructure
# =============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # Extract hostname without port for SERVER_NAME settings
  kong_cluster_server_name   = split(":", var.kong_cluster_endpoint)[0]
  kong_telemetry_server_name = split(":", var.kong_telemetry_endpoint)[0]
}

# Data sources
data "aws_caller_identity" "current" {}

