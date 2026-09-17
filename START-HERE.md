# Start Here

This is the Golden Workflow demo — an IBM Bob-orchestrated infrastructure lifecycle across Day 0
(scaffolding), Day 1 (provisioning), and Day 2 (drift detection and self-healing).

This file is your complete on-ramp. Read it top to bottom, then you won't need to open anything
else to get started.

---

## Step 1 — Understand what you can run right now

The demo has three tiers. You do not need all three to show something compelling.

| Tier | What the audience sees | What you need |
|:---|:---|:---|
| **Tier 1** | Bob reads code, explains architecture, audits Sentinel policies, traces Vault credentials | Vault running + `.env` filled in |
| **Tier 2** | All of Tier 1, plus live `terraform plan` output per module | + HCP Terraform account |
| **Tier 3** | All of Tier 2, plus live Apache drift injection, detection, and autonomous remediation | + Running EC2 instance + SSH key |
| **Tier 4** | All of Tier 3, plus the full Harness pipeline running automatically on PR merge — 12 stages, all 4 Terraform workspaces, Packer build, Ansible baseline, PR comment feedback | + Harness account + GitHub repo secrets (`HARNESS_API_KEY`, `HARNESS_ACCOUNT_ID`, `HARNESS_PROJECT_ID`) |

**Tier 1 is the most impressive for a Bob demo.** It is entirely conversational — no infrastructure
needs to exist. Bob reasons about real code, runs real `sentinel test` commands, and makes real
edits (like adding a port). Start here.

---

## Step 2 — Get the `.env` file from Caroline

Before you do anything, you need a `.env` file with real credentials. Do not try to generate these
yourself — ask Caroline to share her working `.env`.

The values you need for **Tier 1**:

```bash
export VAULT_ADDR="..."        # Vault server URL
export VAULT_TOKEN="..."       # Vault root/admin token
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_REGION="us-east-2"
```

Additional values for **Tier 2**:
```bash
export HCP_TERRAFORM_TOKEN="..."
export hcp_client_id="..."
export hcp_client_secret="..."
export hcp_organization_id="..."
export hcp_project_id="..."
```

Additional values for **Tier 3**:
```bash
export EC2_IP="..."            # from terraform output after apply
export SSH_KEY_PATH="$HOME/.ssh/golden-workflow-dev.pem"
```

Once you have the file, place it at the repo root and run:
```bash
source .env
```

> **Never commit `.env` to Git.** It is in `.gitignore` already.

---

## Step 3 — Install the CLI tools

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform \
             hashicorp/tap/vault \
             hashicorp/tap/packer \
             hashicorp/tap/sentinel \
             ansible jq git
```

Verify:
```bash
terraform -version && vault -version && sentinel version && ansible --version
```

---

## Step 4 — Run the preflight check

```bash
source .env
bash .scripts/demo-preflight.sh
```

This checks CLI tools, environment variables, and Vault connectivity. Fix anything that shows red
before presenting.

---

## Step 5 — Open the repo in Bob and load the orchestrator

Open this repo folder in your IDE with Bob's chat panel visible.

**Start every demo session by pasting this single prompt into Bob:**

```
Start the Golden Workflow demo from the beginning.
```

Bob will activate the `infra-automation-orchestrator` skill, confirm your environment, and guide
you stage by stage — asking before advancing. You do not need to remember the mode or skill
sequence; the orchestrator manages it.

If you want to jump to a specific stage, use:
```
Start the Golden Workflow demo at Stage 2.
```

---

## The demo flow — what Bob does at each stage

### Bob's modes and skills in this demo

Three custom **modes** control Bob's tool permissions and persona:

| Mode | When it's active | What it unlocks |
|:---|:---|:---|
| **Infra Architect** | Day 0 — read-only planning | Architecture analysis, port catalog review, HCL scaffolding proposals |
| **Policy Auditor** | Day 1 pre-commit | Sentinel policy evaluation, credential scanning, compliance reports |
| **Platform SRE** | Day 1 provisioning + Day 2 | Live Terraform/Ansible execution, drift detection, GitHub PR creation |

Three custom **skills** give Bob structured playbooks for the specialized steps:

| Skill | When it fires | What it does |
|:---|:---|:---|
| `infra-automation-orchestrator` | Opening prompt | Manages the full stage sequence and prompts for confirmation at each gate |
| `sentinel-audit` | Day 1 compliance check | Evaluates all three policies, scans for static credentials, produces GO/NO-GO report |
| `drift-remediation` | Day 2 detection + fix | Runs detection, fetches JSON report, maps findings to baseline, orchestrates remediation |

The orchestrator skill calls into the sentinel-audit and drift-remediation skills at the right
moments — you don't need to activate them manually.

---

### Day 0 — Architecture & scaffolding (~8 min)

**Bob mode**: Infra Architect
**Skill active**: `infra-automation-orchestrator` → Stage 1

**Set the scene:**
> "Devin is a developer who needs to add a new metrics endpoint to the EC2 instance. In the old
> world he opens a Jira ticket and waits two days. With Bob, he just asks."

**Paste this into Bob:**
```
Analyze our Terraform and Packer workspace architecture. How are the network,
S3, and EC2 modules decoupled, and how does the EC2 module dynamically
configure ingress rules?
```
Bob (in Infra Architect mode, read-only) explains the three independent Terraform workspaces,
points to `ports.yaml` as the single source of truth, and maps the Vault KV integration bus —
all without touching a file.

**Then:**
```
We need to expose Prometheus metrics on port 9090 for the dev environment.
Add port 9090 to the ingress configuration following project conventions.
```
Bob targets [`terraform/ec2/ports.yaml`](terraform/ec2/ports.yaml) — not `main.tf`. It proposes
a diff, explains why, and confirms before applying. The security group rule is automatically
picked up at the next plan. No HCL authoring required.

---

### Day 1 — Vault audit & Sentinel shift-left (~8 min)

**Bob mode**: Switch to Policy Auditor
**Skill active**: `infra-automation-orchestrator` → Stage 2 → fires `sentinel-audit`

**Set the scene:**
> "Before Devin pushes anything, he wants to know: are there static AWS credentials in this
> codebase? And will his changes pass the CI/CD policy gates? He asks Bob before opening a PR."

**Paste this into Bob:**
```
How does our EC2 Terraform configuration authenticate with AWS, and what is
the lease TTL for generated credentials?
```
Bob traces [`terraform/ec2/main.tf`](terraform/ec2/main.tf) to the Vault dynamic credential data
source. Zero static keys, 15-minute TTL. This is the CISO talking point.

**Then:**
```
Audit our S3 bucket and EC2 instance definitions against the Sentinel policies
in sentinel/. Will our current configuration pass all compliance gates?
```
The `sentinel-audit` skill fires. Bob reads all three policies, runs static pre-flight evaluation,
scans for hardcoded credentials, verifies Vault dynamic sources, reviews port exposure, and
produces a structured GO/NO-GO compliance report — before Devin has committed a single line.
Run `cd sentinel && sentinel test` live to confirm.

---

### Day 1 — Provisioning (~5 min, Tier 2+)

**Bob mode**: Switch to Platform SRE
**Skill active**: `infra-automation-orchestrator` → Stage 3

Bob will only proceed to provisioning after the Stage 2 GO verdict. It walks through
`terraform init` + `terraform plan` per module, parses the plan output for destroys, and
requires explicit user confirmation before apply — never runs apply autonomously.

---

### Day 2 — Drift detection & self-healing (~10 min, Tier 3)

**Bob mode**: Platform SRE (already active)
**Skill active**: `infra-automation-orchestrator` → Stage 4/5 → fires `drift-remediation`

**Set the scene:**
> "It's 2 AM. Someone SSHd into the EC2 instance, stopped Apache to debug something, and forgot
> to restart it. Devin gets paged."

Inject drift (requires Tier 3):
```bash
cd ansible && ansible-playbook simulate-apache-drift.yaml \
  -i "$EC2_IP," --private-key=$SSH_KEY_PATH -u ec2-user
