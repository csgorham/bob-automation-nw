variable "aws_region" {
  type        = string
  default     = "us-east-2"
  description = "AWS region"
}

variable "vault_addr" {
  type        = string
  description = "Vault server address"
}

variable "vault_token" {
  type        = string
  sensitive   = true
  description = "Vault authentication token"
}
