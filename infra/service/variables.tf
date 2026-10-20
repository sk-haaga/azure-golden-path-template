variable "environment" {
  description = "Which stage to deploy: must be a key under `environments` in golden-path.yaml."
  type        = string
}

variable "image" {
  description = "Image to run, pinned by digest. Set by the pipeline."
  type        = string
}

variable "registry_server" {
  description = "ACR login server. Set by the pipeline from the ACR_LOGIN_SERVER variable."
  type        = string
}

variable "git_sha" {
  description = "Commit being deployed; exposed by the app at /version."
  type        = string
  default     = "unknown"
}

variable "repository" {
  description = "owner/repo, recorded as a tag. Set by the pipeline."
  type        = string
  default     = "sk-haaga/azure-golden-path-template"
}

variable "manifest_path" {
  description = "Path to golden-path.yaml, relative to this directory."
  type        = string
  default     = "../../golden-path.yaml"
}
