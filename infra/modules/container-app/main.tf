# A single HTTP service on Azure Container Apps, with logs in Log Analytics.

resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${var.service_name}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = var.tags
}

resource "azurerm_container_app_environment" "this" {
  name                       = "cae-${var.service_name}-${var.environment}"
  resource_group_name        = var.resource_group_name
  location                   = var.location
  logs_destination           = "log-analytics"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  tags                       = var.tags
}

resource "azurerm_container_app" "this" {
  name                         = "ca-${var.service_name}-${var.environment}"
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"
  max_inactive_revisions       = 5
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [var.pull_identity_id]
  }

  # Pull with the managed identity: no registry passwords anywhere.
  registry {
    server   = var.registry_server
    identity = var.pull_identity_id
  }

  ingress {
    external_enabled           = true
    target_port                = var.target_port
    transport                  = "auto"
    allow_insecure_connections = false

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    http_scale_rule {
      name                = "http-concurrency"
      concurrent_requests = tostring(var.concurrent_requests_per_replica)
    }

    container {
      name   = var.service_name
      image  = var.image
      cpu    = var.cpu
      memory = var.memory

      dynamic "env" {
        for_each = merge(var.env_vars, {
          SERVICE_NAME    = var.service_name
          APP_ENVIRONMENT = var.environment
          PORT            = tostring(var.target_port)
        })
        content {
          name  = env.key
          value = env.value
        }
      }

      startup_probe {
        transport               = "HTTP"
        port                    = var.target_port
        path                    = var.liveness_path
        interval_seconds        = 5
        failure_count_threshold = 24 # up to 2 minutes to start
      }

      liveness_probe {
        transport               = "HTTP"
        port                    = var.target_port
        path                    = var.liveness_path
        interval_seconds        = 10
        failure_count_threshold = 3
      }

      readiness_probe {
        transport               = "HTTP"
        port                    = var.target_port
        path                    = var.readiness_path
        interval_seconds        = 5
        failure_count_threshold = 3
      }
    }
  }
}
