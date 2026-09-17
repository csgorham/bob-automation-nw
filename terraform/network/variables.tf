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
  description = "AWS region for network resources"
  default     = "us-east-1"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  type        = string
  description = "CIDR block for the public subnet"
  default     = "10.0.1.0/24"
}

variable "availability_zone" {
  type        = string
  description = "AWS availability zone for the public subnet"
  default     = "us-east-1a"
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
