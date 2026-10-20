variable "service_name" {
  description = "Service name; used in every resource name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,18}[a-z0-9]$", var.service_name))
    error_message = "service_name must be 3-20 chars of lowercase letters, digits and hyphens."
  }
}

variable "environment" {
  description = "Deployment stage, e.g. staging or production."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group for this environment (created by bootstrap)."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "image" {
  description = "Full image reference, preferably pinned by digest: <registry>/<repo>@sha256:..."
  type        = string

  validation {
    condition     = can(regex("@sha256:[a-f0-9]{64}$", var.image)) || can(regex(":[A-Za-z0-9_.-]+$", var.image))
    error_message = "image must include a tag or, better, a sha256 digest."
  }
}

variable "registry_server" {
  description = "Login server of the container registry, e.g. myacr.azurecr.io."
  type        = string
}

variable "pull_identity_id" {
  description = "Resource ID of the user-assigned identity with AcrPull on the registry."
  type        = string
}

variable "target_port" {
  description = "Port the container listens on."
  type        = number
  default     = 8000
}

variable "cpu" {
  description = "vCPU per replica."
  type        = number
  default     = 0.25
}

variable "memory" {
  description = "Memory per replica, e.g. 0.5Gi. Must be a valid pairing with cpu."
  type        = string
  default     = "0.5Gi"
}

variable "min_replicas" {
  type    = number
  default = 0
}

variable "max_replicas" {
  type    = number
  default = 2

  validation {
    condition     = var.max_replicas >= 1 && var.max_replicas <= 30
    error_message = "max_replicas must be between 1 and 30."
  }
}

variable "concurrent_requests_per_replica" {
  description = "HTTP scale rule: add a replica above this many concurrent requests."
  type        = number
  default     = 50
}

variable "liveness_path" {
  type    = string
  default = "/healthz"
}

variable "readiness_path" {
  type    = string
  default = "/readyz"
}

variable "env_vars" {
  description = "Plain, non-secret environment variables for the container."
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "tags" {
  description = "Tags applied to every resource. The pipeline blocks plans that miss required tags."
  type        = map(string)
}
