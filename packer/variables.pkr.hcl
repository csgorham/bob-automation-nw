variable "aws_region" {
  type    = string
  default = "us-east-2"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ami_name" {
  type    = string
  default = "hcp-ami-pipeline"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for Packer build instance"
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID for Packer build instance"
}

# HCP Packer Registry Variables
variable "hcp_bucket_name" {
  type        = string
  description = "HCP Packer Registry bucket name"
  default     = "hcp-ami-pipeline"
}

variable "version" {
  type        = string
  description = "Version number for the build (e.g., 1.0.0)"
  default     = "1.0.0"
}