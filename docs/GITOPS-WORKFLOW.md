# GitOps Workflow — Golden Workflow with IBM Bob

## Overview

This document describes the full GitOps lifecycle for infrastructure changes in the Golden Workflow, with **IBM Bob as the co-orchestrator** at every gate. Bob participates actively in PR authoring, pre-merge compliance checks, risk assessment, branch-aware pipeline coordination, and approval gate decisions — turning a traditionally manual review process into an intelligent, policy-governed workflow.

```
┌─────────────────────────────────────────────────────────────────────┐
│                         DEVIN THE DEVELOPER                         │
│          Declares intent → Bob governs every downstream gate        │
└─────────────────────────────────────────┬───────────────────────────┘
                                          │
                        ┌─────────────────▼─────────────────┐
                        │          IBM BOB (Co-Pilot)        │
                        │  • PR description generation       │
                        │  • Sentinel pre-merge audit        │
                        │  • Vault credential hygiene check  │
                        │  • Port exposure risk assessment   │
                        │  • Rollback plan generation        │
                        └─────┬────────────┬─────────────────┘
                              │            │
               ┌──────────────▼──┐    ┌───▼──────────────┐
               │  GitHub PR Gate │    │ Harness Pipeline  │
               │  (Code Review)  │    │ (Infra Execution) │
               └─────────────────┘    └──────────────────-┘
```

---

## Bob's Role in the GitOps Loop

### PR Authoring

Bob generates the full PR description — including compliance summary, infrastructure plan synopsis, and rollback strategy — from the working branch diff. Trigger this with:

```
Generate a PR description for my current branch changes.
Include Sentinel policy results, Vault credential hygiene, any port exposure risks, and a rollback strategy.
```

Bob's output maps directly to the sections in [`.github/pull_request_template.md`](../.github/pull_request_template.md).

### Pre-Merge Risk Assessment

Before the PR is opened, Bob can evaluate the full risk profile of the change:

```
Run a full pre-merge compliance check for this PR.
Summarise Sentinel policy results, Vault credential hygiene, exposed port changes, and any rollback risk.
```

This triggers Bob's `sentinel-audit` skill internally, which:
1. Runs `sentinel test` against all three active policies
2. Checks for hardcoded Vault tokens or static AWS credentials in the diff
3. Evaluates any `ports.yaml` changes for high-risk ingress exposure
4. Produces a structured GO / NO-GO compliance verdict

### Approval Gate Coordination

Bob can also assist reviewers at each approval gate:

```
Summarise the infrastructure changes in this PR and give me a GO / NO-GO recommendation for Gate 1 (code review).
```

```
Review the Terraform plan for this PR and tell me if Gate 2 (infrastructure approval) should proceed.
```

---

## Recommended Workflow: Test-Before-Merge

The **Test-Before-Merge** approach is the target GitOps pattern for this repository. It ensures the infrastructure plan from the PR branch is validated before any code reaches `main`.

### End-to-End Flow

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Developer creates feature branch                         │
│    git checkout -b feat/add-port-8443                       │
│    # Edit terraform/ec2/ports.yaml                          │
│    git commit -m "feat: add port 8443 for HTTPS admin"      │
│    git push origin feat/add-port-8443                       │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. Bob-Assisted PR Authoring                                │
│    Bob prompt: "Generate a PR description for my changes."  │
│    → Compliance summary auto-populated in PR template       │
│    → Sentinel results, Vault audit, port risk pasted in     │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. PR Opens → Harness Pipeline Auto-Triggers                │
│    - GitHub webhook fires on PR open/sync/reopen            │
│    - Pipeline clones PR branch (not main)                   │
│    - Sentinel pre-check stage runs                          │
│    - Terraform plan stage executes against PR branch        │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. Gate 1: Code Review (GitHub PR Approval)                 │
│    - Reviewer reads Bob's compliance summary in PR body     │
│    - Bob prompt: "Summarise the risk of this PR's changes." │
│    - Reviewer approves PR on GitHub                         │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. Gate 2: Infrastructure Approval (Harness)                │
│    - Platform lead reviews Terraform plan in pipeline       │
│    - Bob prompt: "Should Gate 2 proceed? Review the plan."  │
│    - Approves execution in Harness UI                       │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 6. Pipeline Provisions Infrastructure from PR Branch        │
│    ✓ Apply S3 / Network (if changed)                        │
│    ✓ Build AMI with updated Packer template                 │
│    ✓ Plan EC2 — reads ports.yaml from PR branch             │
│    ✓ Apply EC2 — creates/updates instance                   │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 7. Post-Apply Drift Check                                   │
│    bash .scripts/drift-detect.sh <EC2_IP>                   │
│    Bob prompt: "Parse the drift report and confirm clean."  │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 8. Success — Auto-Merge PR to main                          │
│    ✓ Infrastructure created successfully                    │
│    ✓ PR squash-merged to main                               │
│    ✓ main branch now reflects deployed state                │
└─────────────────────────────────────────────────────────────┘
```

---

## Pipeline Configuration

### Branch-Aware Variable

The pipeline uses a `BRANCH_NAME` variable populated from the webhook trigger so every `git clone` targets the PR source branch:

```yaml
pipeline:
  name: ami-build-pipeline
  variables:
    - name: BRANCH_NAME
      type: String
      default: <+trigger.sourceBranch>
      description: Branch to build from (auto-populated from PR trigger)
