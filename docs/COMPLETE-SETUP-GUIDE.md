# Complete Setup Guide — Golden Workflow Demo

> End-to-end setup from zero to a live demo. Follow steps in order.

---

## Prerequisites

| Tool | Minimum Version | Check |
|------|----------------|-------|
| Terraform | 1.6+ | `terraform version` |
| Sentinel CLI | 0.22+ | `sentinel version` |
| Packer | 1.10+ | `packer version` |
| Ansible | 2.14+ | `ansible --version` |
| Vault CLI | 1.15+ | `vault version` |
| AWS CLI | 2.x | `aws --version` |
| Git | 2.x | `git --version` |
| jq | 1.6+ | `jq --version` |

---

## Step 1 — Clone the Repository

```bash
git clone https://github.com/csgorham/bob-automation-nw.git
cd bob-automation-nw
```

---

## Step 2 — Configure Environment Variables

```bash
cp .env.example .env
```

Edit `.env` and fill in all required values:

```bash
# Vault
VAULT_ADDR=https://your-vault-addr:8200
VAULT_TOKEN=your-vault-token

# AWS (used for local CLI operations only; Terraform uses Vault dynamic creds)
AWS_DEFAULT_REGION=us-east-1

# SSH key for Ansible
SSH_KEY_PATH=~/.ssh/your-key.pem

# HCP Terraform
HCP_TERRAFORM_TOKEN=your-hcp-terraform-token

# HCP Packer (stored in Vault; also needed for .env for local packer builds)
HCP_CLIENT_ID=your-hcp-client-id
HCP_CLIENT_SECRET=your-hcp-client-secret
HCP_ORGANIZATION_ID=your-hcp-org-id
HCP_PROJECT_ID=your-hcp-project-id

# GitHub
# Create at: github.com → Settings → Developer settings → Personal access tokens → Tokens (classic)
# Required scopes: repo (full), workflow
GITHUB_TOKEN=your-github-token
```

Source the file:
```bash
source .env
```

---

## Step 3 — Set Up Vault

### 3a. Enable the AWS secrets engine

```bash
vault secrets enable aws
vault write aws/config/root \
  access_key=$AWS_ACCESS_KEY_ID \
  secret_key=$AWS_SECRET_ACCESS_KEY \
  region=us-east-1

vault write aws/roles/demo-role \
  credential_type=iam_user \
  policy_arns=arn:aws:iam::aws:policy/PowerUserAccess
```

### 3b. Store HCP Packer credentials

```bash
vault kv put secret/ami-pipeline/hcp-packer \
  hcp_client_id=$HCP_CLIENT_ID \
  hcp_client_secret=$HCP_CLIENT_SECRET \
  hcp_organization_id=$HCP_ORGANIZATION_ID \
  hcp_project_id=$HCP_PROJECT_ID
```

### 3c. Store S3 config

```bash
vault kv put secret/ami-pipeline/s3 \
  bucket_name=ami-pipeline-artifacts-$(aws sts get-caller-identity --query Account --output text)
```

### 3d. Store HCP Terraform token

```bash
vault kv put secret/ami-pipeline/hcp-terraform \
  token=$HCP_TERRAFORM_TOKEN
```

### 3e. Store GitHub token

```bash
vault kv put secret/ami-pipeline/github \
  token=$GITHUB_TOKEN
```

> The Harness pipeline reads this at runtime for repo clones and PR comments.
> Required scopes: **repo** (full), **workflow**.

### 3f. Verify

```bash
vault kv get secret/ami-pipeline/hcp-packer
vault kv get secret/ami-pipeline/s3
vault kv get secret/ami-pipeline/hcp-terraform
vault kv get secret/ami-pipeline/github
```

---

## Step 4 — Configure HCP Terraform Workspaces

