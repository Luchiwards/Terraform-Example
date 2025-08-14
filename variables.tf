variable "aws_region" {
  description = "AWS region to deploy resources to"
  type        = string
  default     = "ap-southeast-2"
}

variable "aws_profile" {
  description = "Named AWS CLI profile to use for credentials (from ~/.aws/config). Leave empty to use default credential search chain."
  type        = string
  default     = "default"
}

variable "project_name" {
  description = "Project name used for resource naming and tags"
  type        = string
  default     = "my-project"
}

variable "environment" {
  description = "Deployment environment name"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_app_subnets" {
  description = "List of CIDRs for private application subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "private_db_subnets" {
  description = "List of CIDRs for private database subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}

variable "single_nat_gateway" {
  description = "Deprecated in private-only design; kept for compatibility"
  type        = bool
  default     = false
}

variable "availability_zones" {
  description = "List of availability zones to use (must match the number of subnets per tier)"
  type        = list(string)
  # Provide explicit AZs to avoid requiring DescribeAvailabilityZones permissions
  default     = ["ap-southeast-2a", "ap-southeast-2b"]
}

variable "ecs_desired_count" {
  description = "Desired number of tasks for each ECS service"
  type        = number
  default     = 2
}

variable "ecs_cpu" {
  description = "Fargate task CPU units (e.g., 256, 512, 1024)"
  type        = number
  default     = 512
}

variable "ecs_memory" {
  description = "Fargate task memory in MiB (e.g., 1024, 2048)"
  type        = number
  default     = 1024
}

variable "user_service_image" {
  description = "Container image for the user management service (ECR URI)"
  type        = string
  default     = "<account-id>.dkr.ecr.ap-southeast-2.amazonaws.com/user-mgmt:latest"
}

variable "radio_service_image" {
  description = "Container image for the radio locator service (ECR URI)"
  type        = string
  default     = "<account-id>.dkr.ecr.ap-southeast-2.amazonaws.com/radio-locator:latest"
}

variable "container_port" {
  description = "Container port exposed by services"
  type        = number
  default     = 80
}

# ----------------------------
# RDS configuration
# ----------------------------
variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16.3"
}

variable "db_allocated_storage" {
  description = "Allocated storage for RDS (GB)"
  type        = number
  default     = 20
}

variable "db_multi_az" {
  description = "Whether to enable Multi-AZ for RDS"
  type        = bool
  default     = true
}

variable "db_backup_retention" {
  description = "Backup retention in days"
  type        = number
  default     = 7
}

variable "db_storage_encrypted" {
  description = "Encrypt RDS storage"
  type        = bool
  default     = true
}

variable "db_username" {
  description = "Master username for RDS"
  type        = string
  default     = "appadmin"
}

# ----------------------------
# ElastiCache configuration
# ----------------------------
variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t4g.small"
}

variable "redis_engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.1"
}

// ----------------------------
// Cognito configuration
// ----------------------------
variable "cognito_domain_prefix" {
  description = "Cognito hosted UI domain prefix (globally unique in the region)"
  type        = string
  default     = "my-project-dev-auth"
}

variable "cognito_callback_urls" {
  description = "Allowed OAuth2 callback URLs"
  type        = list(string)
  default     = ["https://example.com/callback"]
}

variable "cognito_logout_urls" {
  description = "Allowed OAuth2 logout URLs"
  type        = list(string)
  default     = ["https://example.com/logout"]
}

// ----------------------------
// API Gateway configuration
// ----------------------------
variable "admin_api_domain_name" {
  description = "Optional custom domain for the Admin API"
  type        = string
  default     = null
}

variable "client_api_domain_name" {
  description = "Optional custom domain for the Client API"
  type        = string
  default     = null
}

variable "ws_api_domain_name" {
  description = "Optional custom domain for the WebSocket API"
  type        = string
  default     = null
}

// ----------------------------
// Lambda/WebSocket configuration
// ----------------------------
variable "lambda_runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "python3.12"
}

// ----------------------------
// DNS and CDN
// ----------------------------
variable "root_domain_name" {
  description = "Root domain managed in Route53 (e.g., example.com)"
  type        = string
  default     = null
}

variable "cloudfront_domain" {
  description = "Optional custom domain for CloudFront (CNAME under root domain)"
  type        = string
  default     = null
}

variable "internal_alb_domain_name" {
  description = "Optional FQDN for internal ALB TLS (e.g., alb.internal.example.com). Must be under root_domain_name."
  type        = string
  default     = null
}

