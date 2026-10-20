terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.10"
    }
  }

  # Partial configuration: the pipeline passes resource_group_name,
  # storage_account_name, container_name and key with -backend-config, and
  # authenticates with the same GitHub OIDC token (no storage keys).
  backend "azurerm" {
    use_oidc         = true
    use_azuread_auth = true
  }
}

provider "azurerm" {
  features {}

  # Credentials come from ARM_CLIENT_ID / ARM_TENANT_ID / ARM_SUBSCRIPTION_ID
  # and ARM_USE_OIDC=true, set by the workflow.
  storage_use_azuread = true

  # Pipeline identities are scoped to one resource group and cannot register
  # resource providers; bootstrap registers what is needed.
  resource_provider_registrations = "none"
}
