variable "kubeconfig" {
  description = "Optional path to kubeconfig. If null, defaults to ~/.kube/config."
  type        = string
  default     = null
}

variable "namespace" {
  description = "Kubernetes namespace to create and deploy into."
  type        = string
  default     = "semseg"
}

variable "image_repo" {
  description = "Image for workers and web APIs (tag included)."
  type        = string
  default     = "semantic-segmenter:latest"
}

variable "ingest_image" {
  description = "Image for the ingest API (tag included)."
  type        = string
  default     = "ingest-api:latest"
}

variable "node_port_base" {
  description = "Base NodePort for external services (ingest=+0, results=+1, qa=+2)."
  type        = number
  default     = 30080
}

variable "pvc_storage_class_name" {
  description = "StorageClass to use for all PVCs."
  type        = string
  default     = "hostpath"
}
