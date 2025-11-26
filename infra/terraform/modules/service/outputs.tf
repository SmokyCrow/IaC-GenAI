output "name" {
  value = kubernetes_service.this.metadata[0].name
}
