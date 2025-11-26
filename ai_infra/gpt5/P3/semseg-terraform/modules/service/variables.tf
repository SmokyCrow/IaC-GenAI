variable "name"       { type = string }
variable "namespace"  { type = string }
variable "type"       { type = string } # "ClusterIP" or "NodePort"
variable "port"       { type = number } # Service port
variable "target_port"{ type = number } # Container port
variable "node_port" {
  type    = number
  default = null
}
