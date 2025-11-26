variable "name" {
  description = "The name of the service."
  type        = string
}

variable "namespace" {
  description = "The namespace for the service."
  type        = string
}

variable "selector_app" {
  description = "The value for the 'app' label selector."
  type        = string
}

variable "type" {
  description = "The type of service (e.g., ClusterIP, NodePort)."
  type        = string
  default     = "ClusterIP"
}

variable "ports" {
  description = "A list of port objects to expose."
  type = list(object({
    port        = number
    target_port = number
    node_port   = optional(number)
  }))
}