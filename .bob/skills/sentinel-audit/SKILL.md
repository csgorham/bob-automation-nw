---
name: sentinel-audit
description: >-
  Use when the user wants to evaluate, test, or enforce Sentinel policy compliance before a
  Terraform plan or commit. Activates for requests like "check Sentinel policies", "run sentinel
  test", "audit my Terraform plan", "will this pass the policy checks", "pre-commit compliance
  check", or "what policies would block this change". Walks through all three active Golden
  Workflow policies (require-tags, restrict-instance-types, enforce-s3-encryption), runs
  sentinel test, and produces a structured GO / NO-GO compliance report.
---

# Sentinel Audit

This skill guides Bob through a pre-commit and pre-plan Sentinel policy compliance check for the
Golden Workflow. It evaluates all three active policies, maps proposed Terraform changes to policy
requirements, runs the Sentinel test suite, and produces a structured compliance verdict.

---

## Active Policies Reference

The Golden Workflow enforces three Sentinel policies defined in `sentinel/sentinel.hcl`:

| Policy File | Enforcement Level | What It Checks |
|---|---|---|
| `require-tags.sentinel` | hard-mandatory | All `aws_instance` resources must carry tags: `Name`, `Pipeline`, `Environment` |
| `restrict-instance-types.sentinel` | soft-mandatory | `aws_instance` must use one of: `t2.micro`, `t2.small`, `t3.micro`, `t3.small` |
| `enforce-s3-encryption.sentinel` | hard-mandatory | Every `aws_s3_bucket` must have a corresponding `aws_s3_bucket_server_side_encryption_configuration` |

**Enforcement level rules:**
- `hard-mandatory`: violation blocks the plan; cannot be overridden.
- `soft-mandatory`: violation blocks the plan but can be overridden with an explicit user acknowledgment.

---

## Step 1 -- Load Policy Context

1. Use `read_file` on `sentinel/sentinel.hcl` to confirm the current enforcement configuration.
2. Use `read_file` on each policy source file:
   - `sentinel/require-tags.sentinel`
   - `sentinel/restrict-instance-types.sentinel`
   - `sentinel/enforce-s3-encryption.sentinel`
3. Summarize each policy to the user: what it checks, what it allows, and what it blocks.
4. Note any policies recently changed (use `git log --oneline -5 sentinel/` if needed).

---

## Step 2 -- Identify the Proposed Change Scope

1. Ask the user what Terraform change is being evaluated, or use `git diff` to identify modified
   `.tf` and `.tfvars` files:
   ```bash
   git diff --name-only HEAD | grep -E '\.(tf|tfvars|yaml)$'
   ```
2. For each changed file, use `read_file` to load its current content.
3. Classify the change scope:
   - **EC2 instance change**: requires evaluation of `require-tags` and `restrict-instance-types`.
   - **S3 bucket change**: requires evaluation of `enforce-s3-encryption`.
   - **Port / security group change**: no Sentinel policy directly applies; note this as INFO.
   - **Variable-only change**: evaluate whether any instance type or tag values are affected.

---

## Step 3 -- Static Pre-Flight Policy Evaluation

Before running `sentinel test`, perform a static evaluation against the loaded policy rules.

### 3a -- require-tags.sentinel (hard-mandatory)

1. Check all `aws_instance` resource blocks in the changed `.tf` files.
2. For each instance, verify the `tags` block contains all three mandatory tags:
   - `Name`
   - `Pipeline`
   - `Environment`
3. Check `*.auto.tfvars` for tag value definitions passed via variables.
4. Report:
   - PASS: all instances carry the three required tags.
   - FAIL (CRITICAL): one or more instances are missing a required tag. List the resource
     address and the missing tag name(s).

### 3b -- restrict-instance-types.sentinel (soft-mandatory)

1. Check all `aws_instance` resource blocks and variable references for `instance_type`.
2. Allowed types: `t2.micro`, `t2.small`, `t3.micro`, `t3.small`.
3. Report:
   - PASS: all instance types are in the allowed list.
   - FAIL (HIGH): one or more instances use a disallowed type. List the resource address
     and the disallowed type. Note that this is soft-mandatory and can be overridden.
   - ADVISORY: if the instance type is set via a variable, note the variable name and
     flag that the runtime value must be verified.

### 3c -- enforce-s3-encryption.sentinel (hard-mandatory)

