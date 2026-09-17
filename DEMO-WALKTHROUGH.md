# Demo Walkthrough — Golden Workflow with IBM Bob

> **Audience:** Demo presenter  
> **Modes used:** Infra Architect → Policy Auditor → Platform SRE  
> **Time:** ~30 min end-to-end (Tiers 1–3); ~45 min with Harness pipeline (Tier 4)

---

## Before You Start

1. Run the preflight check:
   ```bash
   ./.scripts/demo-preflight.sh
   ```
2. Source your environment:
   ```bash
   source .env
   ```
3. Verify Vault is reachable:
   ```bash
   vault status
   ```
4. Open Bob → switch to **Infra Architect** mode to begin.

---

## Stage 1 — Day 0: Architecture & Scaffolding (Infra Architect)

**Mode:** Infra Architect (read-only; no execution tools)

**Goal:** Show that Bob understands the full workspace layout and can explain architectural decisions before a single line of infrastructure is provisioned.

### 1a. Activate the orchestrator skill

Ask Bob:
> *"Activate the infra automation orchestrator skill and walk me through the Golden Workflow."*

Bob will load `.bob/skills/infra-automation-orchestrator/SKILL.md` and provide a full stage-by-stage overview.

### 1b. Architecture question — module decoupling

Ask Bob:
> *"How are the network, S3, and EC2 modules decoupled? How does the EC2 module get its VPC and subnet IDs?"*

**What to point out:**
- Three independent HCP Terraform workspaces — `ami-pipeline-network`, `ami-pipeline-s3`, `ami-pipeline-ec2`
- EC2 workspace reads VPC/subnet via `data "terraform_remote_state" "network"` — no hardcoded IDs
- S3 bucket name is never hardcoded — it comes from Vault KV at `secret/ami-pipeline/s3`
- Bob cites the actual source files ([`terraform/ec2/main.tf`](terraform/ec2/main.tf), [`terraform/network/main.tf`](terraform/network/main.tf))

### 1c. Port catalog walkthrough

Ask Bob:
> *"What ports are currently approved for the dev environment? Walk me through the catalog."*

Bob reads [`terraform/ec2/ports.yaml`](terraform/ec2/ports.yaml) and lists all entries with their `risk_level` and `allowed_environments`. Point out:
- SSH (port 22) is `risk_level: high` and `requires_justification: true`
- Port 9090 (Prometheus) defaults to a restricted `10.0.0.0/8` CIDR
- No port can be added to a `*.auto.tfvars` without a catalog entry here

### 1d. Add a port request (live mutation demo)

Ask Bob:
> *"Add port 8083 to the dev environment."*

Bob:
1. Looks up port 8083 in the catalog — it exists, risk is `medium`, `dev` is allowed
2. Edits [`terraform/ec2/dev.auto.tfvars`](terraform/ec2/dev.auto.tfvars) to append the entry
3. Shows the diff

**Talking point:** Bob never opens a port not in the catalog. Try asking for port 5432 (PostgreSQL) — it's not in the catalog, so Bob refuses and explains why.

---

## Stage 2 — Day 1 Pre-Flight: Policy & Compliance (Policy Auditor)

**Mode:** Switch to **Policy Auditor**

> *"Switch to Policy Auditor mode."*

**Goal:** Demonstrate pre-commit compliance checking against all three Sentinel policies before any infrastructure is provisioned.

### 2a. Activate the sentinel-audit skill

Ask Bob:
> *"Activate the sentinel audit skill and run a compliance check on our current Terraform plan."*

Bob loads `.bob/skills/sentinel-audit/SKILL.md` and walks through all three policies:

| Policy | File | What it checks |
|--------|------|----------------|
| `require-tags` | `sentinel/require-tags.sentinel` | All resources have Name, Environment, Owner, CostCenter, Project, BusinessUnit |
| `restrict-instance-types` | `sentinel/restrict-instance-types.sentinel` | Only `t3.micro`, `t3.small`, `t3.medium`, `t2.micro` allowed |
| `enforce-s3-encryption` | `sentinel/enforce-s3-encryption.sentinel` | S3 buckets must have SSE enabled |

### 2b. Run Sentinel tests locally

```bash
cd sentinel && sentinel test
```

All three policies should return **PASS**. Bob will explain each result.

### 2c. Show a deliberate policy failure

Ask Bob:
> *"What would happen if I tried to use a `c5.xlarge` instance type?"*

