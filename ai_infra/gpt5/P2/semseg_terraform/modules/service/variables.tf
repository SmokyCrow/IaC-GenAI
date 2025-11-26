variable "name" {
  type = string
}

variable "namespace" {
  type = string
}

variable "service_type" {
  description = "ClusterIP or NodePort"
  type        = string
  validation {
    condition     = contains(["ClusterIP", "NodePort"], var.service_type)
    error_message = "service_type must be ClusterIP or NodePort."
  }
}

variable "port" {
  type = number
}

variable "target_port" {
  type = number
}

variable "node_port" {
  type    = number
  default = null
}

variable "selector" {
  description = "Service selector map, e.g. { app = \"name\" }"
  type        = map(string)
}
