variable "kubeconfig" {
  description = "Path to kubeconfig for the target cluster"
  type        = string
  default     = "~/.kube/config"
}

variable "namespace" {
  description = "Target Kubernetes namespace"
  type        = string
  default     = "semseg"
}

variable "image_repo" {
  description = "Docker image repository for app services (local Docker Desktop tag)"
  type        = string
  default     = "semantic-segmenter:latest"
}

variable "ingest_image" {
  description = "Docker image for ingest API"
  type        = string
  default     = "ingest-api:latest"
}

variable "node_port_base" {
  description = "Base NodePort for services (80->30080, 81->30081, 82->30082)"
  type        = number
  default     = 30080
}

variable "pvc_storage_class_name" {
  description = "StorageClass to use for PVCs (k3s: local-path, Docker Desktop: hostpath)."
  type        = string
  default     = "local-path"
}

variable "pvc_volume_binding_mode" {
  description = "Volume binding mode hint for PVC behavior: set to 'Immediate' on Docker Desktop, 'WaitForFirstConsumer' on k3s. Used to toggle wait_until_bound to avoid deadlocks."
  type        = string
  default     = "Immediate"
  validation {
    condition     = contains(["Immediate", "WaitForFirstConsumer"], var.pvc_volume_binding_mode)
    error_message = "pvc_volume_binding_mode must be either 'Immediate' or 'WaitForFirstConsumer'."
  }
}
