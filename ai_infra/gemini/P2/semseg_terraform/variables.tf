variable "namespace" {
  description = "The Kubernetes namespace to deploy all resources into."
  type        = string
  default     = "semseg"
}

variable "shared_image" {
  description = "The container image for worker and web UI deployments."
  type        = string
  default     = "semantic-segmenter:latest"
}

variable "ingest_image" {
  description = "The container image for the ingest-api deployment."
  type        = string
  default     = "ingest-api:latest"
}

variable "redis_image" {
  description = "The container image for the Redis deployment."
  type        = string
  default     = "redis:7-alpine"
}