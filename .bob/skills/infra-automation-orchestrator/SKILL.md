---
name: infra-automation-orchestrator
description: >-
  Use when a presenter or developer wants to run, navigate, or orchestrate the Golden Workflow
  end-to-end interactive demo -- covering Day-0 architecture scaffolding, Day-1 Vault/Sentinel
  pre-checks and provisioning, Day-2 drift detection and self-healing, and GitOps PR generation.
  Also activates for requests like "start the demo", "walk me through the workflow", "run stage N",
  or "what comes next in the Golden Workflow".
---

# Infra Automation Orchestrator

This skill guides a presenter or developer through the full Golden Workflow lifecycle with IBM Bob
as the central orchestrator. Each stage maps to a concrete set of Bob-assisted actions.

---

## Before You Begin

1. Use `read_file` to confirm the following context files are present and readable:
   - `DEMO-WALKTHROUGH.md` -- full presenter walkthrough and stage definitions
   - `ansible/baseline-config.yaml` -- golden state definition
   - `terraform/ec2/ports.yaml` -- dynamic port declarations
   - `sentinel/sentinel.hcl` -- active policy enforcement levels
2. Ask the user which stage they want to start from using `ask_followup_question`:
   - Stage 0: Reset / Environment Preparation
   - Stage 1: Day-0 -- Devin's Feature Request & Architecture Scaffolding
   - Stage 2: Day-1 -- Vault Pre-Check & Sentinel Shift-Left
   - Stage 3: Day-1 -- Provisioning
   - Stage 4: Day-2 -- Drift Injection
   - Stage 5: Day-2 -- Drift Detection & Bob-Guided Remediation
   - Stage 6: GitOps PR Generation & Review
3. If the user says "start from the beginning" or "run all stages", begin at Stage 0 and prompt
   for confirmation before advancing to each subsequent stage.

---

## Stage 0 -- Reset / Environment Preparation

**Goal:** Confirm the workspace and target host are in a clean initial state.

1. Remind the user to set required environment variables:
   ```
   export VAULT_ADDR=<vault-address>
   export VAULT_TOKEN=<vault-token>
   export EC2_IP=<target-ec2-ip>
   export SSH_KEY=<path-to-private-key.pem>
   ```
2. Use `read_file` on `terraform/ec2/dev.auto.tfvars` and surface the current environment config.
3. Instruct the user to verify connectivity: `ssh -i $SSH_KEY ec2-user@$EC2_IP "echo OK"`.
4. Confirm Git working tree is clean: `git status`.
5. Print a Stage 0 PASS summary when all prerequisites are met.

---

## Stage 1 -- Day-0: Devin's Feature Request & Architecture Scaffolding

**Goal:** Show how Bob converts developer intent into safe HCL and infrastructure designs.

1. Accept a natural-language feature request from the user (or use the canned demo prompt:
   "I need to expose a new internal metrics port 9090 on the EC2 instance").
2. Use `read_file` on `terraform/ec2/ports.yaml` to show the current ingress rules.
3. Propose the minimal change to `ports.yaml` -- add the new port entry with a clear description.
   Present the diff before applying any edit.
4. Confirm with the user before using `apply_diff` to write the change.
5. Use `read_file` on `terraform/ec2/main.tf` to show how the security group dynamically
   picks up the new port automatically -- no Terraform resource hardcoding required.
6. Use `read_file` on `ansible/baseline-config.yaml` and check whether the new port should be
   added to `expected_ports`. Propose the change if needed.
7. Print a Stage 1 summary: what changed, what Terraform and Ansible steps are now required.

---

## Stage 2 -- Day-1: Vault Pre-Check & Sentinel Shift-Left

**Goal:** Demonstrate shift-left security -- validate policies and credential hygiene before
any infrastructure change reaches a cloud provider.

1. Use `read_file` on `sentinel/sentinel.hcl` to display all active policies and enforcement levels.
2. For each policy in `sentinel/`:
   - Use `read_file` to load the policy source.
   - Summarize what the policy enforces and its enforcement level (hard-mandatory / soft-mandatory).
   - Indicate whether the proposed Day-0 change would pass or require review.
3. Instruct the user to run Sentinel tests locally:
   ```
   cd sentinel && sentinel test
   ```
4. Parse the test output: report PASS / FAIL per policy with a clear rationale.
5. Check `terraform/ec2/*.auto.tfvars` for any static credentials -- flag any found as CRITICAL.
6. Confirm Vault dynamic credential references are in place:
   - `data "vault_aws_access_credentials"` with `role = "demo-role"`
   - `data "vault_kv_secret_v2"` scoped to `hcp_packer`
7. Print a Stage 2 compliance summary: GO / NO-GO verdict with all findings listed.

