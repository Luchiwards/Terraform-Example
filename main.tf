# -------------------------------------------------------------------------------------------------
# Root configuration
# - Pins Terraform and AWS provider versions for reproducibility
# - Configures AWS provider to use region/profile from variables
# -------------------------------------------------------------------------------------------------
terraform {
  required_version = ">= 1.4"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.1"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

# ACM for CloudFront must be in us-east-1
provider "aws" {
  alias   = "us_east_1"
  region  = "us-east-1"
  profile = var.aws_profile
}
# -------------------------------------------------------------------------------------------------
# Identity and shared context
# - Caller identity is used in tags (Owner)
# - Common tags applied to most managed resources for traceability
# -------------------------------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = data.aws_caller_identity.current.account_id
  }
}

# -------------------------------------------------------------------------------------------------
# Network (VPC + subnets) 
# Using terraform-aws-modules/vpc to provision:
# - Private-only VPC (no Internet Gateway, no NAT)
# - Two subnet tiers across the specified AZs:
#   * private_subnets      → "private-app" tier where compute (ECS tasks, ALB) lives
#   * database_subnets     → "private-db" tier for RDS
# Relationships:
# - ALB and ECS services will attach to subnets in module.network.private_subnets
# - RDS will use the module-managed DB subnet group created from database_subnets
# - Security boundaries are expressed via subnet-level tags and security groups
# -------------------------------------------------------------------------------------------------
module "network" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8"

  name = "${var.project_name}-${var.environment}"
  cidr = var.vpc_cidr
  azs  = var.availability_zones

  # Subnet layout matching the architecture diagram
  private_subnets      = var.private_app_subnets
  database_subnets     = var.private_db_subnets

  enable_dns_hostnames = true
  enable_dns_support   = true

  # No public subnets per design; keep VPC private-only
  create_igw         = false
  enable_nat_gateway = false

  # Tag subnets by role so downstream services can target them
  private_subnet_tags = merge(local.common_tags, {
    Network = "private-app"
  })
  database_subnet_tags = merge(local.common_tags, {
    Network = "private-db"
  })

  tags = local.common_tags
}

