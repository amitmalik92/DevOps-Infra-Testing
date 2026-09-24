variable "location" {
  type    = string
  default = "eastus"
}

variable "resource_group_name" {
  type    = string
  default = "rg-compute-prod"
}

variable "admin_password" {
  type      = string
  sensitive = true
}

variable "dcr_id" {
  type        = string
  description = "ID of the Data Collection Rule deployed in Stage 1"
}