variable "name" {
  description = "Name of the PVC"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
}

variable "storage" {
  description = "Storage size (e.g., 64Mi, 1Gi)"
  type        = string
}

variable "storage_class_name" {
  description = "Storage class name"
  type        = string
}

variable "access_modes" {
  description = "Access modes for the PVC"
  type        = list(string)
  default     = ["ReadWriteOnce"]
}

variable "wait_until_bound" {
  description = "Wait until PVC is bound"
  type        = bool
  default     = false
}
