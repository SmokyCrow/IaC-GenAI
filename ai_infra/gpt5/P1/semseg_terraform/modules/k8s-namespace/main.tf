variable "name" {
  type        = string
  description = "Namespace name"
}

variable "create" {
  type        = bool
  default     = true
  description = "Whether to create the namespace"
}

resource "kubernetes_namespace" "this" {
  count = var.create ? 1 : 0
  metadata {
    name = var.name
  }
}

output "name" {
  value = var.create ? kubernetes_namespace.this[0].metadata[0].name : var.name
}
