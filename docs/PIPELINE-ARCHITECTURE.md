# Pipeline Architecture — Golden Workflow

This document maps the complete automated infrastructure pipeline that runs after a GitHub PR
is merged. It covers the trigger mechanism, every Harness stage, all four Terraform workspaces,
and the secrets/credentials each stage needs.

---

## The Closed Loop

```
Developer uses Bob (modes + skills)
  ↓
Edits ports.yaml / dev.auto.tfvars
  ↓
Runs sentinel-audit skill — pastes GO verdict into PR template
  ↓
GitHub PR opened → reviewed → Approved
  ↓
PR merged to main
  ↓
.github/workflows/harness-trigger.yml fires (GitHub Actions)
  ↓
Harness ami-build-pipeline runs (12 stages, fully automated)
  ↓
Harness posts deployment summary as PR comment
  ↓
Bob reads drift report — drift-remediation skill remediates
```

Bob is the developer-side interface. Harness is the execution engine.
They hand off at the PR merge boundary.

---

## Trigger: `.github/workflows/harness-trigger.yml`

Fires on `pull_request: types: [closed]` when `merged == true` targeting `main`.

POSTs to the Harness webhook API:
```
POST https://app.harness.io/gateway/pipeline/api/webhook/triggerPipeline
  ?accountIdentifier=<HARNESS_ACCOUNT_ID>
  &orgIdentifier=default
  &projectIdentifier=<HARNESS_PROJECT_ID>
  &targetBranchName=main
```

**Required GitHub repository secrets** (Settings → Secrets and variables → Actions):

| Secret name | What it is | Where to get it |
|:---|:---|:---|
| `HARNESS_API_KEY` | Harness API key for the service account | Harness → Account Settings → API Keys |
| `HARNESS_ACCOUNT_ID` | Your Harness account ID | Harness → Account Settings → Overview |
| `HARNESS_PROJECT_ID` | Your Harness project identifier | Harness → Project Settings → Overview |

---

## Harness Secrets (stored in Harness, not in `.env`)

The pipeline reads these at runtime via `<+secrets.getValue("...")>`:

| Harness secret name | Value | Set in |
|:---|:---|:---|
| `vault_addr` | Your Vault server URL | Harness → Project → Secrets |
| `vault_token` | Vault root/admin token | Harness → Project → Secrets |

All other credentials flow through Vault — the pipeline fetches them from Vault at runtime
rather than storing them in Harness.

---

## The Four Terraform Workspaces

| Workspace | HCP Terraform name | Purpose | Hardcoded ID in pipeline |
|:---|:---|:---|:---|
| `terraform/s3-check` | `ami-pipeline-s3-check` | Read-only pre-flight: checks if S3 bucket already exists | `ws-cXnGs9Q6vwxcNheL` |
| `terraform/s3` | `ami-pipeline-s3` | Creates S3 bucket + IAM user + writes creds to Vault | `ws-uGtV1DEBnULDJwzf` |
| `terraform/network` | `ami-pipeline-network` | Creates VPC + subnet + writes IDs to Vault | `ws-knQbRVQxeyzbWcwj` |
| `terraform/ec2` | `ami-pipeline-ec2-<env>` | Created dynamically per `*.auto.tfvars` file | Dynamic — created by pipeline |

---

## Pipeline Stage Map

### Stage 1 — Check S3 (`check_s3`)
Triggers a run on workspace `ami-pipeline-s3-check`. Runs `terraform/s3-check/main.tf` which
calls AWS `head-bucket`. Output variable `S3_EXISTS` gates all downstream S3 creation stages.

### Stage 2 — Plan S3 and Network Infrastructure (`plan_infrastructure`)
1. **Plan S3** — triggers `auto-apply: false` run on `ami-pipeline-s3`. Conditional on `S3_EXISTS == false`.
2. **Validate S3 Sentinel Policies** — checks run status for `policy_checked`.
3. **Plan Network** — checks Vault for existing `vpc_id`/`subnet_id`. Skips if network already exists.
4. **Validate Network Sentinel Policies** — same pattern as S3.

### Stage 3 — Approve Infrastructure (`approve_infrastructure`)
1. **Post PR Comment** — clones PR branch, compares `.auto.tfvars` files against Vault, posts plan summary to GitHub PR.
2. **Manual Approval** — polls GitHub PR reviews API every 30 seconds (up to 24 hours) waiting for an Approved review.

> This is how Bob's pre-merge compliance output connects to pipeline execution. The PR template
> instructs the author to paste Bob's sentinel-audit output. A reviewer reads it, approves.
> That GitHub approval unblocks the Harness pipeline.

### Stage 4 — Create S3 (`create_s3`)
Conditional on `S3_EXISTS == false`. Applies the S3 plan. After apply, Terraform writes
`bucket_arn`, `iam_user`, `access_key_id`, `secret_access_key` to `secret/ami-pipeline/s3`.

