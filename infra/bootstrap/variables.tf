variable "subscription_id" {
  description = "Azure subscription the service is deployed into."
  type        = string
}

variable "github_owner" {
  description = "GitHub user or organisation that owns the service repository."
  type        = string
  default     = "sk-haaga"
}

variable "github_repo" {
  description = "Repository name. Federated credentials only trust workflows from this repo."
  type        = string
  default     = "azure-golden-path-template"
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "swedencentral"
}

variable "environments" {
  description = "Deployment stages, in promotion order."
  type        = list(string)
  default     = ["staging", "production"]

  validation {
    condition     = length(var.environments) > 0 && alltrue([for e in var.environments : can(regex("^[a-z]{3,12}$", e))])
    error_message = "Environment names must be 3-12 lowercase letters."
  }
}

variable "remediation_openai_account_id" {
  description = <<-EOT
    Optional resource ID of the Azure OpenAI account the Vulnerability
    Remediation Agent uses. When set, an OIDC identity is created for the
    `remediation` GitHub environment with the Cognitive Services OpenAI User role.
  EOT
  type        = string
  default     = ""
}

variable "manifest_path" {
  description = "Path to golden-path.yaml."
  type        = string
  default     = "../../golden-path.yaml"
}
