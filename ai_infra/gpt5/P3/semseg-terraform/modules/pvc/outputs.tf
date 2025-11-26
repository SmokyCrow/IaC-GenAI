output "name" {
  value = kubernetes_persistent_volume_claim.this.metadata[0].name
}
