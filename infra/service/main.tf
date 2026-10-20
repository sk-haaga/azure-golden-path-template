# Root module the pipeline runs once per environment. All service-specific
# values come from golden-path.yaml, so teams do not edit Terraform to ship.

locals {
  manifest = yamldecode(file("${path.module}/${var.manifest_path}"))
  service  = local.manifest.service
  runtime  = local.manifest.runtime
  env_cfg  = lookup(local.manifest.environments, var.environment, null)

  # Every value here is a required tag; the require-tags action blocks the
  # deployment if any resource in the plan ends up without them.
  tags = {
    owner               = local.service.owner
    cost-center         = local.service.cost_center
    environment         = var.environment
    service             = local.service.name
    data-classification = local.service.data_classification
    managed-by          = "terraform"
    repository          = var.repository
  }
}

# Created by infra/bootstrap; the deploy identity only has rights inside it.
data "azurerm_resource_group" "this" {
  name = "rg-${local.service.name}-${var.environment}"

  lifecycle {
    precondition {
      condition     = local.env_cfg != null
      error_message = "Environment '${var.environment}' is not defined under environments in golden-path.yaml."
    }
    precondition {
      condition     = contains(["public", "internal", "confidential"], local.service.data_classification)
      error_message = "service.data_classification must be public, internal or confidential."
    }
  }
}

data "azurerm_user_assigned_identity" "app" {
  name                = "id-${local.service.name}-app-${var.environment}"
  resource_group_name = data.azurerm_resource_group.this.name
}

module "app" {
  source = "../modules/container-app"

  service_name        = local.service.name
  environment         = var.environment
  resource_group_name = data.azurerm_resource_group.this.name
  location            = data.azurerm_resource_group.this.location

  image            = var.image
  registry_server  = var.registry_server
  pull_identity_id = data.azurerm_user_assigned_identity.app.id

  target_port    = local.runtime.port
  cpu            = local.runtime.cpu
  memory         = local.runtime.memory
  liveness_path  = local.runtime.liveness_path
  readiness_path = local.runtime.readiness_path
  env_vars       = merge(try(local.runtime.env, {}), { GIT_SHA = var.git_sha })

  min_replicas = try(local.env_cfg.min_replicas, 0)
  max_replicas = try(local.env_cfg.max_replicas, 2)

  tags = local.tags
}
