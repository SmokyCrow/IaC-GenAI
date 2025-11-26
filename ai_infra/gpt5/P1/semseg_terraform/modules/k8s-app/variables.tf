variable "name" {
  type = string
}

variable "namespace" {
  type = string
}

variable "image" {
  type = string
}

variable "image_pull_policy" {
  type    = string
  default = "IfNotPresent"
}

variable "replicas" {
  type    = number
  default = 1
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "env" {
  description = "Environment variables for the container"
  type        = map(string)
  default     = {}
}

variable "container_port" {
  description = "Primary container port (if the app exposes one)"
  type        = number
  default     = 0
}

variable "service_enabled" {
  type    = bool
  default = false
}

variable "service_type" {
  type    = string
  default = "ClusterIP"
}

variable "service_port" {
  type    = number
  default = 0
}

variable "node_port" {
  type     = number
  default  = 0
  nullable = false
  # Used only if service_type == "NodePort"
}

variable "args" {
  description = "Optional container args"
  type        = list(string)
  default     = []
}

variable "command" {
  description = "Optional container command (entrypoint)"
  type        = list(string)
  default     = []
}

variable "extra_annotations" {
  description = "Pod annotations"
  type        = map(string)
  default     = {}
}

variable "pvc_mounts" {
  description = "Map of {pvc_name = mount_path}"
  type        = map(string)
  default     = {}
}