variable "name" {
  description = "The name of the service."
  type        = string
}

variable "namespace" {
  description = "The namespace for the service."
  type        = string
}

variable "selector_app" {
  description = "The value of the 'app' label to select pods."
  type        = string
}

variable "service_type" {
  description = "Type of service (e.g., ClusterIP, NodePort)."
  type        = string
  default     = "ClusterIP"
}

variable "port" {
  description = "The port the service will expose."
  type        = number
}

variable "target_port" {
  description = "The container port to target."
  type        = number
}

variable "node_port" {
  description = "The NodePort to expose (if service_type is NodePort)."
  type        = number
  default     = null
}