```

All `git clone` commands in the pipeline use:

```bash
BRANCH_NAME="${BRANCH_NAME:-main}"
git clone -b ${BRANCH_NAME} https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git
```

This appears in four pipeline stages:
- `Build AMI` stage
- `Plan EC2` stage
- `Apply EC2` stage
- `Destroy` stage

Without this variable, the pipeline clones `main` and ignores PR branch changes — the root cause of the previous `ports.yaml` mismatch issue.

### GitHub Webhook Trigger (Harness)

Configure a PR webhook trigger in the Harness UI:

```yaml
trigger:
  name: PR Trigger
  identifier: pr_trigger
  enabled: true
  source:
    type: Webhook
    spec:
      type: Github
      spec:
        type: PullRequest
        spec:
          connectorRef: github_connector
          autoAbortPreviousExecutions: true
          payloadConditions:
            - key: <+trigger.payload.action>
              operator: In
              value: opened,synchronize,reopened
          actions:
            - Opened
            - Synchronized
            - Reopened
```

### Auto-Merge on Pipeline Success

Add a final stage to squash-merge the PR after successful infrastructure provisioning:

```yaml
- stage:
    name: Merge PR on Success
    identifier: merge_pr
    type: Custom
    spec:
      execution:
        steps:
          - step:
              name: Auto-merge PR
              identifier: auto_merge
              type: ShellScript
              spec:
                shell: Bash
                environmentVariables:
                  - name: PR_NUMBER
                    type: String
                    value: <+trigger.prNumber>
                  - name: GITHUB_REPO
                    type: String
                    value: <+pipeline.tags.github_repo>
                source:
                  type: Inline
                  spec:
                    script: |
                      #!/bin/bash
                      set -e
                      GITHUB_TOKEN=$(vault kv get -field=token secret/ami-pipeline/github)
                      echo "Merging PR #${PR_NUMBER}..."
                      curl -X PUT \
                        -H "Authorization: token $GITHUB_TOKEN" \
                        -H "Accept: application/vnd.github.v3+json" \
                        "https://api.github.com/repos/${GITHUB_REPO}/pulls/${PR_NUMBER}/merge" \
                        -d '{"merge_method":"squash"}'
                      echo "✅ PR merged successfully"
    when:
      pipelineStatus: Success
```

---

## GitHub Actions: Harness Trigger on Merge

[`.github/workflows/harness-trigger.yml`](../.github/workflows/harness-trigger.yml) fires after a PR is **merged to main** and notifies Harness to trigger a reconciliation run. This is the fallback for the Option 1 (Merge-First) pattern and provides an audit trail of post-merge pipeline invocations.

```yaml
on:
  pull_request:
    types: [closed]
    branches:
      - main

jobs:
  trigger-harness:
    if: github.event.pull_request.merged == true
    runs-on: ubuntu-latest
    steps:
      - name: Trigger Harness Pipeline
        run: |
          curl -X POST \
            -H "x-api-key: ${{ secrets.HARNESS_API_KEY }}" \
            -H "Content-Type: application/json" \
            -d '{"branch":"main","repoIdentifier":"ami-pipeline"}' \
            "https://app.harness.io/gateway/pipeline/api/webhook/triggerPipeline?..."
