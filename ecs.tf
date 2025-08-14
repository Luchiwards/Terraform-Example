// ---------------------------------------------------------------------------------------
// ECS (Fargate) compute layer
// - Cluster in private app subnets
// - Two services: user management and radio locator
// - Each service registers targets in ALB target groups defined in alb.tf
// - Uses CloudWatch Logs; adds VPC endpoints for private-only operation
// ---------------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}/${var.environment}"
  retention_in_days = 30
}

resource "aws_ecs_cluster" "this" {
  name = "${var.project_name}-${var.environment}"
}

// Task execution role (pull from ECR, write logs)
data "aws_iam_policy_document" "ecs_task_execution_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${var.project_name}-${var.environment}-ecs-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_assume.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

// Task role for application containers (extend with app permissions later)
resource "aws_iam_role" "ecs_task" {
  name               = "${var.project_name}-${var.environment}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_assume.json
}

// Security group for ECS tasks: allow traffic from ALB to container port
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.project_name}-${var.environment}-ecs-tasks-sg"
  description = "Allow ALB to reach ECS tasks"
  vpc_id      = module.network.vpc_id

  ingress {
    description = "From internal ALB"
    from_port   = var.container_port
    to_port     = var.container_port
    protocol    = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

// Security group for Interface VPC Endpoints (accept HTTPS from ECS tasks)
resource "aws_security_group" "vpce" {
  name        = "${var.project_name}-${var.environment}-vpce-sg"
  description = "Allow HTTPS from ECS tasks to interface endpoints"
  vpc_id      = module.network.vpc_id

  ingress {
    description     = "HTTPS from ECS tasks"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
// ----------------------------
// Task definitions
// ----------------------------

locals {
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.ecs.name
      awslogs-region        = var.aws_region
      awslogs-stream-prefix = "ecs"
    }
  }
}

resource "aws_ecs_task_definition" "user" {
  family                   = "${var.project_name}-${var.environment}-user"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_cpu
  memory                   = var.ecs_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name             = "user"
      image            = var.user_service_image
      essential        = true
      portMappings     = [{ containerPort = var.container_port, hostPort = var.container_port, protocol = "tcp" }]
      logConfiguration = local.log_configuration
    }
  ])
}

resource "aws_ecs_task_definition" "radio" {
  family                   = "${var.project_name}-${var.environment}-radio"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_cpu
  memory                   = var.ecs_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name             = "radio"
      image            = var.radio_service_image
      essential        = true
      portMappings     = [{ containerPort = var.container_port, hostPort = var.container_port, protocol = "tcp" }]
      logConfiguration = local.log_configuration
    }
  ])
}

// ----------------------------
// Services
// ----------------------------

resource "aws_ecs_service" "user" {
  name            = "${var.project_name}-${var.environment}-user"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.user.arn
  desired_count   = var.ecs_desired_count
  launch_type     = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets         = module.network.private_subnets
    security_groups = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tg_user_mgmt.arn
    container_name   = "user"
    container_port   = var.container_port
  }

  lifecycle {
    ignore_changes = [task_definition]
  }
}

resource "aws_ecs_service" "radio" {
  name            = "${var.project_name}-${var.environment}-radio"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.radio.arn
  desired_count   = var.ecs_desired_count
  launch_type     = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets         = module.network.private_subnets
    security_groups = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tg_radio.arn
    container_name   = "radio"
    container_port   = var.container_port
  }

  lifecycle {
    ignore_changes = [task_definition]
  }
}

// ----------------------------
// VPC Endpoints to support private-only operation
// - ECR (API + DKR), CloudWatch Logs, S3 gateway endpoint
// ----------------------------

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id            = module.network.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type = "Interface"
  subnet_ids          = module.network.private_subnets
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id            = module.network.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type = "Interface"
  subnet_ids          = module.network.private_subnets
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id            = module.network.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type = "Interface"
  subnet_ids          = module.network.private_subnets
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = module.network.vpc_id
  service_name = "com.amazonaws.${var.aws_region}.s3"
  route_table_ids = module.network.private_route_table_ids
}

# Additional VPC interface endpoints for private-only operation
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = module.network.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.network.private_subnets
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "kms" {
  vpc_id              = module.network.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.kms"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.network.private_subnets
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "sts" {
  vpc_id              = module.network.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.network.private_subnets
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true
}


