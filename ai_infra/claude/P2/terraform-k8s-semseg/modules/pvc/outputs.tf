output "name" {
  description = "Name of the PVC"
  value       = kubernetes_persistent_volume_claim.this.metadata[0].name
}

output "namespace" {
  description = "Namespace of the PVC"
  value       = kubernetes_persistent_volume_claim.this.metadata[0].namespace
}
