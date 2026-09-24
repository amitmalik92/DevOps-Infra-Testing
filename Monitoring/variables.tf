variable "location" {
  type    = string
  default = "eastus"
}

variable "resource_group_name" {
  type    = string
  default = "rg-monitoring-prod"
}

variable "action_group_email" {
  type        = string
  description = "Email address for alert notifications"
  default     = "admin@example.com"
}