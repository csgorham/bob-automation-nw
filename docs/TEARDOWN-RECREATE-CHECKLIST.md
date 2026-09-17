# Teardown & Recreate Checklist

<!-- Last known good state: Sep 16 2026 -->
<!-- EC2 Public IP: 3.138.118.64  Instance: i-0041a572bf405ea9a -->
<!-- SSH key path: ~/.ssh/ami-pipeline-key.pem -->

When you delete and recreate the Vault cluster (or any core infrastructure), run through this list **in order**. Each item is a step that does NOT survive a teardown and must be manually redone.

> **Quick reference:** Always `cd` to the project root and `source .env` first before running any command. The `.env` file must be at the project root (`bob-automation-nw/.env`), not inside a subdirectory.

---

## What Survives vs. What Resets

| Resource | Survives teardown? | Notes |
|---|---|---|
| AWS IAM user (`vault-admin-demo`) | ✅ Yes | Reuse existing access keys |
| AWS VPC / Subnet / Network | ❌ No | Destroyed with `terraform destroy` |
| HCP Terraform workspaces | ✅ Yes | State is wiped but workspace config stays |
| HCP Packer Registry | ✅ Yes | Buckets and AMIs persist — registry is project-level |
| HCP Packer AMI bucket (`hcp-ami-pipeline`) | ✅ Yes | Survives — no need to rebuild unless AMI is stale |
| HCP service principal (`packer-demo`) | ✅ Yes | Principal survives, but **keys must be regenerated** |
| Vault cluster | ❌ No | All secrets and engine config wiped |
| All `vault kv` secrets | ❌ No | Must be re-stored after new cluster is up |
| Vault AWS dynamic secrets engine | ❌ No | Must be reconfigured via `vault.sh` |
| EC2 instance + SSH key | ❌ No | Reprovisioned by `terraform apply` |

---

## Recreate Steps (Run In Order)

### Step 0 — Update .env with new token and address
After creating a new Vault cluster, update `.env` at the project root with the new values:

```bash
# Open .env and update these two lines:
export VAULT_ADDR="http://127.0.0.1:8200"        # or new HCP Vault cluster URL
export VAULT_TOKEN="hvs.XXXXXXXXXXXXXXXXXXXXXXXXXX"  # new root/admin token
```

All other `.env` variables that must be present for `vault.sh` to succeed:
```bash
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_REGION="us-east-2"
export GITHUB_TOKEN="ghp_..."
export HCP_TERRAFORM_TOKEN="..."
export S3_BUCKET_NAME="..."
export hcp_client_id="..."           # from Step 3 below
export hcp_client_secret="..."       # from Step 3 below
export hcp_organization_id="cgorham-org"
export hcp_project_id="44007ba7-a99a-4765-afa0-5373475b4714"
export aap_url="..."
export aap_user="..."
export aap_pwd="..."
```

Then source it:
```bash
cd /Users/carolinegorham/Desktop/Nationwide-Automation-Bob/bob-automation-nw
source .env
```

---

### Step 0b — Update Terraform variable set in HCP Terraform
The `vault_addr` and `vault_token` variables are passed at apply time, but if you have them stored as a **variable set** in HCP Terraform (`app.terraform.io` → `dev_space-cgh` org → **Variable sets**), update them there too so remote runs pick up the new values automatically.

