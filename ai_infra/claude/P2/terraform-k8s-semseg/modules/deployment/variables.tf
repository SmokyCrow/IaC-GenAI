variable "name" {
  description = "Name of the deployment"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
}

variable "image" {
  description = "Container image"
  type        = string
}

variable "image_pull_policy" {
  description = "Image pull policy (Always, IfNotPresent, Never)"
  type        = string
  default     = "IfNotPresent"
}

variable "replicas" {
  description = "Number of replicas"
  type        = number
  default     = 1
}

variable "command" {
  description = "Container command (overrides image ENTRYPOINT)"
  type        = list(string)
  default     = null
}

variable "args" {
  description = "Container arguments (overrides image CMD or appends to ENTRYPOINT)"
  type        = list(string)
  default     = null
}

variable "container_port" {
  description = "Container port to expose"
  type        = number
  default     = null
}

variable "env_vars" {
  description = "Environment variables as a map"
  type        = map(string)
  default     = {}
}

variable "volume_mounts" {
  description = "List of volume mounts"
  type = list(object({
    name       = string
    mount_path = string
    claim_name = string
  }))
  default = []
}

variable "readiness_probe" {
  description = "Readiness probe configuration"
  type = object({
    http_get = object({
      path = string
      port = number
    })
    initial_delay_seconds = number
    period_seconds        = number
  })
  default = null
}

variable "liveness_probe" {
  description = "Liveness probe configuration"
  type = object({
    http_get = object({
      path = string
      port = number
    })
    initial_delay_seconds = number
    period_seconds        = number
  })
  default = null
}
