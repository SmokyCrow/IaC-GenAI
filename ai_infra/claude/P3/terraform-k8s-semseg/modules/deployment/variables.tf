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
  description = "Image pull policy"
  type        = string
  default     = "IfNotPresent"
}

variable "replicas" {
  description = "Number of replicas"
  type        = number
  default     = 1
}

variable "port" {
  description = "Container port"
  type        = number
  default     = null
}

variable "command" {
  description = "Container command"
  type        = list(string)
  default     = null
}

variable "args" {
  description = "Container args"
  type        = list(string)
  default     = null
}

variable "environment" {
  description = "Environment variables"
  type        = map(string)
  default     = {}
}

variable "volumes" {
  description = "Volume mounts"
  type = list(object({
    name       = string
    mount_path = string
    pvc_name   = string
  }))
  default = []
}

variable "resources" {
  description = "Resource requests and limits"
  type = object({
    requests = map(string)
    limits   = map(string)
  })
  default = null
}

variable "liveness_probe" {
  description = "Liveness probe configuration"
  type = object({
    path                  = string
    port                  = number
    initial_delay_seconds = number
    period_seconds        = number
    timeout_seconds       = number
    failure_threshold     = number
  })
  default = null
}

variable "readiness_probe" {
  description = "Readiness probe configuration"
  type = object({
    path                  = string
    port                  = number
    initial_delay_seconds = number
    period_seconds        = number
    timeout_seconds       = number
    failure_threshold     = number
  })
  default = null
}
