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

variable "replicas" {
  description = "Number of replicas for the deployment."
  type        = number
  default     = 1
}

variable "image_pull_policy" {
  description = "Image pull policy."
  type        = string
  default     = "IfNotPresent"
}

variable "container_port" {
  description = "A single port to expose on the container."
  type        = number
  default     = null
}

variable "command" {
  description = "Command to run in the container."
  type        = list(string)
  default     = null
}

variable "args" {
  description = "Arguments for the command."
  type        = list(string)
  default     = null
}

variable "env_vars" {
  description = "A map of environment variables (name = value)."
  type        = map(string)
  default     = {}
}

variable "volumes" {
  description = "List of volumes to attach to the pod."
  type = list(object({
    name      = string
    pvc_claim = string
  }))
  default = []
}

variable "volume_mounts" {
  description = "List of volume mounts for the container."
  type = list(object({
    name       = string
    mount_path = string
  }))
  default = []
}

variable "resources" {
  description = "Map of resources requests and limits (e.g., { requests = { cpu = \"100m\", memory = \"256Mi\" } })."
  type        = any
  default     = null
}

variable "liveness_probe" {
  description = "Configuration for liveness probe."
  type = object({
    path          = string
    port          = number
    initial_delay = optional(number, 15)
    period        = optional(number, 20)
  })
  default = null
}

variable "readiness_probe" {
  description = "Configuration for readiness probe."
  type = object({
    path          = string
    port          = number
    initial_delay = optional(number, 5)
    period        = optional(number, 10)
  })
  default = null
}