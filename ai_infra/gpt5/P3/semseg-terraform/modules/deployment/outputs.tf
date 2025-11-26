output "name" {
  value = kubernetes_deployment.this.metadata[0].name
}
