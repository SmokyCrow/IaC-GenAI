variable "namespace" {
  description = "Kubernetes namespace for all resources"
  type        = string
  default     = "semseg"
}

variable "shared_image" {
  description = "Docker image for workers and web UIs"
  type        = string
  default     = "semantic-segmenter:latest"
}

variable "ingest_image" {
  description = "Docker image for ingest-api"
  type        = string
  default     = "ingest-api:latest"
}

variable "redis_image" {
  description = "Docker image for Redis"
  type        = string
  default     = "redis:7-alpine"
}

variable "storage_class" {
  description = "Storage class for PVCs"
  type        = string
  default     = "hostpath"
}

variable "sub_pc_frames_size" {
  description = "Size of sub-pc-frames PVC"
  type        = string
  default     = "64Mi"
}

variable "pc_frames_size" {
  description = "Size of pc-frames PVC"
  type        = string
  default     = "128Mi"
}

variable "segments_size" {
  description = "Size of segments PVC"
  type        = string
  default     = "256Mi"
}