Bob reads `sentinel/restrict-instance-types.sentinel` and explains the exact policy check that would block it, and which mock file demonstrates the fail case.

### 2d. Vault credential audit

Ask Bob:
> *"Audit our Vault credential configuration. Are we following least privilege?"*

Bob reviews:
- `data "vault_aws_access_credentials"` — dynamic, short-lived AWS creds via `demo-role`
- `data "vault_kv_secret_v2" "hcp_packer"` — HCP credentials pulled at plan time, never in state
- `vault_token` variable is marked `sensitive = true` across all modules

**Talking point:** No long-lived AWS keys anywhere in the codebase — Vault issues them dynamically per plan/apply run.

---

## Stage 3 — Day 1 Provisioning (Platform SRE)

**Mode:** Switch to **Platform SRE**

> *"Switch to Platform SRE mode."*

**Goal:** Execute the full provisioning stack — S3 → Network → EC2 — using Bob to orchestrate the commands.

### 3a. Check S3 bucket existence

Ask Bob:
> *"Check whether the S3 bucket exists before we provision."*

```bash
cd terraform/s3-check && terraform init
terraform plan -var="vault_addr=$VAULT_ADDR" -var="vault_token=$VAULT_TOKEN"
```

Bob will read the `bucket_exists` output and tell you whether to proceed to the S3 provisioning step or skip it.

### 3b. Provision S3 (if needed)

```bash
cd terraform/s3 && terraform init
terraform plan -var-file=dev.auto.tfvars -var="vault_addr=$VAULT_ADDR" -var="vault_token=$VAULT_TOKEN"
terraform apply -auto-approve -var-file=dev.auto.tfvars -var="vault_addr=$VAULT_ADDR" -var="vault_token=$VAULT_TOKEN"
```

**Talking point:** The bucket name comes from Vault — Bob never sees a hardcoded bucket name.

### 3c. Provision Network

```bash
cd terraform/network && terraform init
terraform plan -var-file=dev.auto.tfvars -var="vault_addr=$VAULT_ADDR" -var="vault_token=$VAULT_TOKEN"
terraform apply -auto-approve -var-file=dev.auto.tfvars -var="vault_addr=$VAULT_ADDR" -var="vault_token=$VAULT_TOKEN"
```

### 3d. Provision EC2

Ask Bob:
> *"Run the EC2 Terraform plan and tell me what it's going to create."*

```bash
cd terraform/ec2 && terraform init
terraform plan -var-file=dev.auto.tfvars -var="vault_addr=$VAULT_ADDR" -var="vault_token=$VAULT_TOKEN"
```

Bob reads the plan output and summarises:
- AMI resolved from HCP Packer channel
- Security group ingress rules dynamically derived from `ingress_ports` in `dev.auto.tfvars`
- VPC/subnet pulled from remote state (network workspace)
- All resources tagged per Sentinel `require-tags` policy

```bash
terraform apply -auto-approve -var-file=dev.auto.tfvars -var="vault_addr=$VAULT_ADDR" -var="vault_token=$VAULT_TOKEN"
```

Capture the public IP:
```bash
export EC2_IP=$(terraform output -raw public_ip)
echo "Instance is at: $EC2_IP"
```

---

## Stage 4 — Day 2: Drift Detection & Remediation (Platform SRE)

**Mode:** Remains **Platform SRE**

**Goal:** Simulate configuration drift, detect it with Ansible, and trigger self-healing.

### 4a. Activate the drift-remediation skill

Ask Bob:
> *"Activate the drift remediation skill."*

Bob loads `.bob/skills/drift-remediation/SKILL.md` and explains the detection → report → remediation loop.

### 4b. Simulate drift

Ask Bob:
> *"Simulate Apache drift on the instance."*

```bash
cd ansible && ansible-playbook simulate-apache-drift.yaml \
  -i "$EC2_IP," \
  --private-key="$SSH_KEY_PATH" \
  -u ec2-user
```

This stops Apache and modifies its config — simulating a manual change that diverges from the baseline.

### 4c. Run drift detection

Ask Bob:
> *"Run drift detection and show me what changed."*

```bash
cd ansible && ansible-playbook drift-detection.yaml \
  -i "$EC2_IP," \
  --private-key="$SSH_KEY_PATH" \
  -u ec2-user
```

Bob then:
1. Fetches the latest drift report from `/var/log/drift-reports/` on the instance
2. Parses the JSON and summarises findings:
   - Apache service stopped (expected: running)
   - Config file hash mismatch
