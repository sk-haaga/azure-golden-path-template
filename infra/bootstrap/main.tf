# One-time platform setup for a service.
#
# Creates everything the pipeline needs before it can deploy anything:
#   * a container registry and a Terraform state store (no shared keys)
#   * one resource group per environment
#   * the runtime identity each environment's app uses to pull images
#   * GitHub OIDC identities, each trusted only for one workflow context and
#     given only the roles that context needs. No client secrets exist.
#
#   identity        trusted subject (who may log in)            can do
#   ------------    ----------------------------------------   ------------------------------------
#   build           repo:<o>/<r>:ref:refs/heads/main           push images to ACR
#   plan            repo:<o>/<r>:pull_request                  read env resource groups + state
#   deploy-<env>    repo:<o>/<r>:environment:<env>             manage its own resource group, write state
#   remediation     repo:<o>/<r>:environment:remediation       call Azure OpenAI (optional)

data "azurerm_client_config" "current" {}

locals {
  manifest = yamldecode(file(var.manifest_path))
  service  = local.manifest.service.name
  compact  = replace(local.service, "-", "")
  repo     = "${var.github_owner}/${var.github_repo}"

  oidc_issuer   = "https://token.actions.githubusercontent.com"
  oidc_audience = ["api://AzureADTokenExchange"]

  base_tags = {
    owner                 = local.manifest.service.owner
    cost-center           = local.manifest.service.cost_center
    service               = local.service
    data-classification   = local.manifest.service.data_classification
    managed-by            = "terraform"
    repository            = local.repo
    golden-path-component = "bootstrap"
  }
  platform_tags = merge(local.base_tags, { environment = "shared" })
}

resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

# ---------------------------------------------------------------- shared platform

resource "azurerm_resource_group" "platform" {
  name     = "rg-${local.service}-platform"
  location = var.location
  tags     = local.platform_tags

  lifecycle {
    precondition {
      condition     = can(regex("^[a-z][a-z0-9-]{1,18}[a-z0-9]$", local.service))
      error_message = "service.name in golden-path.yaml must be 3-20 chars of lowercase letters, digits and hyphens."
    }
  }
}

resource "azurerm_container_registry" "this" {
  name                          = "cr${substr(local.compact, 0, 40)}${random_string.suffix.result}"
  resource_group_name           = azurerm_resource_group.platform.name
  location                      = azurerm_resource_group.platform.location
  sku                           = "Standard"
  admin_enabled                 = false
  anonymous_pull_enabled        = false
  public_network_access_enabled = true # GitHub-hosted runners push from the internet
  tags                          = local.platform_tags
}

resource "azurerm_storage_account" "tfstate" {
  name                              = "st${substr(local.compact, 0, 15)}tf${random_string.suffix.result}"
  resource_group_name               = azurerm_resource_group.platform.name
  location                          = azurerm_resource_group.platform.location
  account_tier                      = "Standard"
  account_replication_type          = "GZRS"
  infrastructure_encryption_enabled = true
  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  allow_nested_items_to_be_public   = false
  shared_access_key_enabled         = false # Entra ID auth only
  default_to_oauth_authentication   = true

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 30
    }
    container_delete_retention_policy {
      days = 30
    }
  }

  tags = local.platform_tags
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

locals {
  tfstate_container_scope = "${azurerm_storage_account.tfstate.id}/blobServices/default/containers/${azurerm_storage_container.tfstate.name}"
}

# ---------------------------------------------------------------- per environment

resource "azurerm_resource_group" "env" {
  for_each = toset(var.environments)

  name     = "rg-${local.service}-${each.key}"
  location = var.location
  tags     = merge(local.base_tags, { environment = each.key })
}

# Runtime identity the Container App uses to pull its image. Created here so the
# deploy identities never need permission to grant roles.
resource "azurerm_user_assigned_identity" "app" {
  for_each = toset(var.environments)

  name                = "id-${local.service}-app-${each.key}"
  resource_group_name = azurerm_resource_group.env[each.key].name
  location            = var.location
  tags                = merge(local.base_tags, { environment = each.key })
}

