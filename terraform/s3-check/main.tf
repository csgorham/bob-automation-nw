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
      name = "ami-pipeline-s3-check"
    }
  }
}

# Read AWS credentials from Vault Dynamic Secrets
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

provider "vault" {
  address = var.vault_addr
  token   = var.vault_token
}

# ── Read S3 config from Vault ──────────────────────────────────────
data "vault_kv_secret_v2" "s3" {
  mount = "secret"
  name  = "ami-pipeline/s3"
}

data "external" "s3_check" {
  program = ["bash", "-c", <<-EOT
    set -eo pipefail

    bucket="${data.vault_kv_secret_v2.s3.data["bucket_name"]}"
    region="${var.aws_region}"
    access_key="${data.vault_aws_access_credentials.creds.access_key}"
    secret_key="${data.vault_aws_access_credentials.creds.secret_key}"
    session_token="${data.vault_aws_access_credentials.creds.security_token}"

    # Log to stderr (won't interfere with JSON output)
    echo "Checking bucket: $bucket in region: $region" >&2

    # Check if AWS CLI is available
    if ! command -v aws >/dev/null 2>&1; then
      echo "ERROR: AWS CLI not found" >&2
      printf '{"bucket_exists":"false","bucket_name":"%s","bucket_region":"%s","error":"aws_cli_not_found"}' "$bucket" "$region"
      exit 0
    fi

    # Try to check if bucket exists
    export AWS_ACCESS_KEY_ID="$access_key"
    export AWS_SECRET_ACCESS_KEY="$secret_key"
    export AWS_SESSION_TOKEN="$session_token"
    export AWS_DEFAULT_REGION="$region"

    if aws s3api head-bucket --bucket "$bucket" 2>&1 | tee /dev/stderr | grep -q "404\|NoSuchBucket"; then
      echo "Bucket does not exist (404)" >&2
      printf '{"bucket_exists":"false","bucket_name":"%s","bucket_region":"%s"}' "$bucket" "$region"
    elif aws s3api head-bucket --bucket "$bucket" >/dev/null 2>&1; then
      echo "Bucket exists!" >&2
      printf '{"bucket_exists":"true","bucket_name":"%s","bucket_region":"%s"}' "$bucket" "$region"
    else
      echo "Bucket check failed (permissions or other error)" >&2
      printf '{"bucket_exists":"false","bucket_name":"%s","bucket_region":"%s","error":"check_failed"}' "$bucket" "$region"
    fi
  EOT
  ]
}

# ── Outputs ───────────────────────────────────────────────────────
output "bucket_exists" {
  value       = data.external.s3_check.result["bucket_exists"] == "true"
  description = "Whether the S3 bucket exists"
}

output "bucket_name" {
  value       = nonsensitive(data.external.s3_check.result["bucket_name"])
  description = "The name of the bucket"
}

output "bucket_region" {
  value       = data.external.s3_check.result["bucket_region"]
  description = "The region of the bucket"
}
