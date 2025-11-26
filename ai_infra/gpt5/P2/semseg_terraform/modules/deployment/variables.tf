variable "name" {
  type = string
}

variable "namespace" {
  type = string
}

variable "image" {
  type = string
}

variable "replicas" {
  type    = number
  default = 1
}

variable "port" {
  description = "Container port (optional)"
  type        = number
  default     = null
}

variable "env" {
  description = "Map of environment variables"
  type        = map(string)
  default     = {}
}

variable "readiness_path" {
  description = "HTTP readiness probe path (optional)"
  type        = string
  default     = null
}

variable "liveness_path" {
  description = "HTTP liveness probe path (optional)"
  type        = string
  default     = null
}

variable "volume_claims" {
  description = "List of { name, claim } for volumes"
  type = list(object({
    name  : string
    claim : string
  }))
  default = []
}

variable "volume_mounts" {
  description = "List of { name, mount_path, read_only? } for mounts"
  type = list(object({
    name       : string
    mount_path : string
    read_only  : optional(bool)
  }))
  default = []
}

variable "command" {
  description = "Container entrypoint command"
  type        = list(string)
  default     = []
}

variable "args" {
  description = "Container args"
  type        = list(string)
  default     = []
}