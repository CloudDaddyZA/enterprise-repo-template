# Infrastructure as Code

This directory contains infrastructure definitions using both Terraform and Bicep.

## Structure

```
infra/
├── terraform/          # Terraform modules and configurations
│   ├── modules/        # Reusable Terraform modules
│   ├── environments/   # Environment-specific configurations
│   └── main.tf         # Root module
├── bicep/              # Azure Bicep templates
│   ├── modules/        # Reusable Bicep modules
│   └── main.bicep      # Main deployment
└── README.md           # This file
```

## Usage

### Terraform

```bash
cd infra/terraform
terraform init
terraform plan -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars
```

### Bicep

```bash
cd infra/bicep
az deployment group create \
  --resource-group <rg-name> \
  --template-file main.bicep \
  --parameters @parameters/dev.bicepparam
```

## Environments

| Environment | Purpose | Approval Required |
|-------------|---------|-------------------|
| dev | Development/testing | No |
| staging | Pre-production validation | Yes (1 reviewer) |
| production | Live workloads | Yes (2 reviewers) |

## Conventions

- All resources must be tagged with: `environment`, `team`, `cost-center`, `project`
- Use remote state (Terraform) or deployment stacks (Bicep)
- Follow least-privilege RBAC assignments
- Enable diagnostic settings on all resources
