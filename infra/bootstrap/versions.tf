terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.10"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  # Bootstrap runs once, from an admin's machine, before any pipeline exists,
  # so its state is local. Keep the generated terraform.tfstate somewhere safe
  # (or migrate it into the storage account this module creates).
}

provider "azurerm" {
  features {}

  subscription_id     = var.subscription_id
  storage_use_azuread = true

  # The pipeline identities cannot register resource providers, so the admin
  # running bootstrap registers the ones the template needs, once.
  resource_provider_registrations = "core"
  resource_providers_to_register = [
    "Microsoft.App",
    "Microsoft.OperationalInsights",
    "Microsoft.ContainerRegistry",
    "Microsoft.ManagedIdentity",
  ]
}
