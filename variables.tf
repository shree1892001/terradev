variable "server_ip" {
  description = "Server public IP or DNS name used for browser-facing service URLs. Use Elastic IP or domain in production."
  type        = string
}

variable "platform_dir" {
  description = "Base installation directory on the Linux server."
  type        = string
  default     = "/opt/redberyl-platform"
}

variable "enabled_stacks" {
  description = "Selection-based stack deployment. Supported values: devops, plane, huly."
  type        = list(string)
  default     = ["devops", "plane", "huly"]

  validation {
    condition     = length(var.enabled_stacks) > 0 && alltrue([for stack in var.enabled_stacks : contains(["devops", "plane", "huly"], stack)])
    error_message = "enabled_stacks must contain one or more supported stack names: devops, plane, huly."
  }
}

variable "force_redeploy" {
  description = "Change this value to force Terraform to re-run the bootstrap script."
  type        = string
  default     = ""
}