```

**Paste this into Bob:**
```
Check for drift on the target instance and execute the automated remediation flow.
```
The `drift-remediation` skill fires. Bob loads the baseline config, runs detection, fetches the
JSON report from the managed node, maps each vector to its severity, asks whether to remediate
all or select specific vectors, dispatches the remediation playbook, and re-runs detection to
confirm clean state. MTTR from hours of SSH debugging to autonomous seconds.

---

### GitOps — PR generation & pipeline handoff (~10 min)

**Bob mode**: Platform SRE (already active)
**Skill active**: `infra-automation-orchestrator` → Stage 6

**Paste this into Bob:**
```
Summarize all changes in this session and generate a production-ready pull request.
```
Bob runs `git diff --stat`, generates a commit message following the Golden Workflow format,
creates the PR via the GitHub MCP server, and — once the PR is approved and merged — the
[`.github/workflows/harness-trigger.yml`](.github/workflows/harness-trigger.yml) GitHub Actions
workflow fires, triggering the full 12-stage Harness pipeline automatically.

See [`docs/PIPELINE-ARCHITECTURE.md`](docs/PIPELINE-ARCHITECTURE.md) for the complete pipeline
stage reference.

---

## What to read next

| Document | What's in it |
|:---|:---|
| [`DEMO-WALKTHROUGH.md`](DEMO-WALKTHROUGH.md) | Full speaker track with exact prompts, expected Bob outputs, and talking points for every stage |
| [`docs/PIPELINE-ARCHITECTURE.md`](docs/PIPELINE-ARCHITECTURE.md) | Complete Harness pipeline reference — all 12 stages, 4 Terraform workspaces, required secrets, workspace IDs |
| [`docs/COMPLETE-SETUP-GUIDE.md`](docs/COMPLETE-SETUP-GUIDE.md) | Step-by-step setup including Harness and GitHub Actions secrets |
| [`docs/TEARDOWN-RECREATE-CHECKLIST.md`](docs/TEARDOWN-RECREATE-CHECKLIST.md) | If you ever tear down the Vault cluster or EC2 and need to rebuild |

---

## Quick troubleshooting

| Problem | Fix |
|:---|:---|
| `vault: command not found` | `brew install hashicorp/tap/vault` |
| `vault status` returns connection refused | The dev Vault server tab closed — restart: `vault server -dev` |
| `sentinel test` fails with parse errors | The mock files likely have missing commas — Bob can fix them |
| `terraform init` fails | Run from the module directory: `cd terraform/ec2 && terraform init` |
| Ansible unreachable | Check `EC2_IP` and that port 22 is open in the security group |
| Bob mode not switching | Reload Bob, confirm `.bob/custom_modes.yaml` exists and is valid YAML |
| Orchestrator skill not firing | Paste "Start the Golden Workflow demo" — the exact trigger phrase activates the skill |
| Harness pipeline not triggering on merge | Set `HARNESS_API_KEY`, `HARNESS_ACCOUNT_ID`, `HARNESS_PROJECT_ID` in GitHub repo → Settings → Secrets → Actions |
| Harness pipeline fails at Check S3 | Workspace IDs in `harness-pipeline.yaml` lines 44/397/582 need updating to your org. See `docs/PIPELINE-ARCHITECTURE.md` |
| AAP variables (`aap_url`, `aap_user`, `aap_pwd`) | Not required — Harness runs Ansible directly via SSH. Safe to leave unset. |
