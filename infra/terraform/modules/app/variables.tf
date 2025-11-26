variable "namespace" {
  type = string
}

variable "image_repo" {
  type = string
}

variable "ingest_image" {
  type = string
}

variable "node_port_base" {
  type = number
}

variable "pvc_storage_class_name" {
  description = "StorageClass to use for PVCs (k3s: local-path, Docker Desktop: hostpath)."
  type        = string
  default     = "local-path"
}

variable "pvc_volume_binding_mode" {
  description = "Volume binding mode hint for PVC behavior: 'Immediate' for Docker Desktop, 'WaitForFirstConsumer' for k3s. Propagated to PVC modules to control wait_until_bound."
  type        = string
  default     = "Immediate"
}
