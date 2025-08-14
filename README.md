## Terraform foundation (network layer)

This sets up the base AWS networking to match the high‑level architecture (private‑only VPC, private app subnets, private DB subnets; no internet gateway/NAT). It demonstrates best practices for:
- **Provider and CLI version pinning** for reproducible runs
- **Secure credential setup** using a named AWS CLI profile
- **Variable-driven configuration** via `variables.tf` and `terraform.tfvars`

## Setup

Follow these steps to configure AWS credentials securely for this project.

### 1) Install the AWS CLI and Terraform
- AWS CLI: `brew install awscli`
- Terraform: `brew tap hashicorp/tap && brew install hashicorp/tap/terraform`

### 2) Configure a named AWS profile (recommended)
Run:

```bash
aws configure --profile <profile-name>
```

Provide your Access key ID, Secret access key, default region, and output format. Credentials are stored under `~/.aws/credentials`.

### 3) Configure project variables

Set your profile and region:

Edit `terraform.tfvars`:

```hcl
aws_region          = "ap-southeast-2"
aws_profile         = "<profile-name>"
project_name        = "radio-locator"
environment         = "dev"
vpc_cidr            = "10.0.0.0/16"
private_app_subnets = ["10.0.10.0/24", "10.0.11.0/24"]
private_db_subnets  = ["10.0.20.0/24", "10.0.21.0/24"]
single_nat_gateway  = false
availability_zones  = ["ap-southeast-2a", "ap-southeast-2b"]
```

### 4) Initialize and run

```bash
terraform init
terraform plan
terraform apply
```

## Best practices

- Do not hardcode credentials in `.tf` files. Use a named profile, environment variables, or AWS SSO.
- Resource naming and taging should always use `-` and never use `_`
- Prefer short‑lived credentials (SSO or `aws configure sso`) over long‑lived access keys.
- Keep `terraform.tfvars` and state files out of git (see `.gitignore`).

### Next steps

- Build the edge: Route53, CloudFront, API Gateway (public), Cognito. Public endpoints live outside the VPC; VPC services are private behind an internal ALB.
- Add compute: ECS/Fargate services (frontend, backend), internal ALB in private subnets
- Add data: RDS PostgreSQL (split subnets), ElastiCache
- Add async: SQS, Lambda for WebSocket transform and emergency button



