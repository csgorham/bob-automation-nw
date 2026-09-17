terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.0"
    }
  }

  cloud {
    organization = "dev_space-cgh"
    workspaces {
      name = "ami-pipeline-s3"
    }
  }
}

# ── Vault Provider ─────────────────────────────────────────────────
provider "vault" {
  address = var.vault_addr
  token   = var.vault_token
}

# ── Dynamic AWS Credentials from Vault ────────────────────────────
data "vault_aws_access_credentials" "creds" {
  backend = "aws"
  role    = "demo-role"
}

provider "aws" {
  region     = var.aws_region
  access_key = data.vault_aws_access_credentials.creds.access_key
  secret_key = data.vault_aws_access_credentials.creds.secret_key
  token      = data.vault_aws_access_credentials.creds.security_token
}

# ── S3 Config from Vault ───────────────────────────────────────────
data "vault_kv_secret_v2" "s3" {
  mount = "secret"
  name  = "ami-pipeline/s3"
}

# ── S3 Bucket ─────────────────────────────────────────────────────
resource "aws_s3_bucket" "packer_artifacts" {
  bucket = data.vault_kv_secret_v2.s3.data["bucket_name"]

  tags = {
    Name         = data.vault_kv_secret_v2.s3.data["bucket_name"]
    Project      = "ami-pipeline"
    Environment  = var.environment
    ManagedBy    = "terraform"
    Owner        = var.owner
    CostCenter   = var.cost_center
    BusinessUnit = var.business_unit
  }
}

# ── Block all public access ────────────────────────────────────────
resource "aws_s3_bucket_public_access_block" "packer_artifacts" {
  bucket = aws_s3_bucket.packer_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── Server-side encryption (AES-256) ──────────────────────────────
#
# enforce-s3-encryption Sentinel policy requires SSE to be enabled.
# This resource satisfies that policy check.
#
resource "aws_s3_bucket_server_side_encryption_configuration" "packer_artifacts" {
  bucket = aws_s3_bucket.packer_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ── Versioning ─────────────────────────────────────────────────────
resource "aws_s3_bucket_versioning" "packer_artifacts" {
  bucket = aws_s3_bucket.packer_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ── Outputs ────────────────────────────────────────────────────────
output "bucket_name" {
  value       = aws_s3_bucket.packer_artifacts.id
  description = "S3 bucket name for Packer artifacts"
}

output "bucket_arn" {
  value       = aws_s3_bucket.packer_artifacts.arn
  description = "S3 bucket ARN"
}

output "bucket_region" {
  value       = aws_s3_bucket.packer_artifacts.region
  description = "Region where the bucket was created"
}
