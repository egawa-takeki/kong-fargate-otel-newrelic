# =============================================================================
# ECS Cluster
# =============================================================================

resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${local.name_prefix}-cluster"
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# =============================================================================
# CloudWatch Log Groups
# =============================================================================

resource "aws_cloudwatch_log_group" "kong" {
  name              = "/ecs/${local.name_prefix}/kong"
  retention_in_days = 7

  tags = {
    Name = "${local.name_prefix}-kong-logs"
  }
}

resource "aws_cloudwatch_log_group" "dummy_api" {
  name              = "/ecs/${local.name_prefix}/dummy-api"
  retention_in_days = 7

  tags = {
    Name = "${local.name_prefix}-dummy-api-logs"
  }
}

resource "aws_cloudwatch_log_group" "otel_collector" {
  name              = "/ecs/${local.name_prefix}/otel-collector"
  retention_in_days = 7

  tags = {
    Name = "${local.name_prefix}-otel-collector-logs"
  }
}

resource "aws_cloudwatch_log_group" "downstream_api" {
  name              = "/ecs/${local.name_prefix}/downstream-api"
  retention_in_days = 7

  tags = {
    Name = "${local.name_prefix}-downstream-api-logs"
  }
}

# =============================================================================
# Kong Data Plane Task Definition
# =============================================================================

resource "aws_ecs_task_definition" "kong" {
  family                   = "${local.name_prefix}-kong"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.kong_task_cpu
  memory                   = var.kong_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "kong"
      image     = "kong/kong-gateway:3.12"
      essential = true

      portMappings = [
        {
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
        },
        {
          containerPort = 8100
          hostPort      = 8100
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "KONG_ROLE", value = "data_plane" },
        { name = "KONG_DATABASE", value = "off" },
        { name = "KONG_CLUSTER_MTLS", value = "pki" },
        { name = "KONG_CLUSTER_CONTROL_PLANE", value = var.kong_cluster_endpoint },
        { name = "KONG_CLUSTER_SERVER_NAME", value = local.kong_cluster_server_name },
        { name = "KONG_CLUSTER_TELEMETRY_ENDPOINT", value = var.kong_telemetry_endpoint },
        { name = "KONG_CLUSTER_TELEMETRY_SERVER_NAME", value = local.kong_telemetry_server_name },
        { name = "KONG_CLUSTER_CERT", value = var.kong_cluster_cert },
        { name = "KONG_CLUSTER_CERT_KEY", value = var.kong_cluster_cert_key },
        { name = "KONG_LUA_SSL_TRUSTED_CERTIFICATE", value = "system" },
        { name = "KONG_KONNECT_MODE", value = "on" },
        { name = "KONG_VITALS", value = "off" },
        { name = "KONG_PROXY_LISTEN", value = "0.0.0.0:8000" },
        { name = "KONG_STATUS_LISTEN", value = "0.0.0.0:8100" },
        { name = "KONG_TRACING_INSTRUMENTATIONS", value = "all" },
        { name = "KONG_TRACING_SAMPLING_RATE", value = "1.0" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.kong.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "kong"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "kong health"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    },
    {
      name      = "otel-collector"
      image     = "${aws_ecr_repository.otel_collector.repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = 4318
          hostPort      = 4318
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "NEW_RELIC_LICENSE_KEY", value = var.new_relic_license_key }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.otel_collector.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "kong-otel"
        }
      }
    }
  ])

  tags = {
    Name = "${local.name_prefix}-kong-task"
  }
}

# =============================================================================
# Kong Data Plane Service
# =============================================================================

resource "aws_ecs_service" "kong" {
  name                   = "${local.name_prefix}-kong"
  cluster                = aws_ecs_cluster.main.id
  task_definition        = aws_ecs_task_definition.kong.arn
  desired_count          = var.kong_desired_count
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.kong_dp.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.kong.arn
    container_name   = "kong"
    container_port   = 8000
  }

  service_registries {
    registry_arn = aws_service_discovery_service.kong.arn
  }

  depends_on = [aws_lb_listener.http]

  tags = {
    Name = "${local.name_prefix}-kong-service"
  }
}