1. Go to [https://app.terraform.io/app/dev_space-cgh/settings/varsets](https://app.terraform.io/app/dev_space-cgh/settings/varsets)
2. Find the variable set used by `ami-pipeline-ec2` and `ami-pipeline-network` workspaces
3. Update `vault_addr` and `vault_token` to the new values
4. Save

> Without this, `terraform apply` run remotely on HCP Terraform will use stale Vault credentials and fail to read any secrets.

---

### Step 1 — Start a new Vault cluster
```bash
# Option A: Local dev Vault (new terminal tab, keep it running)
vault server -dev

# Copy the Root Token printed in output, then in your .env:
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="hvs.XXXXXXXXXXXXXXXXXXXXXXXXXX"
```

---

### Step 2 — Re-run vault.sh to reconfigure Vault
This restores the AWS dynamic secrets engine and all KV secrets.
```bash
cd /path/to/bob-automation-nw
source .env
./.scripts/vault.sh
```

> ⚠️ Make sure `.env` has `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `VAULT_ADDR`, `VAULT_TOKEN`, `GITHUB_TOKEN`, `HCP_TERRAFORM_TOKEN`, `S3_BUCKET_NAME`, `hcp_client_id`, `hcp_client_secret`, `hcp_organization_id`, `hcp_project_id` filled in before running.

---

### Step 3 — Regenerate HCP service principal keys
The `packer-demo` service principal persists but its keys are invalidated.

1. Go to [https://portal.cloud.hashicorp.com](https://portal.cloud.hashicorp.com)
2. `default-project` → **Access control (IAM)** → **Service principals** → `packer-demo`
3. Click **Keys** in the left sidebar → **Generate key**
4. Copy `client_id` and `client_secret` immediately (shown once only)
5. Update your `.env`:
   ```bash
   export hcp_client_id="<new client_id>"
   export hcp_client_secret="<new client_secret>"
   ```
6. Re-store in Vault:
   ```bash
   vault kv put secret/ami-pipeline/hcp-packer \
     client_id="<new client_id>" \
     client_secret="<new client_secret>" \
     organization_id="cgorham-org" \
     project_id="44007ba7-a99a-4765-afa0-5373475b4714"
   ```

---

### Step 4 — Apply Terraform network module
Recreates VPC, subnet, and writes network config back to Vault automatically.
```bash
cd terraform/network
source .env
terraform apply \
  -var="vault_addr=$VAULT_ADDR" \
  -var="vault_token=$VAULT_TOKEN"
```

> This automatically writes `secret/ami-pipeline/network` (vpc_id + subnet_id) to Vault on success.

---

### Step 5 — Run Packer build (only if AMI is gone or stale)
The HCP Packer Registry and `hcp-ami-pipeline` bucket **survive** teardown.
Only redo this if you destroyed the AMI or need a fresh build.

```bash
cd /path/to/bob-automation-nw
source .env
export HCP_CLIENT_ID="$hcp_client_id"
export HCP_CLIENT_SECRET="$hcp_client_secret"
export PKR_VAR_vpc_id="<vpc_id from Step 4 output>"
export PKR_VAR_subnet_id="<subnet_id from Step 4 output>"

cd packer
./build-with-hcp.sh
```

After the build completes (~5-10 min), assign the new version to the **production** channel in the HCP portal:
- HCP Portal → Packer → `hcp-ami-pipeline` → **Channels** → `production` → assign latest version

---

### Step 6 — Apply Terraform EC2 module
```bash
cd terraform/ec2
source .env
terraform apply \
  -var="vault_addr=$VAULT_ADDR" \
  -var="vault_token=$VAULT_TOKEN"
```

After apply completes:
```bash
terraform output instance_public_ips
```

---

### Step 7 — Verify everything is connected
```bash
# Vault is up and AWS dynamic creds work
vault read aws/creds/demo-role

# Network secret was written
vault kv get secret/ami-pipeline/network

# HCP Packer secret is correct (no surrounding quotes on values)
vault kv get secret/ami-pipeline/hcp-packer

# EC2 instance IP
cd terraform/ec2 && terraform output instance_public_ips
```

---

## Common Errors & Fixes

| Error | Cause | Fix |
|---|---|---|
| `no secret found at secret/data/ami-pipeline/network` | Network module not applied yet | Run Step 4 |
| `unable to create HCP api client: unauthorized` | Stale or quoted HCP keys in Vault | Run Step 3 |
| `bucket hcp-ami-pipeline does not exist` | HCP Packer Registry not activated | Go to HCP Portal → Packer → Activate, then Step 5 |
| `could not read state version outputs: resource not found` | Terraform module never applied | Run the relevant apply step |
| `No value found at secret/data/ami-pipeline/aws-creds` | Not an issue — EC2 uses dynamic creds, not this path | Safe to ignore |
| Values in `vault kv get` show with surrounding `"` quotes | Stored with literal quote characters | Re-run `vault kv put` without quotes in values |