Log in to [app.terraform.io](https://app.terraform.io) under the `dev_space-cgh` organization and confirm these workspaces exist:

| Workspace | ID | Module |
|-----------|-----|--------|
| `ami-pipeline-s3-check` | `ws-cXnGs9Q6vwxcNheL` | `terraform/s3-check` |
| `ami-pipeline-s3` | `ws-uGtV1DEBnULDJwzf` | `terraform/s3` |
| `ami-pipeline-network` | `ws-knQbRVQxeyzbWcwj` | `terraform/network` |
| `ami-pipeline-ec2` | `ws-i7ApJ9RdDPvvEQVd` | `terraform/ec2` |

For each workspace, set these environment variables (Sensitive):
- `VAULT_ADDR` — your Vault address
- `VAULT_TOKEN` — your Vault token
- `TFE_TOKEN` — your HCP Terraform token (for remote state reads)

---

## Step 5 — Configure HCP Packer Registry

1. Log in to [portal.cloud.hashicorp.com](https://portal.cloud.hashicorp.com)
2. Navigate to Packer → Registries
3. Create a bucket named `hcp-ami-pipeline` (or match `hcp_bucket_name` in `terraform/ec2/variables.tf`)
4. Create a channel named `dev` pointing to the latest iteration

---

## Step 6 — Validate Packer Template

```bash
cd packer
export HCP_CLIENT_ID=$HCP_CLIENT_ID
export HCP_CLIENT_SECRET=$HCP_CLIENT_SECRET
packer validate -var-file=variables.pkr.hcl ami.pkr.hcl
```

---

## Step 7 — Build the Base AMI

```bash
cd packer
./build-with-hcp.sh
```

This builds the AMI, pushes it to HCP Packer Registry, and creates a manifest at `packer/manifest.json`.

---

## Step 8 — Run Sentinel Tests

```bash
cd sentinel
sentinel test
```

All three policies (`require-tags`, `restrict-instance-types`, `enforce-s3-encryption`) must return **PASS** before proceeding.

---

## Step 9 — Run the Preflight Check

```bash
./.scripts/demo-preflight.sh
```

This verifies:
- All required tools are installed
- Vault is reachable and unsealed
- AWS credentials resolve via Vault dynamic secrets
- HCP Packer registry is accessible
- All four Terraform workspaces are reachable

---

## Step 10 — Provision Infrastructure

Run in order:

```bash
# S3 (if bucket doesn't exist yet)
cd terraform/s3 && terraform init
terraform apply -auto-approve \
  -var-file=dev.auto.tfvars \
  -var="vault_addr=$VAULT_ADDR" \
  -var="vault_token=$VAULT_TOKEN"

# Network
cd ../network && terraform init
terraform apply -auto-approve \
  -var-file=dev.auto.tfvars \
  -var="vault_addr=$VAULT_ADDR" \
  -var="vault_token=$VAULT_TOKEN"

# EC2
cd ../ec2 && terraform init
terraform apply -auto-approve \
  -var-file=dev.auto.tfvars \
  -var="vault_addr=$VAULT_ADDR" \
  -var="vault_token=$VAULT_TOKEN"

export EC2_IP=$(terraform output -raw public_ip)
```

---

## Step 11 — Configure GitHub Repository

### 11a. Set GitHub Actions secrets

In `github.com/csgorham/bob-automation-nw` → Settings → Secrets and variables → Actions:

| Secret | Value |
|--------|-------|
| `VAULT_ADDR` | Your Vault address |
| `VAULT_TOKEN` | Your Vault token |
| `AWS_DEFAULT_REGION` | `us-east-1` |

### 11b. Set Up Harness Pipeline (Tier 4)

> Skip this step if you are only running Tier 1–3 of the demo.

**Prerequisites:**
- A Harness account at [app.harness.io](https://app.harness.io)
- A Harness Delegate running in your environment (Docker or Kubernetes)

**Steps:**

1. **Import the pipeline:**
   - In Harness, go to your project → Pipelines → Import from Git
   - Repository: `https://github.com/csgorham/bob-automation-nw`
   - Branch: `main`
   - File: `harness-pipeline.yaml`

2. **Add Harness secrets** (Project → Secrets):

   | Secret ID | Value |
   |-----------|-------|
   | `vault_addr` | Your Vault address |
   | `vault_token` | Your Vault token |
   | `ssh_key` | Contents of your EC2 SSH private key |

3. **Add GitHub Actions secret for Harness trigger:**

   In `github.com/csgorham/bob-automation-nw` → Settings → Secrets:
   
   | Secret | Value |
   |--------|-------|
   | `HARNESS_API_KEY` | Your Harness API key (Account → Access Control → API Keys) |
   | `HARNESS_ACCOUNT_ID` | Your Harness account ID |
   | `HARNESS_ORG_ID` | `default` (or your org identifier) |
   | `HARNESS_PROJECT_ID` | `amipipeline` |

4. **Verify trigger:** Merge a change to `main` → confirm `.github/workflows/harness-trigger.yml` fires and the pipeline starts in Harness UI.

---

## Step 12 — Verify Demo Readiness

Run the full preflight one more time and confirm all checks pass:

```bash
./.scripts/demo-preflight.sh
```

Then open Bob, switch to **Infra Architect** mode, and follow [`DEMO-WALKTHROUGH.md`](../DEMO-WALKTHROUGH.md).

---

## Teardown

See [`docs/TEARDOWN-RECREATE-CHECKLIST.md`](TEARDOWN-RECREATE-CHECKLIST.md) for the full teardown and recreation procedure.

To destroy all provisioned infrastructure:

```bash
# EC2 first (depends on network)
cd terraform/ec2 && terraform destroy -auto-approve \
  -var-file=dev.auto.tfvars \
  -var="vault_addr=$VAULT_ADDR" \
  -var="vault_token=$VAULT_TOKEN"

# Network
cd ../network && terraform destroy -auto-approve \
  -var-file=dev.auto.tfvars \
  -var="vault_addr=$VAULT_ADDR" \
  -var="vault_token=$VAULT_TOKEN"

# S3 (only if you want to delete the bucket)
cd ../s3 && terraform destroy -auto-approve \
  -var-file=dev.auto.tfvars \
  -var="vault_addr=$VAULT_ADDR" \
  -var="vault_token=$VAULT_TOKEN"
```

---

## Quick Reference

| What | Command |
|------|---------|
| Check Vault | `vault status` |
| Source env | `source .env` |
| Preflight | `./.scripts/demo-preflight.sh` |
| Sentinel tests | `cd sentinel && sentinel test` |
| Validate Packer | `cd packer && packer validate -var-file=variables.pkr.hcl ami.pkr.hcl` |
| Get EC2 IP | `cd terraform/ec2 && terraform output -raw public_ip` |
| Run drift detection | `cd ansible && ansible-playbook drift-detection.yaml -i "$EC2_IP," --private-key="$SSH_KEY_PATH" -u ec2-user` |
