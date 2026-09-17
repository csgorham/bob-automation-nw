---
name: drift-remediation
description: >-
  Use when the user wants to detect, analyze, or remediate infrastructure drift on EC2 instances
  managed by the Golden Workflow. Activates for requests like "check for drift", "run drift
  detection", "parse the drift report", "what drifted", "fix the drift", "run remediation",
  or "self-heal the instance". Guides Bob through fetching JSON drift reports from managed nodes,
  summarizing multi-vector findings against the baseline config, and triggering targeted Ansible
  remediation playbooks.
---

# Drift Remediation

This skill guides Bob through the full Day-2 self-healing loop: running Ansible drift detection,
fetching and parsing the JSON audit report from the managed EC2 node, summarizing findings against
the golden baseline, and orchestrating targeted Ansible remediation.

---

## Prerequisites

Before running any Ansible command, confirm the following variables are available in the session.
Use `ask_followup_question` if any are missing:

| Variable | Purpose | Example |
|---|---|---|
| `EC2_IP` | Target EC2 instance IP address | `10.0.1.45` |
| `SSH_KEY` | Path to SSH private key file | `/path/to/key.pem` |
| `ANSIBLE_DIR` | Absolute or relative path to ansible/ | `./ansible` |

---

## Step 1 -- Load the Baseline

1. Use `read_file` on `ansible/baseline-config.yaml` to load the golden state definition.
2. Build an in-memory reference of:
   - `required_packages`: packages that must be installed
   - `forbidden_packages`: packages that must NOT be present
   - `required_services`: services and their expected state + enabled status
   - `config_files`: monitored files with expected owner, group, and mode
   - `expected_ports`: TCP ports that must be open (22, 80, 443 by default)
   - `security`: expected SELinux mode and firewalld state
3. Summarize the baseline to the user in a concise table before running detection.

---

## Step 2 -- Run Drift Detection

1. Execute the drift detection playbook (read-only, no changes to the host):
   ```bash
   cd ansible && ansible-playbook drift-detection.yaml \
     -i "$EC2_IP," --private-key=$SSH_KEY -u ec2-user
   ```
2. Watch the playbook output for FAILED or CHANGED tasks -- surface any play-level errors
   immediately and stop if the playbook cannot complete.
3. The playbook writes a timestamped JSON report to `/var/log/drift-reports/` on the managed node.

---

## Step 3 -- Fetch the JSON Drift Report

1. Retrieve the most recent drift report from the managed node:
   ```bash
   ssh -i $SSH_KEY ec2-user@$EC2_IP \
     "sudo cat \$(ls -t /var/log/drift-reports/drift-report-*.json | head -1)"
   ```
2. If the command fails (no report found, permission denied), surface the error and ask the user
   whether to re-run the detection playbook or specify a report path manually.
3. Parse the JSON output. The report schema produced by the ec2_drift_detection role contains
   sections for each drift vector type. Map each section to the baseline reference from Step 1.

---

## Step 4 -- Analyze and Summarize Findings

For each drift vector found in the report, produce a structured finding entry:

```
Vector Type   : <service_down | forbidden_package | missing_package | file_permission |
                 unexpected_port | security_policy>
Affected Item : <service name, package name, file path, or port number>
Observed State: <current value on the host>
Expected State: <value from ansible/baseline-config.yaml>
Severity      : <CRITICAL | HIGH | MEDIUM | LOW>
Remediation   : <brief description of the Ansible task that will fix this>
```

Severity mapping:
- **CRITICAL**: required service is down (e.g., httpd stopped), forbidden package present
- **HIGH**: file permission or ownership mismatch on a security-sensitive file
            (e.g., /etc/ssh/sshd_config mode != 0600)
- **MEDIUM**: missing required package, unexpected open port
- **LOW**: SELinux mode deviation, firewalld state mismatch, non-critical config delta

After enumerating all findings:
1. Print a summary table (Severity | Item | Observed | Expected | Remediation).
2. Report a total count per severity tier.
3. Provide a GO / NO-GO recommendation:
   - NO-GO (immediate remediation required) if any CRITICAL or HIGH findings exist.
   - ADVISORY (remediate soon) if only MEDIUM or LOW findings exist.
   - CLEAN if no drift is detected.

---

## Step 5 -- Confirm Remediation Scope

1. If the verdict is CLEAN, report the result and stop.
2. If findings exist, ask the user:
   - "Remediate all findings automatically?"
   - "Select specific drift vectors to remediate?"
   - "Generate a report only -- no remediation now?"
3. If the user selects specific vectors, list them by severity and let the user choose.
4. Record the confirmed remediation scope before proceeding.

---

## Step 6 -- Run Targeted Remediation

1. Execute the remediation playbook against the target host:
   ```bash
   cd ansible && ansible-playbook drift-remediation.yaml \
     -i "$EC2_IP," --private-key=$SSH_KEY -u ec2-user
   ```
2. Monitor the playbook output for FAILED tasks. If any task fails:
   - Report the failed task name and error message.
   - Ask the user whether to retry, skip, or abort.
   - Do not proceed silently past a failed remediation task.
3. After the playbook completes, fetch the remediation report:
   ```bash
   ssh -i $SSH_KEY ec2-user@$EC2_IP \
     "sudo cat \$(ls -t /var/log/drift-reports/remediation-report-*.json | head -1)"
   ```
4. Parse the remediation report and confirm which vectors were resolved.

---

## Step 7 -- Post-Remediation Verification

1. Re-run drift detection (Step 2) to confirm clean state.
2. Fetch and parse the new drift report (Steps 3-4).
3. If any findings remain, repeat Steps 5-6 for the residual vectors.
4. If the host is clean, proceed to Step 8.

---

## Step 8 -- Generate Remediation Summary

Produce a structured Markdown summary of the full remediation cycle:

```markdown
## Drift Remediation Summary

**Host**: <EC2_IP>
**Detection run**: <timestamp from report filename>
**Remediation run**: <timestamp from remediation report filename>

### Findings Detected
| Severity | Item | Observed | Expected |
|---|---|---|---|
...

### Findings Resolved
| Item | Remediation Action | Status |
|---|---|---|
...

### Outstanding Items
<List any findings not resolved, or "None -- host is clean.">

### Verdict: <CLEAN | RESIDUAL DRIFT>
```

Offer to include this summary as the body of a GitOps pull request (links to the
`infra-automation-orchestrator` skill Stage 6 for PR generation).