### Stage 5 — Create Network (`create_network`)
Applies the network plan (or skips if already exists). After apply, Terraform writes
`vpc_id`, `subnet_id`, `region` to `secret/ami-pipeline/network`.

### Stage 6 — Build AMI (`build_ami`)
1. Checks Vault for cached `version_fingerprint` at `secret/ami-pipeline/ami`. Skips build if found.
2. If no cache: fetches HCP credentials from Vault, clones repo, runs `packer build` using Vault dynamic AWS credentials.
3. Assigns new version to `latest` channel via HCP API.
4. Stores `ami_id`, `version_fingerprint`, `region`, `build_date` to `secret/ami-pipeline/ami`.

### Stage 7 — Setup EC2 Workspaces (`setup_ec2_workspaces`)
Scans `terraform/ec2/*.auto.tfvars`. For each file, creates a new HCP Terraform workspace
`ami-pipeline-ec2-<env>` if it doesn't exist. Sets workspace variables including Vault credentials.
Output: `NEW_WORKSPACE_ENV` — the name of any newly created environment.

### Stage 8 — Plan EC2 Launch (`plan_ec2`)
Looks up the workspace for `ami-pipeline-ec2-<env>`, sets `ami_id` variable, triggers plan,
validates Sentinel policies on the plan result.

### Stage 9 — Launch EC2 (`launch_ec2`)
Applies the approved EC2 plan. After apply, Terraform writes to `secret/ami-pipeline/ec2/<env>`:
`instance_id`, `public_ip`, `private_ip`, `private_key` (PEM), `key_name`, `availability_zone`.

### Stage 10 — Configure with Ansible (`ansible_config`)
For each environment in Vault: fetches `instance_ip` and `private_key`, writes PEM to `/tmp`,
runs `ansible-playbook site.yaml`, deletes PEM.

### Stage 11 — Post Deployment Summary (`post_deployment_summary`)
Queries Vault for all environments, builds a Markdown table of IPs/AZs/regions, posts as
GitHub PR comment.

### Stage 12 — Drift Detection (`drift_detection`)
1. Harness Approval gate before drift simulation.
2. Runs `simulate-apache-drift.yaml` to inject drift.
3. Runs `drift-detection.yaml`, exports `DRIFT_DETECTED`.
4. Runs `drift-remediation.yaml` if `DRIFT_DETECTED != 0`.

---

## Vault Secret Paths — Complete Reference

| Path | Written by | Read by |
|:---|:---|:---|
| `secret/ami-pipeline/network` | terraform/network (apply) | terraform/ec2, Harness Packer stage |
| `secret/ami-pipeline/s3` | vault.sh (seed) + terraform/s3 (apply) | terraform/s3-check |
| `secret/ami-pipeline/hcp-packer` | vault.sh | terraform/ec2 (HCP provider), Harness Packer stage |
| `secret/ami-pipeline/hcp-terraform` | vault.sh | All Harness stages (HCP TF API calls) |
| `secret/ami-pipeline/github` | vault.sh | Harness: PR comments, repo clone |
| `secret/ami-pipeline/ami` | Harness Packer stage | Harness EC2 stages (cache check) |
| `secret/ami-pipeline/ec2/<env>` | terraform/ec2 (apply) | Harness Ansible stages, drift scripts |
| `secret/ami-pipeline/aap` | vault.sh | **Not used** — legacy path, safe to ignore |
| `aws/creds/demo-role` | Vault AWS engine | terraform/*, Harness Packer stage |

---

## AAP Variables — Not Required

The `aap_url`, `aap_user`, `aap_pwd` variables write to `secret/ami-pipeline/aap`.
No stage in `harness-pipeline.yaml` reads this path. The pipeline runs Ansible directly
inside Harness ShellScript steps using SSH keys from Vault. Safe to leave unset.

---

## Workspace IDs — Current Values

| Workspace | ID |
|:---|:---|
| `ami-pipeline-s3-check` | `ws-cXnGs9Q6vwxcNheL` |
| `ami-pipeline-s3` | `ws-uGtV1DEBnULDJwzf` |
| `ami-pipeline-network` | `ws-knQbRVQxeyzbWcwj` |
| `ami-pipeline-ec2` | `ws-i7ApJ9RdDPvvEQVd` (default; env-specific workspaces created dynamically) |

To retrieve current IDs:
```bash
source .env
curl -s \
  -H "Authorization: Bearer $HCP_TERRAFORM_TOKEN" \
  https://app.terraform.io/api/v2/organizations/dev_space-cgh/workspaces \
  | jq -r '.data[] | select(.attributes.name | startswith("ami-pipeline")) | "\(.attributes.name): \(.id)"'
```
