variable "namespace" {
  description = "The Kubernetes namespace to deploy all resources into."
  type        = string
  default     = "semseg"
}

variable "image_repo" {
  description = "The main application image repository and tag (e.g., 'semantic-segmenter:latest')."
  type        = string
  default     = "semantic-segmenter:latest"
}

variable "ingest_image" {
  description = "The image for the ingest-api service (e.g., 'ingest-api:latest')."
  type        = string
  default     = "ingest-api:latest"
}

variable "node_port_base" {
  description = "The base NodePort number. ingest=base+0, results=base+1, qa=base+2."
  type        = number
  default     = 30080
}

variable "pvc_storage_class_name" {
  description = "The storage class name for all PVCs. For Docker Desktop, 'hostpath' is common."
  type        = string
  default     = "hostpath"
}

variable "kubeconfig" {
  description = "Optional path to a kubeconfig file. If null, provider uses default resolution."
  type        = string
  default     = null
}