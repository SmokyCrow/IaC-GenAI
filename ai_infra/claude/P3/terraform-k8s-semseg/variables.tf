variable "namespace" {
  description = "Kubernetes namespace for all resources"
  type        = string
  default     = "semseg"
}

variable "image_repo" {
  description = "Docker image for semantic segmentation services"
  type        = string
  default     = "semantic-segmenter:latest"
}

variable "ingest_image" {
  description = "Docker image for ingest API service"
  type        = string
  default     = "ingest-api:latest"
}

variable "node_port_base" {
  description = "Base NodePort number for external services"
  type        = number
  default     = 30080
}

variable "pvc_storage_class_name" {
  description = "Storage class name for PVCs"
  type        = string
  default     = "hostpath"
}

variable "kubeconfig" {
  description = "Path to kubeconfig file (optional, defaults to ~/.kube/config)"
  type        = string
  default     = ""
}
