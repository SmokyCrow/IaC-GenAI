variable "namespace" {
  description = "Kubernetes namespace to deploy into"
  type        = string
  default     = "semseg"
}

variable "kubeconfig" {
  description = "Path to kubeconfig (Docker Desktop usually uses ~/.kube/config)"
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Kube context name (e.g., docker-desktop). Leave null to use current."
  type        = string
  default     = null
}

variable "shared_image" {
  description = "Container image for shared workers and web UIs"
  type        = string
  default     = "semantic-segmenter:latest"
}

variable "ingest_image" {
  description = "Container image for ingest-api"
  type        = string
  default     = "ingest-api:latest"
}

variable "redis_image" {
  description = "Container image for Redis"
  type        = string
  default     = "redis:7-alpine"
}

variable "node_ip" {
  description = "Node IP/host for NodePort URLs (Docker Desktop usually localhost)"
  type        = string
  default     = "localhost"
}
