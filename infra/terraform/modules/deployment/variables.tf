variable "name" {
  type = string
}

variable "namespace" {
  type = string
}

variable "labels" {
  type    = map(string)
  default = null
}

variable "replicas" {
  type    = number
  default = 1
}

variable "container_name" {
  type    = string
  default = ""
}

variable "image" {
  type = string
}

variable "image_pull_policy" {
  type    = string
  default = "IfNotPresent"
}

variable "container_ports" {
  type    = list(number)
  default = []
}

variable "command" {
  type    = list(string)
  default = []
}

variable "args" {
  type    = list(string)
  default = []
}

variable "env" {
  type    = map(string)
  default = {}
}

variable "volume_mounts" {
  type = list(object({
    name       = string
    mount_path = string
  }))
  default = []
}

variable "volumes" {
  type = list(object({
    name       = string
    claim_name = string
  }))
  default = []
}

variable "readiness_http" {
  type = object({
    path = string
    port = number
  })
  default = null
}

variable "readiness_exec" {
  description = "If provided, readiness probe will run this exec command instead of HTTP."
  type        = list(string)
  default     = []
}

variable "readiness_initial_delay_seconds" {
  type    = number
  default = 0
}

variable "readiness_period_seconds" {
  type    = number
  default = 10
}

variable "liveness_http" {
  type = object({
    path = string
    port = number
  })
  default = null
}

variable "liveness_initial_delay_seconds" {
  type    = number
  default = 0
}

variable "liveness_period_seconds" {
  type    = number
  default = 10
}