1. Check for all `aws_s3_bucket` resource blocks in the changed `.tf` files.
2. For each bucket, verify a corresponding `aws_s3_bucket_server_side_encryption_configuration`
   resource exists in the same plan scope.
3. Report:
   - PASS: every bucket has a paired encryption configuration.
   - FAIL (CRITICAL): one or more buckets lack an encryption configuration. List the bucket
     resource address.
   - N/A: no S3 buckets in the change scope.

---

## Step 4 -- Run Sentinel Test Suite

1. Run the full Sentinel test suite against the local policy files:
   ```bash
   cd sentinel && sentinel test
   ```
2. Parse the output per policy:
   - A line containing `PASS` for a policy file = policy passes.
   - A line containing `FAIL` for a policy file = policy fails; capture the error message.
3. Report the raw `sentinel test` output alongside the parsed summary.

---

## Step 5 -- Static Credential and Secret Scan

1. Search all changed `.tf` and `.tfvars` files for static AWS credential patterns:
   ```bash
   grep -rn "AKIA\|aws_secret_access_key\|aws_access_key_id" terraform/
   ```
2. Search for any hardcoded Vault tokens:
   ```bash
   grep -rn "vault_token\s*=\s*\"[^$]" terraform/
   ```
3. Report any findings as CRITICAL. A clean scan returns:
   ```
   PASS: No static credentials detected in Terraform files.
   ```

---

## Step 6 -- Vault Dynamic Credential Verification

1. Use `read_file` on `terraform/ec2/main.tf` (and any other `.tf` files in scope).
2. Confirm the following Vault data sources are present:
   - `data "vault_aws_access_credentials" "creds"` with `role = "demo-role"`
   - `data "vault_kv_secret_v2" "hcp_packer"` scoped appropriately
3. Verify that AWS provider credentials are sourced from the Vault data source, not from
   static variables or environment variable hardcodes.
4. Report:
   - PASS: Vault dynamic credentials confirmed; no static credential references.
   - WARN: Vault data sources found but static fallback credentials also present.
   - FAIL (CRITICAL): No Vault dynamic credential sources; static credentials in use.

---

## Step 7 -- Port Exposure Review

1. Use `read_file` on `terraform/ec2/ports.yaml`.
2. Cross-reference each ingress port against `ansible/baseline-config.yaml` `expected_ports`
   (22, 80, 443 by default).
3. Flag any port in `ports.yaml` not in the baseline expected_ports list as:
   - MEDIUM if it is a well-known application port (e.g., 8080, 8443, 3000).
   - HIGH if it is an unusual or sensitive port (e.g., database ports, admin consoles).
4. Report all extra ports with their description from `ports.yaml` and the recommended action
   (document the justification, restrict the CIDR, or remove the rule).

---

## Step 8 -- Generate Compliance Report

Produce a final structured compliance report:

```markdown
## Sentinel Audit Report

**Scope**: <list of changed files>
**Evaluated**: <date/time if available>

### Policy Compliance

| Policy | Enforcement | Result | Notes |
|---|---|---|---|
| require-tags | hard-mandatory | PASS/FAIL | <details> |
| restrict-instance-types | soft-mandatory | PASS/FAIL | <details> |
| enforce-s3-encryption | hard-mandatory | PASS/FAIL | <details> |

### Credential & Secret Scan
<PASS or CRITICAL findings>

### Vault Dynamic Credentials
<PASS / WARN / FAIL>

### Port Exposure Review
<PASS or findings list>

### Soft-Mandatory Override Log
<List any soft-mandatory failures the user explicitly acknowledged, or "None">

---
### Verdict: GO / NO-GO

**Reason**: <1-2 sentences summarizing the verdict>
```

- **GO**: all hard-mandatory policies pass, no CRITICAL credential findings, and any
  soft-mandatory failures have been explicitly acknowledged by the user.
- **NO-GO**: any hard-mandatory policy fails OR any CRITICAL credential or secret finding exists.

---

## Handling Soft-Mandatory Overrides

If `restrict-instance-types` fails (soft-mandatory) and the user wants to proceed:

1. Print the policy failure message and the disallowed instance type(s).
2. Ask the user to explicitly confirm: "Do you acknowledge this soft-mandatory policy violation
   and want to proceed?"
3. Record the override in the compliance report under "Soft-Mandatory Override Log" with the
   instance resource, disallowed type, and the user's acknowledgment.
4. Do not proceed to provisioning without this explicit confirmation.
