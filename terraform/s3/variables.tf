variable "vault_addr" {
  type        = string
  description = "Vault server address"
}

variable "vault_token" {
  type        = string
  sensitive   = true
  description = "Vault authentication token"
}

variable "aws_region" {
  type        = string
  description = "AWS region for the S3 bucket"
  default     = "us-east-1"
}

variable "environment" {
  type        = string
  description = "Environment name (dev, prod, staging, etc.)"
  default     = "dev"
}

variable "owner" {
  type        = string
  description = "Owner tag for all resources"
  default     = "platform-team"
}

variable "cost_center" {
  type        = string
  description = "Cost center tag for billing"
  default     = "cc-demo"
}

variable "business_unit" {
  type        = string
  description = "Business unit tag"
  default     = "engineering"
}