3. Produces a structured drift summary table

### 4d. Remediate

Ask Bob:
> *"Remediate the drift."*

```bash
cd ansible && ansible-playbook drift-remediation.yaml \
  -i "$EC2_IP," \
  --private-key="$SSH_KEY_PATH" \
  -u ec2-user
```

Bob confirms remediation success by re-running detection — drift report should show all checks green.

**Talking point:** Bob detected, explained, and fixed the drift without the engineer needing to SSH into the box or read raw JSON.

---

## Stage 5 — GitOps: PR Generation & Harness Pipeline (Platform SRE)

**Mode:** Remains **Platform SRE**

**Goal:** Generate a GitOps PR from the port change made in Stage 1d, then show how it gates the Harness pipeline.

### 5a. Generate the PR

Ask Bob:
> *"Generate a pull request for the port 8083 change we made."*

Bob uses the **Create Pull Request** workflow:
1. Reads the git diff
2. Fills in `.github/pull_request_template.md`
3. Stages the change summary, references the ports.yaml catalog entry, notes the Sentinel risk level
4. Creates the PR on `github.com/csgorham/bob-automation-nw`

### 5b. Show the PR template

Point out `.github/pull_request_template.md` — it captures:
- What changed and why
- Sentinel policy impact
- Vault credential hygiene status
- Rollback plan

### 5c. Harness pipeline trigger (Tier 4 — requires Harness account)

When the PR is merged to `main`, `.github/workflows/harness-trigger.yml` fires and calls the Harness API to start `ami_build_pipeline`.

The 12-stage pipeline runs:
1. **Check S3** — `ami-pipeline-s3-check` workspace (`ws-cXnGs9Q6vwxcNheL`)
2. **Create S3** — `ami-pipeline-s3` workspace (`ws-uGtV1DEBnULDJwzf`)
3. **Validate Packer** — `packer validate`
4. **Build AMI** — `packer build` → pushes to HCP Packer Registry
5. **Sentinel: require-tags** — policy gate
6. **Sentinel: restrict-instance-types** — policy gate
7. **Sentinel: enforce-s3-encryption** — policy gate
8. **Provision Network** — `ami-pipeline-network` workspace (`ws-knQbRVQxeyzbWcwj`)
9. **Provision EC2** — `ami-pipeline-ec2` workspace (`ws-i7ApJ9RdDPvvEQVd`)
10. **Drift Detection** — Ansible against new instance
11. **Smoke Test** — HTTP health check on provisioned EC2
12. **Notify** — Slack/email result

Full pipeline reference: [`docs/PIPELINE-ARCHITECTURE.md`](docs/PIPELINE-ARCHITECTURE.md)

---

## Key Metrics to Cite

| Metric | Value |
|--------|-------|
| Manual steps eliminated | ~14 |
| Time to provision (manual) | ~45 min |
| Time to provision (with Bob + Harness) | ~8 min |
| Policy gates in pipeline | 3 Sentinel checks |
| Drift detection to remediation | < 2 min |
| Hardcoded secrets in codebase | 0 |
| Long-lived AWS credentials | 0 (all dynamic via Vault) |

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `vault status` fails | Check `VAULT_ADDR` and `VAULT_TOKEN` in `.env`; run `.scripts/vault.sh` |
| Terraform plan errors on AWS credentials | Vault AWS engine may be unsealed but the `demo-role` lease expired — re-auth to Vault |
| `hcp_packer_artifact` data source fails | Verify `hcp_channel_name` in `dev.auto.tfvars` matches the channel in HCP Packer Registry |
| Sentinel test fails | Run `sentinel test -verbose` in `sentinel/` to see which mock is triggering |
| Ansible drift playbook hangs | Check `SSH_KEY_PATH` and that the EC2 security group has port 22 open |
| Harness pipeline not triggering | Check `HARNESS_API_KEY` secret in GitHub repo → Settings → Secrets and variables |

---

## Mode Switch Summary

```
Bob session start
    │
    ├─ Infra Architect ──► Stage 1 (architecture, ports, scaffolding)
    │
    ├─ Policy Auditor  ──► Stage 2 (Sentinel checks, Vault audit)
    │
    └─ Platform SRE    ──► Stages 3–5 (provision, drift, GitOps, Harness)
```

Each mode constrains what Bob can execute — Infra Architect and Policy Auditor are read-only by design, preventing accidental `terraform apply` during planning and compliance phases.
