variable "name" {
  type = string
}

variable "namespace" {
  type = string
}

variable "storage" {
  type = string
}

variable "access_modes" {
  type    = list(string)
  default = ["ReadWriteOnce"]
}

variable "storage_class_name" {
  description = "StorageClass to use for the PVC. On k3s, the default is 'local-path'."
  type        = string
  default     = "local-path"
}

variable "volume_binding_mode" {
  description = "VolumeBindingMode of the backing StorageClass: 'Immediate' or 'WaitForFirstConsumer'. Used to decide whether to wait for binding."
  type        = string
  default     = "Immediate"
}

