# ============================================================================
# Terraform Root Module - Enterprise Template
# ============================================================================
# This is the root module entry point. Configure your providers and
# call modules from ./modules/ as needed.
# ============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.74"
    }
  }

  # Remote state configuration - uncomment and configure for your backend
  # backend "azurerm" {
  #   resource_group_name  = "rg-terraform-state"
  #   storage_account_name = "stterraformstate"
  #   container_name       = "tfstate"
  #   key                  = "enterprise-template.tfstate"
  # }
}

provider "azurerm" {
  features {}
}

# ============================================================================
# Local Values
# ============================================================================

locals {
  common_tags = merge(var.tags, {
    environment = var.environment
    managed_by  = "terraform"
    project     = var.project_name
  })

  name_prefix = "${var.project_name}-${var.environment}"
}

# ============================================================================
# Resource Group
# ============================================================================

resource "azurerm_resource_group" "main" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.common_tags
}

# ============================================================================
# Add your module calls below
# ============================================================================
# Example:
# module "networking" {
#   source              = "./modules/networking"
#   resource_group_name = azurerm_resource_group.main.name
#   location            = azurerm_resource_group.main.location
#   tags                = local.common_tags
# }