resource "azurerm_role_assignment" "app_acr_pull" {
  for_each = toset(var.environments)

  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.app[each.key].principal_id
  principal_type       = "ServicePrincipal"
}

# ---------------------------------------------------------------- GitHub OIDC identities

resource "azurerm_user_assigned_identity" "build" {
  name                = "id-${local.service}-gh-build"
  resource_group_name = azurerm_resource_group.platform.name
  location            = var.location
  tags                = local.platform_tags
}

resource "azurerm_federated_identity_credential" "build" {
  name                      = "github-main"
  user_assigned_identity_id = azurerm_user_assigned_identity.build.id
  issuer                    = local.oidc_issuer
  audience                  = local.oidc_audience
  subject                   = "repo:${local.repo}:ref:refs/heads/main"
}

resource "azurerm_role_assignment" "build_acr_push" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.build.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_user_assigned_identity" "plan" {
  name                = "id-${local.service}-gh-plan"
  resource_group_name = azurerm_resource_group.platform.name
  location            = var.location
  tags                = local.platform_tags
}

resource "azurerm_federated_identity_credential" "plan" {
  name                      = "github-pull-request"
  user_assigned_identity_id = azurerm_user_assigned_identity.plan.id
  issuer                    = local.oidc_issuer
  audience                  = local.oidc_audience
  subject                   = "repo:${local.repo}:pull_request"
}

resource "azurerm_role_assignment" "plan_reader" {
  for_each = toset(var.environments)

  scope                = azurerm_resource_group.env[each.key].id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.plan.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "plan_state_reader" {
  scope                = local.tfstate_container_scope
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.plan.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_user_assigned_identity" "deploy" {
  for_each = toset(var.environments)

  name                = "id-${local.service}-gh-deploy-${each.key}"
  resource_group_name = azurerm_resource_group.platform.name
  location            = var.location
  tags                = local.platform_tags
}

resource "azurerm_federated_identity_credential" "deploy" {
  for_each = toset(var.environments)

  name                      = "github-env-${each.key}"
  user_assigned_identity_id = azurerm_user_assigned_identity.deploy[each.key].id
  issuer                    = local.oidc_issuer
  audience                  = local.oidc_audience
  subject                   = "repo:${local.repo}:environment:${each.key}"
}

resource "azurerm_role_assignment" "deploy_contributor" {
  for_each = toset(var.environments)

  scope                = azurerm_resource_group.env[each.key].id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.deploy[each.key].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "deploy_state_writer" {
  for_each = toset(var.environments)

  scope                = local.tfstate_container_scope
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.deploy[each.key].principal_id
  principal_type       = "ServicePrincipal"
}

# ---------------------------------------------------------------- optional: remediation agent

resource "azurerm_user_assigned_identity" "remediation" {
  count = var.remediation_openai_account_id == "" ? 0 : 1

  name                = "id-${local.service}-gh-remediation"
  resource_group_name = azurerm_resource_group.platform.name
  location            = var.location
  tags                = local.platform_tags
}

resource "azurerm_federated_identity_credential" "remediation" {
  count = var.remediation_openai_account_id == "" ? 0 : 1

  name                      = "github-env-remediation"
  user_assigned_identity_id = azurerm_user_assigned_identity.remediation[0].id
  issuer                    = local.oidc_issuer
  audience                  = local.oidc_audience
  subject                   = "repo:${local.repo}:environment:remediation"
}

resource "azurerm_role_assignment" "remediation_openai_user" {
  count = var.remediation_openai_account_id == "" ? 0 : 1

  scope                = var.remediation_openai_account_id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_user_assigned_identity.remediation[0].principal_id
  principal_type       = "ServicePrincipal"
}
