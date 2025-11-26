variable "name" { type = string }
variable "namespace" { type = string }
variable "image" { type = string } # fixed to redis:7-alpine by caller
variable "service_port" { type = number }

variable "storage_gi" {
  type    = number
  default = 1
}

variable "labels" {
  type    = map(string)
  default = {}
}
