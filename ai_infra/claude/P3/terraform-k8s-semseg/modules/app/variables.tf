variable "name" {
  description = "Name of the application"
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
  description = "Container port (optional)"
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
  default = {
    requests = {
      cpu    = "100m"
      memory = "256Mi"
    }
    limits = {
      cpu    = "500m"
      memory = "512Mi"
    }
  }
}

variable "service_type" {
  description = "Service type (ClusterIP, NodePort)"
  type        = string
  default     = "NodePort"
}

variable "service_port" {
  description = "Service port (defaults to container port if not specified)"
  type        = number
  default     = null
}

variable "node_port" {
  description = "NodePort number (only used if service_type is NodePort)"
  type        = number
  default     = null
}

variable "enable_health_probes" {
  description = "Enable liveness and readiness probes"
  type        = bool
  default     = false
}
