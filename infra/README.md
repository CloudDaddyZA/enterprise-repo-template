# Infrastructure as Code

This directory contains infrastructure definitions using both Terraform and Bicep.

## Structure

```
infra/
├── terraform/          # Terraform modules and configurations
│   ├── modules/        # Reusable Terraform modules
│   ├── environments/   # Environment-specific configurations
│   ├── .tflint.hcl     # TFLint rules (azurerm, naming, docs)
│   └── main.tf         # Root module
├── bicep/              # Azure Bicep templates
│   ├── modules/        # Reusable Bicep modules
│   ├── bicepconfig.json # Bicep linting configuration
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

## IaC Guardrails

The `.github/workflows/iac-guardrails.yml` workflow automatically validates infrastructure changes:

| Check | Tool | Scope |
|-------|------|-------|
| Formatting | `terraform fmt` | `infra/terraform/**` |
| Validation | `terraform validate` | `infra/terraform/**` |
| Linting | TFLint (`.tflint.hcl`) | `infra/terraform/**` |
| Bicep build | `az bicep build` | `infra/bicep/**` |
| Bicep lint | `bicepconfig.json` rules | `infra/bicep/**` |
| Security | Checkov | All IaC files |

The workflow triggers on PRs that modify files under `infra/`.
