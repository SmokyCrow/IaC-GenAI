variable "name" {
  description = "The name of the PVC."
  type        = string
}

variable "namespace" {
  description = "The namespace for the PVC."
  type        = string
}

variable "storage_class_name" {
  description = "The storage class to use."
  type        = string
}

variable "storage_size" {
  description = "The size of the PVC (e.g., '64Mi', '1Gi')."
  type        = string
}

variable "access_modes" {
  description = "A list of access modes for the PVC."
  type        = list(string)
  default     = ["ReadWriteOnce"]
}

variable "wait_until_bound" {
  description = "Whether to wait for the PVC to be bound before considering creation complete."
  type        = bool
  default     = false
}