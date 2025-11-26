variable "kubeconfig_path" {
  description = "Path to kubeconfig for the k3s cluster"
  type        = string
  default     = "~/.kube/config"
}

variable "namespace" {
  description = "Target Kubernetes namespace"
  type        = string
  default     = "semseg"
}

# Images
variable "shared_image" {
  description = "Container image for workers and web UIs (qa-web, results-api, convert-ply, part-labeler, redactor, analytics)"
  type        = string
}

variable "ingest_image" {
  description = "Container image for the ingest-api service"
  type        = string
}

# Optional image pull policy (e.g., Always during dev)
variable "image_pull_policy" {
  description = "Image pull policy for containers"
  type        = string
  default     = "IfNotPresent"
}

variable "sub_pc_frames_size_gi" {
  description = "Size for /sub-pc-frames PVC"
  type        = number
  default     = 1
}

variable "pc_frames_size_gi" {
  description = "Size for /pc-frames PVC"
  type        = number
  default     = 1
}

variable "segments_size_gi" {
  description = "Size for /segments PVC"
  type        = number
  default     = 2
}
