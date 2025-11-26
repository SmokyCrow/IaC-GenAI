variable "kubeconfig" {
  description = "Optional path to the kubeconfig file. If not set, the provider will use default resolution (e.g., KUBECONFIG env var, ~/.kube/config, %USERPROFILE%\\.kube\\config)."
  type        = string
  default     = "~/.kube/config"
}

variable "ingest_image" {
  description = "Docker image for the ingest-api."
  type        = string
  default     = "ingest-api:latest"
}

variable "shared_image" {
  description = "Shared Docker image for web UIs and workers."
  type        = string
  default     = "semantic-segmenter:latest"
}

variable "redis_image" {
  description = "Docker image for Redis."
  type        = string
  default     = "redis:7-alpine"
}

# --- Persistent Storage Variables ---

variable "storage_sub_pc_frames" {
  description = "Storage size for the /sub-pc-frames volume."
  type        = string
  default     = "2Gi"
}

variable "storage_pc_frames" {
  description = "Storage size for the /pc-frames volume."
  type        = string
  default     = "2Gi"
}

variable "storage_segments" {
  description = "Storage size for the /segments volume."
  type        = string
  default     = "2Gi"
}

variable "storage_redis" {
  description = "Storage size for the Redis data volume."
  type        = string
  default     = "2Gi"
}

# --- Redis Stream and Group Variables (Updated) ---

variable "redis_stream_frames_converted" {
  description = "Redis stream name for converted frames."
  type        = string
  default     = "s_frames_converted"
}

variable "redis_stream_parts_labeled" {
  description = "Redis stream name for labeled parts."
  type        = string
  default     = "s_parts_labeled"
}

variable "redis_stream_redacted_done" {
  description = "Redis stream name for completed redactions."
  type        = string
  default     = "s_redacted_done"
}

variable "redis_stream_analytics_done" {
  description = "Redis stream name for completed analytics."
  type        = string
  default     = "s_analytics_done"
}

variable "redis_group_part_labeler" {
  description = "Redis group name for the part-labeler."
  type        = string
  default     = "g_part_labeler"
}

variable "redis_group_redactor" {
  description = "Redis group name for the redactor."
  type        = string
  default     = "g_redactor"
}

variable "redis_group_analytics" {
  description = "Redis group name for the analytics worker."
  type        = string
  default     = "g_analytics"
}