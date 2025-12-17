# =============================================================================
# Security Groups
# =============================================================================

# -----------------------------------------------------------------------------
# ALB Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Security group for ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-alb-sg"
  }
}

# -----------------------------------------------------------------------------
# Kong Data Plane Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "kong_dp" {
  name        = "${local.name_prefix}-kong-dp-sg"
  description = "Security group for Kong Data Plane"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Health check from ALB"
    from_port       = 8100
    to_port         = 8100
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-kong-dp-sg"
  }
}

# -----------------------------------------------------------------------------
# Dummy API Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "dummy_api" {
  name        = "${local.name_prefix}-dummy-api-sg"
  description = "Security group for Dummy API"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from Kong DP"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.kong_dp.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-dummy-api-sg"
  }
}

# -----------------------------------------------------------------------------
# Downstream API Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "downstream_api" {
  name        = "${local.name_prefix}-downstream-api-sg"
  description = "Security group for Downstream API"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from Dummy API"
    from_port       = 3001
    to_port         = 3001
    protocol        = "tcp"
    security_groups = [aws_security_group.dummy_api.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-downstream-api-sg"
  }
}

