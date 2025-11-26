variable "name" {
  description = "Name of the service"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
}

variable "selector_app" {
  description = "App label to select pods"
  type        = string
}

variable "type" {
  description = "Service type (ClusterIP, NodePort, LoadBalancer)"
  type        = string
  default     = "ClusterIP"
}

variable "port" {
  description = "Service port"
  type        = number
}

variable "target_port" {
  description = "Target port on the pod"
  type        = number
}

variable "node_port" {
  description = "NodePort (only used if type is NodePort)"
  type        = number
  default     = null
}
