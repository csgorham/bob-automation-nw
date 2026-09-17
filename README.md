# Golden Workflow — Powered by IBM Bob

A fully governed, AI-orchestrated infrastructure lifecycle driven by **IBM Bob** as the central intelligent co-pilot. Bob moves infrastructure management from reactive scripting into a single, policy-enforced, conversational interface across **Day 0**, **Day 1**, and **Day 2** operations.

> **New here?** → Start with [`START-HERE.md`](START-HERE.md)

---

## What it demonstrates

| Phase | What Bob does |
|:---|:---|
| **Day 0 — Scaffolding** | Translates developer intent into HCL, safely mutates `ports.yaml`, explains module architecture |
| **Day 1 — Provisioning** | Audits Sentinel policies pre-commit, traces Vault dynamic credentials, runs `terraform plan` |
| **Day 2 — Drift & Healing** | Parses JSON drift reports, dispatches targeted Ansible remediation, confirms clean state |
| **GitOps** | Generates PR descriptions with compliance summary, rollback strategy, and risk assessment |

---

## Architecture

```
Developer (Devin)
        │  declares intent
        ▼
┌───────────────────────────────────────────────────┐
│                IBM Bob — Orchestrator              │
│  Infra Architect · Platform SRE · Policy Auditor  │
└──────┬─────────────┬──────────────┬───────────────┘
       │             │              │
       ▼             ▼              ▼
  DAY 0           DAY 1          DAY 2
  ports.yaml      Vault creds    Drift JSON
  Packer HCL      Sentinel       Ansible roles
  Terraform mods  terraform plan remediation
```

**Key design decisions:**
- Ingress rules live in [`terraform/ec2/ports.yaml`](terraform/ec2/ports.yaml) — never hardcoded in `main.tf`
- AWS credentials are Vault dynamic (15 min TTL) — no static keys anywhere
- Three Terraform workspaces (`s3`, `network`, `ec2`) are fully independent state machines
- Drift reports are JSON at `/var/log/drift-reports/` on managed EC2 nodes

---

## Tech stack

| Layer | Technology |
|:---|:---|
| Infrastructure as Code | Terraform (HCP Terraform, decoupled state) |
| Golden Image | Packer + HCP Packer Registry + Amazon Linux 2023 |
| Zero-Trust Secrets | HashiCorp Vault (dynamic AWS creds, 15–20 min TTL) |
| Policy as Code | HashiCorp Sentinel (3 active policies) |
| Configuration Management | Ansible (detect, remediate, harden roles) |
| CI/CD | Harness + GitHub Actions |
| AI Orchestrator | IBM Bob (custom modes + skills) |

---

## Bob modes & skills

Three custom modes in [`.bob/custom_modes.yaml`](.bob/custom_modes.yaml):

| Mode | ID | Use for |
|:---|:---|:---|
| Infra Architect | `infra-architect` | Day-0 planning — read-only |
| Platform SRE | `platform-sre` | Day-1/2 live operations — full execute |
| Policy Auditor | `policy-auditor` | Pre-commit/pre-merge compliance review |

Three skills in [`.bob/skills/`](.bob/skills/):

| Skill | Activates for |
|:---|:---|
| `infra-automation-orchestrator` | "start the demo", "run stage N", "walk me through the workflow" |
| `drift-remediation` | "check for drift", "fix the drift", "self-heal the instance" |
| `sentinel-audit` | "check Sentinel policies", "audit my Terraform plan" |

---

## Documentation

| Document | Read when |
|:---|:---|
| [`START-HERE.md`](START-HERE.md) | You're new — start here |
| [`docs/COMPLETE-SETUP-GUIDE.md`](docs/COMPLETE-SETUP-GUIDE.md) | Setting up from scratch |
| [`DEMO-WALKTHROUGH.md`](DEMO-WALKTHROUGH.md) | Running the demo (speaker track + exact Bob prompts) |
| [`docs/DEVIN-EXPERIENCE.md`](docs/DEVIN-EXPERIENCE.md) | Before/after developer journey — useful for explaining the "why" |
| [`docs/DRIFT-DETECTION-GUIDE.md`](docs/DRIFT-DETECTION-GUIDE.md) | Day-2 drift deep-dive and JSON report schema |
| [`docs/GITOPS-WORKFLOW.md`](docs/GITOPS-WORKFLOW.md) | PR gates, Harness pipeline, test-before-merge pattern |
| [`docs/TEARDOWN-RECREATE-CHECKLIST.md`](docs/TEARDOWN-RECREATE-CHECKLIST.md) | Rebuilding after a Vault/EC2 teardown |
| [`AGENTS.md`](AGENTS.md) | Bob/agent project conventions (commands, patterns, gotchas) |
