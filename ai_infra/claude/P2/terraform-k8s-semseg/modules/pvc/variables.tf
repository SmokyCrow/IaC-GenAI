variable "name" {
  description = "Name of the PVC"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
}

variable "storage_class" {
  description = "Storage class name"
  type        = string
}

variable "storage_size" {
  description = "Size of the storage"
  type        = string
}

variable "wait_until_bound" {
  description = "Wait until PVC is bound"
  type        = bool
  default     = false
}
