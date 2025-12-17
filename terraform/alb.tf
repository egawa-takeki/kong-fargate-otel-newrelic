# =============================================================================
# Application Load Balancer
# =============================================================================

resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name = "${local.name_prefix}-alb"
  }
}

# -----------------------------------------------------------------------------
# Target Group for Kong Data Plane
# -----------------------------------------------------------------------------

resource "aws_lb_target_group" "kong" {
  name        = "${local.name_prefix}-kong-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/status"
    port                = "8100"
    protocol            = "HTTP"
    matcher             = "200"
  }

  tags = {
    Name = "${local.name_prefix}-kong-tg"
  }
}

# -----------------------------------------------------------------------------
# ALB Listener
# -----------------------------------------------------------------------------

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kong.arn
  }

  tags = {
    Name = "${local.name_prefix}-http-listener"
  }
}


