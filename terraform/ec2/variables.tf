variable "vault_addr" {
  type        = string
  description = "Vault server address"
}

variable "vault_token" {
  type        = string
  sensitive   = true
  description = "Vault authentication token"
}

# HCP Packer Registry Variables
variable "hcp_bucket_name" {
  type        = string
  description = "HCP Packer Registry bucket name"
  default     = "hcp-ami-pipeline"
}

# Single instance configuration variable
# All *.auto.tfvars files will set this same variable
# Terraform Cloud workspace will determine which file is used
variable "instance_config" {
  type = object({
    instance_type    = string
    aws_region       = string
    hcp_channel_name = string
    cost_center      = string
    project          = string
    environment      = string
    owner            = string
    business_unit    = string
    ingress_ports = list(object({
      port        = number
      description = string
    }))
  })
  description = "EC2 instance configuration for the current environment"
}

# Environment name - used for resource naming
variable "environment_name" {
  type        = string
  description = "Name of the environment (dev, prod, staging, etc.)"
}
