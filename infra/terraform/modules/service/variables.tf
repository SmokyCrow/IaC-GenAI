variable "name" {
  type = string
}

variable "namespace" {
  type = string
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "selector" {
  type = map(string)
}

variable "port" {
  type = number
}

variable "target_port" {
  type = number
}

variable "type" {
  type    = string
  default = "ClusterIP"
}

variable "node_port" {
  type    = number
  default = null
}
