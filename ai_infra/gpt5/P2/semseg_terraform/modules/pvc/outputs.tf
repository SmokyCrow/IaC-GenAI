output "claim_name" {
  description = "The name of the created PersistentVolumeClaim"
  value       = kubernetes_persistent_volume_claim.this.metadata[0].name
}
