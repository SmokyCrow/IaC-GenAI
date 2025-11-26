# These variables simply receive and pass through the root variables.

variable "namespace" {
  description = "The Kubernetes namespace."
  type        = string
}

variable "image_repo" {
  description = "The main application image."
  type        = string
}

variable "ingest_image" {
  description = "The image for the ingest-api service."
  type        = string
}

variable "node_port_base" {
  description = "The base NodePort number."
  type        = number
}

variable "pvc_storage_class_name" {
  description = "The storage class name for all PVCs."
  type        = string
}