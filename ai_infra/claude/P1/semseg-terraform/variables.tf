variable "kubeconfig_path" {
  description = "Path to the kubeconfig file for Docker Desktop Kubernetes"
  type        = string
  default     = "~/.kube/config"
}

variable "shared_image" {
  description = "Docker image for shared components (workers and web UIs)"
  type        = string
  default     = "semantic-segmenter:latest"
}

variable "ingest_image" {
  description = "Docker image for the ingest API"
  type        = string
  default     = "ingest-api:latest"
}

variable "redis_image" {
  description = "Docker image for Redis cache"
  type        = string
  default     = "redis:7-alpine"
}
