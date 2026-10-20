output "acr_login_server" {
  value = azurerm_container_registry.this.login_server
}

output "environment_resource_groups" {
  value = { for env, rg in azurerm_resource_group.env : env => rg.name }
}

# Consumed by scripts/configure-github.sh, which writes these into the
# repository as GitHub Actions *variables*. None of them are secrets: OIDC
# identities are referenced by client ID, and trust is defined in Azure.
output "github_repository_variables" {
  value = {
    AZURE_TENANT_ID         = data.azurerm_client_config.current.tenant_id
    AZURE_SUBSCRIPTION_ID   = data.azurerm_client_config.current.subscription_id
    AZURE_BUILD_CLIENT_ID   = azurerm_user_assigned_identity.build.client_id
    AZURE_PLAN_CLIENT_ID    = azurerm_user_assigned_identity.plan.client_id
    ACR_NAME                = azurerm_container_registry.this.name
    ACR_LOGIN_SERVER        = azurerm_container_registry.this.login_server
    TFSTATE_RESOURCE_GROUP  = azurerm_resource_group.platform.name
    TFSTATE_STORAGE_ACCOUNT = azurerm_storage_account.tfstate.name
    TFSTATE_CONTAINER       = azurerm_storage_container.tfstate.name
  }
}

output "github_environment_variables" {
  value = merge(
    {
      for env in var.environments : env => {
        AZURE_CLIENT_ID = azurerm_user_assigned_identity.deploy[env].client_id
      }
    },
    var.remediation_openai_account_id == "" ? {} : {
      remediation = {
        AZURE_CLIENT_ID = azurerm_user_assigned_identity.remediation[0].client_id
      }
    }
  )
}
