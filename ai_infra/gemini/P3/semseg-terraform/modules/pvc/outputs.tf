output "pvc_name" {
  description = "The name of the created PVC."
  value       = kubernetes_persistent_volume_claim.pvc.metadata[0].name
}