# =============================================================================
# General
# =============================================================================

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "kong-otel-newrelic"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

# =============================================================================
# VPC
# =============================================================================

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["ap-northeast-1a", "ap-northeast-1c"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

# =============================================================================
# Kong Konnect
# =============================================================================

variable "kong_cluster_endpoint" {
  description = "Kong Konnect cluster endpoint (e.g., xxx.us.cp0.konghq.com)"
  type        = string
  sensitive   = true
}

variable "kong_telemetry_endpoint" {
  description = "Kong Konnect telemetry endpoint (e.g., xxx.us.tp0.konghq.com)"
  type        = string
  sensitive   = true
}

variable "kong_cluster_cert" {
  description = "Kong Konnect cluster certificate (PEM format)"
  type        = string
  sensitive   = true
}

variable "kong_cluster_cert_key" {
  description = "Kong Konnect cluster certificate key (PEM format)"
  type        = string
  sensitive   = true
}

# =============================================================================
# ECS
# =============================================================================

variable "kong_cpu" {
  description = "CPU units for Kong container (1024 = 1 vCPU)"
  type        = number
  default     = 256
}

variable "kong_memory" {
  description = "Memory for Kong container in MB"
  type        = number
  default     = 512
}

variable "dummy_api_cpu" {
  description = "CPU units for Dummy API container"
  type        = number
  default     = 256
}

variable "dummy_api_memory" {
  description = "Memory for Dummy API container in MB"
  type        = number
  default     = 512
}

variable "otel_collector_cpu" {
  description = "CPU units for OTEL Collector sidecar"
  type        = number
  default     = 256
}

variable "otel_collector_memory" {
  description = "Memory for OTEL Collector sidecar in MB"
  type        = number
  default     = 512
}

# Fargate task-level CPU/Memory (must be valid Fargate combinations)
variable "kong_task_cpu" {
  description = "CPU units for Kong Fargate task (valid: 256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 512
}

variable "kong_task_memory" {
  description = "Memory for Kong Fargate task in MB (must match CPU, see AWS docs)"
  type        = number
  default     = 1024
}

variable "api_task_cpu" {
  description = "CPU units for API Fargate tasks (valid: 256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 512
}

variable "api_task_memory" {
  description = "Memory for API Fargate tasks in MB"
  type        = number
  default     = 1024
}

variable "kong_desired_count" {
  description = "Desired number of Kong tasks"
  type        = number
  default     = 1
}

variable "dummy_api_desired_count" {
  description = "Desired number of Dummy API tasks"
  type        = number
  default     = 1
}

variable "downstream_api_cpu" {
  description = "CPU units for Downstream API container"
  type        = number
  default     = 256
}

variable "downstream_api_memory" {
  description = "Memory for Downstream API container in MB"
  type        = number
  default     = 512
}

variable "downstream_api_desired_count" {
  description = "Desired number of Downstream API tasks"
  type        = number
  default     = 1
}

# =============================================================================
# New Relic
# =============================================================================

variable "new_relic_license_key" {
  description = "New Relic Ingest License Key for OTLP export"
  type        = string
  sensitive   = true
}

