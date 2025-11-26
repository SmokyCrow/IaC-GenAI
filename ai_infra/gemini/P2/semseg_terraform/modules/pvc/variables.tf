variable "name" {
  description = "The name of the PVC."
  type        = string
}

variable "namespace" {
  description = "The namespace for the PVC."
  type        = string
}

variable "storage_class_name" {
  description = "The storageClassName for the PVC."
  type        = string
}

variable "size" {
  description = "The size of the PVC (e.g., '64Mi')."
  type        = string
}

variable "wait_until_bound" {
  description = "Whether to wait for the PVC to be bound."
  type        = bool
  default     = false
}