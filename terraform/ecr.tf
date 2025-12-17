# =============================================================================
# ECR Repositories
# =============================================================================

# -----------------------------------------------------------------------------
# Dummy API Repository
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "dummy_api" {
  name                 = "${local.name_prefix}-dummy-api"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${local.name_prefix}-dummy-api"
  }
}

resource "aws_ecr_lifecycle_policy" "dummy_api" {
  repository = aws_ecr_repository.dummy_api.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# OTEL Collector Repository
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "otel_collector" {
  name                 = "${local.name_prefix}-otel-collector"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${local.name_prefix}-otel-collector"
  }
}

resource "aws_ecr_lifecycle_policy" "otel_collector" {
  repository = aws_ecr_repository.otel_collector.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Downstream API Repository
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "downstream_api" {
  name                 = "${local.name_prefix}-downstream-api"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${local.name_prefix}-downstream-api"
  }
}

resource "aws_ecr_lifecycle_policy" "downstream_api" {
  repository = aws_ecr_repository.downstream_api.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

