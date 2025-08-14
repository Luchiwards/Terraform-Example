// ---------------------------------------------------------------------------------------
// Data layer: RDS PostgreSQL (user mgmt, radio mgmt) and ElastiCache Redis
// - DB subnet group is provided by VPC module; SGs allow ingress from ECS tasks SG
// - Secrets Manager stores DB passwords
// - Redis subnet group lives in private-app subnets; SG allows from ECS tasks SG
// ---------------------------------------------------------------------------------------

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-${var.environment}-rds-sg"
  description = "Allow PostgreSQL from ECS tasks"
  vpc_id      = module.network.vpc_id

  ingress {
    description     = "PostgreSQL from ECS tasks"
    from_port       = 5432
    to_port         = 5432
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

resource "aws_secretsmanager_secret" "db_user" {
  name = "${var.project_name}/${var.environment}/db/user/password"
}

resource "aws_secretsmanager_secret_version" "db_user" {
  secret_id     = aws_secretsmanager_secret.db_user.id
  secret_string = random_password.db_user.result
}

resource "aws_secretsmanager_secret" "db_radio" {
  name = "${var.project_name}/${var.environment}/db/radio/password"
}

resource "aws_secretsmanager_secret_version" "db_radio" {
  secret_id     = aws_secretsmanager_secret.db_radio.id
  secret_string = random_password.db_radio.result
}

resource "random_password" "db_user" {
  length  = 20
  special = true
}

resource "random_password" "db_radio" {
  length  = 20
  special = true
}

resource "aws_db_instance" "user" {
  identifier              = "${var.project_name}-${var.environment}-user"
  engine                  = "postgres"
  engine_version          = var.db_engine_version
  instance_class          = var.db_instance_class
  allocated_storage       = var.db_allocated_storage
  username                = var.db_username
  password                = random_password.db_user.result
  db_subnet_group_name    = module.network.database_subnet_group
  vpc_security_group_ids  = [aws_security_group.rds.id]
  multi_az                = var.db_multi_az
  storage_encrypted       = var.db_storage_encrypted
  backup_retention_period = var.db_backup_retention
  skip_final_snapshot     = true
  deletion_protection     = false

  tags = {
    Name        = "${var.project_name}-${var.environment}-user-db"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_db_instance" "radio" {
  identifier              = "${var.project_name}-${var.environment}-radio"
  engine                  = "postgres"
  engine_version          = var.db_engine_version
  instance_class          = var.db_instance_class
  allocated_storage       = var.db_allocated_storage
  username                = var.db_username
  password                = random_password.db_radio.result
  db_subnet_group_name    = module.network.database_subnet_group
  vpc_security_group_ids  = [aws_security_group.rds.id]
  multi_az                = var.db_multi_az
  storage_encrypted       = var.db_storage_encrypted
  backup_retention_period = var.db_backup_retention
  skip_final_snapshot     = true
  deletion_protection     = false

  tags = {
    Name        = "${var.project_name}-${var.environment}-radio-db"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

// Redis (ElastiCache) in private app subnets
resource "aws_security_group" "redis" {
  name        = "${var.project_name}-${var.environment}-redis-sg"
  description = "Allow Redis from ECS tasks"
  vpc_id      = module.network.vpc_id

  ingress {
    description     = "Redis from ECS tasks"
    from_port       = 6379
    to_port         = 6379
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

resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.project_name}-${var.environment}-redis"
  subnet_ids = module.network.private_subnets
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id          = "${var.project_name}-${var.environment}-redis"
  description                   = "Redis for session/cache"
  engine                        = "redis"
  engine_version                = var.redis_engine_version
  node_type                     = var.redis_node_type
  num_node_groups               = 1
  replicas_per_node_group       = 1
  automatic_failover_enabled    = true
  transit_encryption_enabled    = true
  at_rest_encryption_enabled    = true
  subnet_group_name             = aws_elasticache_subnet_group.redis.name
  security_group_ids            = [aws_security_group.redis.id]
  port                          = 6379

  tags = {
    Name        = "${var.project_name}-${var.environment}-redis"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}


