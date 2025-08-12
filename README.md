## Terraform example

This is a minimal Terraform example for AWS. It demonstrates best practices for:
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
aws_region  = "ap-southeast-2"
aws_profile = "<profile-name>"
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