# =============================================================================
# Dummy API Task Definition
# =============================================================================

resource "aws_ecs_task_definition" "dummy_api" {
  family                   = "${local.name_prefix}-dummy-api"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.api_task_cpu
  memory                   = var.api_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "dummy-api"
      image     = "${aws_ecr_repository.dummy_api.repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "PORT", value = "3000" },
        { name = "OTEL_EXPORTER_OTLP_ENDPOINT", value = "http://localhost:4318" },
        { name = "OTEL_SERVICE_NAME", value = "dummy-api" },
        { name = "OTEL_TRACES_EXPORTER", value = "otlp" },
        { name = "NODE_ENV", value = "production" },
        { name = "DOWNSTREAM_API_URL", value = "http://downstream-api.${local.name_prefix}.local:3001" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.dummy_api.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "dummy-api"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "wget -q --spider http://localhost:3000/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
    },
    {
      name      = "otel-collector"
      image     = "${aws_ecr_repository.otel_collector.repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = 4318
          hostPort      = 4318
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "NEW_RELIC_LICENSE_KEY", value = var.new_relic_license_key }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.otel_collector.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "api-otel"
        }
      }
    }
  ])

  tags = {
    Name = "${local.name_prefix}-dummy-api-task"
  }
}

# =============================================================================
# Dummy API Service
# =============================================================================

resource "aws_ecs_service" "dummy_api" {
  name                   = "${local.name_prefix}-dummy-api"
  cluster                = aws_ecs_cluster.main.id
  task_definition        = aws_ecs_task_definition.dummy_api.arn
  desired_count          = var.dummy_api_desired_count
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.dummy_api.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.dummy_api.arn
  }

  tags = {
    Name = "${local.name_prefix}-dummy-api-service"
  }
}

# =============================================================================
# Service Discovery (Cloud Map)
# =============================================================================

resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = "${local.name_prefix}.local"
  description = "Private DNS namespace for ${local.name_prefix}"
  vpc         = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-namespace"
  }
}

resource "aws_service_discovery_service" "kong" {
  name = "kong"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = {
    Name = "${local.name_prefix}-kong-discovery"
  }
}

resource "aws_service_discovery_service" "dummy_api" {
  name = "dummy-api"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = {
    Name = "${local.name_prefix}-dummy-api-discovery"
  }
}

# =============================================================================
# Downstream API Task Definition
# =============================================================================

resource "aws_ecs_task_definition" "downstream_api" {
  family                   = "${local.name_prefix}-downstream-api"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.api_task_cpu
  memory                   = var.api_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "downstream-api"
      image     = "${aws_ecr_repository.downstream_api.repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = 3001
          hostPort      = 3001
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "PORT", value = "3001" },
        { name = "OTEL_EXPORTER_OTLP_ENDPOINT", value = "http://localhost:4318" },
        { name = "OTEL_SERVICE_NAME", value = "downstream-api" },
        { name = "OTEL_TRACES_EXPORTER", value = "otlp" },
        { name = "NODE_ENV", value = "production" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.downstream_api.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "downstream-api"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "wget -q --spider http://localhost:3001/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
    },
    {
      name      = "otel-collector"
      image     = "${aws_ecr_repository.otel_collector.repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = 4318
          hostPort      = 4318
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "NEW_RELIC_LICENSE_KEY", value = var.new_relic_license_key }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.otel_collector.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "downstream-otel"
        }
      }
    }
  ])

  tags = {
    Name = "${local.name_prefix}-downstream-api-task"
  }
}

# =============================================================================
# Downstream API Service
# =============================================================================

resource "aws_ecs_service" "downstream_api" {
  name                   = "${local.name_prefix}-downstream-api"
  cluster                = aws_ecs_cluster.main.id
  task_definition        = aws_ecs_task_definition.downstream_api.arn
  desired_count          = var.downstream_api_desired_count
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.downstream_api.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.downstream_api.arn
  }

  tags = {
    Name = "${local.name_prefix}-downstream-api-service"
  }
}

resource "aws_service_discovery_service" "downstream_api" {
  name = "downstream-api"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = {
    Name = "${local.name_prefix}-downstream-api-discovery"
  }
}

