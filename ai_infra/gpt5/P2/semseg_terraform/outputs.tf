output "ingest_api_url" {
  description = "NodePort URL for ingest-api"
  value       = "http://${var.node_ip}:30080"
}

output "results_api_url" {
  description = "NodePort URL for results-api"
  value       = "http://${var.node_ip}:30081"
}

output "qa_web_url" {
  description = "NodePort URL for qa-web"
  value       = "http://${var.node_ip}:30082"
}
