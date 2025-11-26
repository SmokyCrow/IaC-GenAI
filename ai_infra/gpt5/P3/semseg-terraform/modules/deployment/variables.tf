variable "name"            { type = string }
variable "namespace"       { type = string }
variable "image"           { type = string }
variable "container_port"  { type = number }
variable "image_pull_policy" {
  type    = string
  default = "IfNotPresent"
}

variable "env" {
  description = "Env vars as map(string)."
  type        = map(string)
  default     = {}
}

variable "command" {
  description = "Container command array. Omit to use image entrypoint."
  type        = list(string)
  default     = []
}

variable "args" {
  description = "Container args."
  type        = list(string)
  default     = []
}

variable "volume_mounts" {
  description = "List of mounts: { name, mount_path, read_only }"
  type = list(object({
    name       = string
    mount_path = string
    read_only  = optional(bool, false)
  }))
  default = []
}

variable "volumes" {
  description = "List of volumes: { name, claim_name }"
  type = list(object({
    name       = string
    claim_name = string
  }))
  default = []
}

variable "resources" {
  description = "Optional requests/limits maps, e.g., { requests = { cpu = \"100m\", memory = \"256Mi\" } }"
  type = object({
    requests = optional(map(string))
    limits   = optional(map(string))
  })
  default = {
    requests = { cpu = "100m", memory = "256Mi" }
    limits   = null
  }
}

variable "readiness_probe" {
  description = "Optional readiness probe (http path & port)."
  type = object({
    path                = string
    port                = number
    initial_delay_secs  = optional(number, 5)
    period_secs         = optional(number, 10)
    timeout_secs        = optional(number, 1)
    failure_threshold   = optional(number, 3)
    success_threshold   = optional(number, 1)
  })
  default = null
}

variable "liveness_probe" {
  description = "Optional liveness probe (http path & port)."
  type = object({
    path                = string
    port                = number
    initial_delay_secs  = optional(number, 10)
    period_secs         = optional(number, 10)
    timeout_secs        = optional(number, 1)
    failure_threshold   = optional(number, 3)
    success_threshold   = optional(number, 1)
  })
  default = null
}

variable "replicas" {
  type    = number
  default = 1
}
