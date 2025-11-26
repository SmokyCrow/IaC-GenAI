variable "name" {
  description = "Name of the service"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
}

variable "service_type" {
  description = "Type of service (ClusterIP, NodePort, LoadBalancer)"
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
  description = "NodePort (only used when service_type is NodePort)"
  type        = number
  default     = null
}

variable "selector" {
  description = "Label selector for pods"
  type        = map(string)
}
