variable "name" {
  description = "The name of the deployment."
  type        = string
}

variable "namespace" {
  description = "The namespace for the deployment."
  type        = string
}

variable "image" {
  description = "The container image to use."
  type        = string
}

variable "image_pull_policy" {
  description = "The image pull policy for the container."
  type        = string
  default     = "IfNotPresent"
}

variable "replicas" {
  description = "Number of replicas for the deployment."
  type        = number
  default     = 1
}

variable "container_port" {
  description = "Optional port to expose on the container."
  type        = number
  default     = null
}

variable "env_vars" {
  description = "A map of environment variables."
  type        = map(string)
  default     = {}
}

variable "command" {
  description = "A list for the container's command (entrypoint)."
  type        = list(string)
  default     = []
}

variable "args" {
  description = "A list of arguments for the container's entrypoint."
  type        = list(string)
  default     = []
}

variable "volumes" {
  description = "A list of volume definitions to attach to the pod."
  type        = any # Simplified for module ease
  default     = []
}

variable "volume_mounts" {
  description = "A list of volume mount definitions for the container."
  type        = any # Simplified for module ease
  default     = []
}

variable "probes" {
  description = "Configuration for liveness and readiness probes."
  type = object({
    enabled = bool
    path    = optional(string, "/healthz")
    port    = optional(number)
  })
  default = {
    enabled = false
  }
}