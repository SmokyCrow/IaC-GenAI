variable "name"                  { type = string }
variable "namespace"             { type = string }
variable "storage_class_name"    { type = string }
variable "size"                  { type = string } # e.g., "64Mi"
variable "access_modes" {
  type    = list(string)
  default = ["ReadWriteOnce"]
}
