#!/bin/bash

# Source environment variables from .env file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$(dirname "$SCRIPT_DIR")/.env"

if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
    echo "Loaded environment variables from .env"
else
    echo "ERROR: .env file not found at $ENV_FILE"
    exit 1
fi


vault secrets enable -path=secret kv-v2 2>/dev/null || true
vault secrets enable aws 2>/dev/null || true
vault write aws/config/root \
    access_key=$AWS_ACCESS_KEY_ID \
    secret_key=$AWS_SECRET_ACCESS_KEY \
    region="us-east-2"

vault write aws/roles/demo-role \
    credential_type=iam_user \
    policy_document=-<<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:*",
                "s3:*",
                "iam:*",
                "vpc:*"
            ],
            "Resource": "*"
        }
    ]
}
EOF

vault secrets tune \
  -default-lease-ttl=15m \
  -max-lease-ttl=20m \
  aws/

# Store HCP Terraform token (static)
vault kv put secret/ami-pipeline/hcp-terraform \
    token=$HCP_TERRAFORM_TOKEN

echo "✓ HCP Terraform token stored in Vault"
echo "  Path: secret/ami-pipeline/hcp-terraform"

vault kv put secret/ami-pipeline/github \
    token=$GITHUB_TOKEN

vault kv put secret/ami-pipeline/s3 \
    bucket_name=$S3_BUCKET_NAME \
    region=$AWS_REGION

vault kv put secret/ami-pipeline/aap \
  host=$aap_url \
  username=$aap_user \
  password=$aap_pwd

vault kv put secret/ami-pipeline/hcp-packer \
  client_id=$hcp_client_id \
  client_secret=$hcp_client_secret \
  organization_id=$hcp_organization_id \
  project_id=$hcp_project_id


vault kv patch secret/ami-pipeline/aap \
  job_template_id="7"

# Verify configurations
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "VAULT CONFIGURATION SUMMARY"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Static Secrets (KV v2):"
vault kv list secret/ami-pipeline/
echo ""
echo "Dynamic AWS Credentials:"
vault read aws/creds/demo-role
echo ""
echo "═══════════════════════════════════════════════════════════"
