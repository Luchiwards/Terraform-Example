// ---------------------------------------------------------------------------------------
// Internal Application Load Balancer layer
// - Lives in `module.network.private_subnets` (private-app tier)
// - Receives HTTP from inside the VPC (e.g., API Gateway private integration,
//   CloudFront to ALB via PrivateLink, or service-to-service traffic)
// - Exposes two target groups for separate services and uses path-based routing
//   to direct requests
// Relationships:
// - Security group restricts inbound to VPC CIDR only
// - Target groups will later be registered by ECS services (target_type = "ip")
// ---------------------------------------------------------------------------------------
locals {
  alb_name = "${var.project_name}-${var.environment}-internal-alb"
}

resource "aws_security_group" "alb_sg" {
  # Attached to the ALB; controls who can reach listener ports
  name        = "${local.alb_name}-sg"
  description = "Allow HTTP from API Gateway VPC Link to internal ALB"
  vpc_id      = module.network.vpc_id

  ingress {
    description = "HTTP from API Gateway VPC Link ENIs"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "HTTPS from API Gateway VPC Link ENIs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    # Allow the ALB to reach registered targets (within subnets)
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${local.alb_name}-sg"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_lb" "internal_alb" {
  # Deployed into private application subnets, not internet-facing
  name               = local.alb_name
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = module.network.private_subnets

  enable_deletion_protection = false
  idle_timeout               = 60

  tags = {
    Name        = local.alb_name
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_lb_target_group" "tg_user_mgmt" {
  # Target group for the user management backend service
  name        = "${var.project_name}-${var.environment}-tg-user"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = module.network.vpc_id

  health_check {
    enabled             = true
    path                = "/health"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-tg-user"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_lb_target_group" "tg_radio" {
  # Target group for the radio locator backend service
  name        = "${var.project_name}-${var.environment}-tg-radio"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = module.network.vpc_id

  health_check {
    enabled             = true
    path                = "/health"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-tg-radio"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_lb_listener" "http" {
  # HTTP listener routes to user management by default
  load_balancer_arn = aws_lb.internal_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_user_mgmt.arn
  }
}

resource "aws_lb_listener_rule" "route_radio" {
  # Path-based rule sends `/radio/*` traffic to the radio service
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_radio.arn
  }

  condition {
    path_pattern {
      values = ["/radio/*"]
    }
  }
}


