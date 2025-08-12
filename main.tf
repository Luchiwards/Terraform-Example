terraform {
  required_version = ">= 1.4"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.1"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

resource "aws_vpc" "main-vpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "development"
  }
}

resource "aws_subnet" "private-subnet-1" {
  vpc_id     = aws_vpc.main-vpc.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "dev-subnet-1"
    Network = "private"
  }
}

resource "aws_subnet" "private-subnet-2" {
  vpc_id     = aws_vpc.main-vpc.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "dev-subnet-2"
    Network = "private"
  }
}

# resource "<provider>_<resource_type>" "name" {
#     config options...
#     key = "value"
#     key2= "value2"
# }