---

## Stage 3 -- Day-1: Provisioning

**Goal:** Show a safe, Bob-supervised Terraform provisioning run.

1. Confirm Stage 2 returned a GO verdict. If not, block and return to Stage 2.
2. Walk through the Terraform init + plan sequence per module. Show exact commands from AGENTS.md:
   ```
   cd terraform/ec2
   terraform init
   terraform plan -var-file=dev.auto.tfvars -var="vault_addr=$VAULT_ADDR" -var="vault_token=$VAULT_TOKEN"
   ```
3. Parse the plan output:
   - List all resources to be created, modified, or destroyed.
   - Flag any destroy actions and require explicit user confirmation before proceeding.
4. If the plan is safe, prompt the user to confirm before apply. Never run apply autonomously.
5. Print a Stage 3 provisioning summary: resources changed, time taken, next steps.

---

## Stage 4 -- Day-2: Drift Injection (Demo Simulation)

**Goal:** Inject realistic service drift to demonstrate the Day-2 self-healing loop.

1. Explain to the audience what drift vectors will be simulated (Apache stopped, config tampered).
2. Require explicit user confirmation before injecting drift -- this is destructive to the running
   service state.
3. Run the drift simulation playbook:
   ```
   cd ansible && ansible-playbook simulate-apache-drift.yaml \
     -i "$EC2_IP," --private-key=$SSH_KEY -u ec2-user
   ```
4. Confirm drift is live by checking service status remotely:
   ```
   ssh -i $SSH_KEY ec2-user@$EC2_IP "systemctl status httpd"
   ```
5. Print a Stage 4 confirmation: drift injected, service down, ready for Day-2 detection.

---

## Stage 5 -- Day-2: Drift Detection & Bob-Guided Remediation

**Goal:** Demonstrate Bob reading real JSON audit reports and orchestrating targeted remediation.

1. Run drift detection against the target host:
   ```
   cd ansible && ansible-playbook drift-detection.yaml \
     -i "$EC2_IP," --private-key=$SSH_KEY -u ec2-user
   ```
2. The playbook writes a JSON report to `/var/log/drift-reports/` on the managed node.
   Fetch the latest report:
   ```
   ssh -i $SSH_KEY ec2-user@$EC2_IP \
     "sudo cat \$(ls -t /var/log/drift-reports/drift-report-*.json | head -1)"
   ```
3. Parse the JSON output. For each drift vector found, summarize:
   - Vector type (service down / forbidden package / file permission / unexpected port)
   - Affected resource
   - Baseline expectation (from ansible/baseline-config.yaml)
   - Recommended Ansible task to remediate
4. Ask the user: "Remediate all findings now, or select specific vectors?"
5. Run targeted remediation:
   ```
   cd ansible && ansible-playbook drift-remediation.yaml \
     -i "$EC2_IP," --private-key=$SSH_KEY -u ec2-user
   ```
6. Fetch the remediation report and confirm all vectors are resolved.
7. Re-run drift detection to confirm clean state.
8. Print a Stage 5 remediation summary: vectors found, vectors resolved, time to remediation.

---

## Stage 6 -- GitOps PR Generation & Review

**Goal:** Close the loop by generating a structured GitOps pull request that captures all
changes made during the demo run.

1. Run `git diff --stat` to summarize changed files.
2. For each changed file, briefly describe what was changed and why (using context from earlier
   stages).
3. Propose a commit message following the format:
   ```
   feat(day-N): <short summary of change>

   - <bullet: what changed>
   - <bullet: why it changed>
   - Drift vectors remediated: <list or "none">
   - Sentinel policies: PASS
   - Vault credentials: dynamic (TTL 15 min)
   ```
4. Prompt the user to confirm the commit message before staging.
5. Stage and commit:
   ```
   git add <changed-files>
   git commit -m "<confirmed message>"
   git push origin <branch>
   ```
6. If the GitHub MCP server is available, use it to create a pull request with:
   - Title derived from the commit message
   - Body containing the Stage 5 remediation summary and Stage 2 compliance summary
   - Label: `golden-workflow-demo`
7. Print a Stage 6 summary: PR URL (if created), files changed, compliance verdict, next steps.

---

## Session Wrap-Up

After all stages are complete (or at any point the user asks for a summary):

1. Print a structured session log:
   - Stages completed
   - Files changed (with brief rationale)
   - Compliance verdict (Sentinel / Vault / Port audit)
   - Drift vectors injected and remediated
   - PR URL (if generated)
2. Remind the user of any open items (e.g., pending Terraform apply, unresolved Sentinel findings).
3. Suggest the next demo stage from `DEMO-WALKTHROUGH.md` based on current progress.