```

**Required secrets** in the GitHub repository:
- `HARNESS_API_KEY` — Harness personal access token
- `HARNESS_ACCOUNT_ID` — Harness account identifier
- `HARNESS_PROJECT_ID` — Harness project identifier

---

## Approval Gates

### Gate 1: Code Review (GitHub PR)

| Field | Value |
|-------|-------|
| **Who** | Code reviewers (peer + lead developer) |
| **When** | After pipeline Sentinel check and Terraform plan pass |
| **What** | Review code changes — `ports.yaml`, Ansible, Terraform, Packer |
| **How** | Approve PR on GitHub; Bob compliance summary must be populated |
| **Bob assist** | `Summarise the risk profile of this PR for Gate 1 code review.` |

### Gate 2: Infrastructure Approval (Harness)

| Field | Value |
|-------|-------|
| **Who** | Infrastructure / Platform team lead |
| **When** | After GitHub PR approval (Gate 1) |
| **What** | Review Terraform plan output — resource changes, new ports, AMI builds |
| **How** | Approve execution in Harness pipeline UI |
| **Bob assist** | `Review the Terraform plan for this PR. Should Gate 2 proceed?` |

---

## Rollback Strategy

### Pre-Merge Failure (Automated)

If the pipeline fails before the PR is merged:
1. Pipeline marks the commit status as failed on GitHub
2. PR remains open with a blocked merge status
3. Push a fix commit to the same branch
4. Pipeline re-triggers automatically on `synchronize` event
5. No manual rollback action required

### Post-Merge Regression (Manual)

If infrastructure regresses after a successful merge:

```bash
# 1. Identify the last known-good merge commit
git log --oneline -10

# 2. Revert the merge commit (replace SHA with actual value)
git revert -m 1 <merge-commit-sha>
git checkout -b fix/revert-<original-branch-name>
git push origin fix/revert-<original-branch-name>

# 3. Open a revert PR — pipeline triggers on the revert branch
# Approve Gate 1 (code review) and Gate 2 (infra approval) as normal
```

**Bob prompt for rollback planning:**
```
Generate a rollback plan for the infrastructure changes introduced by PR #<number>.
Include the git revert command, Terraform destroy scope, and drift check steps.
```

---

## Branch Naming Convention

| Prefix | Use case | Example |
|--------|----------|---------|
| `feat/` | New feature or resource | `feat/add-port-8443` |
| `fix/` | Bug fix or broken config | `fix/vault-ttl-policy` |
| `chore/` | Maintenance, doc updates | `chore/update-ami-version` |
| `revert/` | Revert a previous merge | `revert/remove-port-3030` |
| `security/` | Security hardening changes | `security/rotate-iam-role` |

---

## Best Practices

1. **Single-concern PRs**: One infrastructure change per PR (one new port, one AMI update, one Vault role change). Smaller diffs mean faster Bob analysis and less risk.
2. **Always populate the Bob compliance block**: If Bob's `sentinel-audit` skill cannot be run, the PR template fields must be filled manually before review.
3. **`ports.yaml` is the only source of port truth**: Never hardcode security group ingress rules in `main.tf`. Bob enforces this during port risk assessment.
4. **Review Terraform plans**: Gate 2 reviewers must read the full `terraform plan` diff — not just the summary. Bob can highlight unexpected `-/+` replacements on request.
5. **Post-apply drift check**: Run `bash .scripts/drift-detect.sh <EC2_IP>` after every EC2 apply. Bob parses the JSON report and confirms the instance is clean.

---

## Bob Prompt Reference — GitOps Workflow

| Trigger point | Bob prompt |
|---------------|------------|
| Pre-PR authoring | `Generate a PR description for my current branch changes including compliance summary.` |
| Pre-merge check | `Run a full pre-merge compliance check. Summarise Sentinel, Vault, port risks, and rollback strategy.` |
| Gate 1 reviewer assist | `Summarise the risk profile of this PR for Gate 1 code review.` |
| Gate 2 reviewer assist | `Review the Terraform plan for this PR. Should Gate 2 infrastructure approval proceed?` |
| Post-apply validation | `Parse the drift report and confirm the instance is in a clean state after apply.` |
| Rollback planning | `Generate a rollback plan for the infrastructure changes in this PR.` |
| Credential audit | `Audit this PR for any hardcoded Vault tokens or static AWS credentials.` |
| Port exposure check | `Review the ports.yaml diff in this PR and flag any high-risk ingress exposures.` |

---

## Workflow Status

| Pattern | Status |
|---------|--------|
| Option 1: Merge-First (current fallback) | ✅ Active — `harness-trigger.yml` fires post-merge |
| Option 2: Test-Before-Merge (target) | 🔧 Requires `BRANCH_NAME` pipeline variable + Harness PR webhook |
| Bob PR Authoring | ✅ Available via `sentinel-audit` skill + PR template |
| Bob Gate Coordination | ✅ Available via direct Bob prompts at each gate |
| Auto-merge on success | 🔧 Requires final Harness pipeline stage addition |
