## Summary

<!-- Describe what this PR changes and why. One paragraph is enough. -->

---

## Change Type

<!-- Check all that apply -->

- [ ] Infrastructure change (Terraform / ports.yaml / security groups)
- [ ] Ansible playbook / role update
- [ ] Packer image definition
- [ ] Sentinel policy change
- [ ] Vault configuration / credential path
- [ ] CI/CD pipeline update (Harness / GitHub Actions)
- [ ] Documentation only
- [ ] Other: <!-- describe -->

---

## 🤖 Bob Compliance Summary

> **Instructions for the PR author**: Before opening this PR, run Bob's automated pre-merge checks by typing the following prompt in Bob's chat panel:
>
> ```
> Run a full pre-merge compliance check for this PR.
> Summarise Sentinel policy results, Vault credential hygiene, exposed port changes, and any rollback risk.
> ```
>
> Paste Bob's structured output into the section below. If the check cannot be run, fill in the fields manually.

### Sentinel Policy Evaluation

| Policy | Result | Notes |
|--------|--------|-------|
| `require-resource-tags` | `PASS / FAIL` | <!-- e.g. all required tags present --> |
| `restrict-instance-types` | `PASS / FAIL` | <!-- e.g. instance type is t3.medium (approved) --> |
| `enforce-s3-encryption` | `PASS / FAIL` | <!-- e.g. S3 bucket has AES-256 encryption --> |

> Run locally: `cd sentinel && sentinel test`
>
> Expected output: **3/3 policies PASS** before this PR can be merged.

### Vault Credential Hygiene

- [ ] Dynamic credentials used (no static AWS keys in code)
- [ ] Vault role `demo-role` lease TTL ≤ 15 minutes
- [ ] No `vault_token` or `vault_addr` literals committed to source files
- [ ] `VAULT_TOKEN` and `VAULT_ADDR` sourced only from Harness secrets or environment

> Bob prompt: `Audit this PR for any hardcoded Vault tokens or static AWS credentials.`

### Port / Security Group Changes

<!-- Complete only if ports.yaml or security group resources were modified -->

| Port | Protocol | Direction | Justification |
|------|----------|-----------|---------------|
| <!-- e.g. 8080 --> | TCP | Ingress | <!-- e.g. required for app server health checks --> |

- [ ] All new ingress ports have a documented justification above
- [ ] No ports in range 0–1023 opened without explicit approval
- [ ] `terraform/ec2/ports.yaml` is the single source of truth (no hardcoded SG rules in `main.tf`)

> Bob prompt: `Review the ports.yaml diff in this PR and flag any high-risk ingress exposures.`

---

## Infrastructure Plan Summary

<!-- Paste the relevant section of `terraform plan` output here, or a link to the Harness pipeline run. -->

```
# terraform plan output (relevant section)

```

- [ ] `terraform plan` reviewed and outputs match expected scope
- [ ] No unintended resource replacements (`-/+`) in plan output
- [ ] Harness pipeline triggered on this branch and plan stage passed

---

## Rollback Strategy

<!-- Describe how to revert these changes if the pipeline fails post-merge. -->

**Automated rollback** (Harness pipeline failure before merge):
- Pipeline fails → PR stays open → push a fix commit → pipeline re-triggers automatically.
- No manual intervention required for pre-merge failures.

**Manual rollback** (post-merge infrastructure regression):

1. Identify the last known-good commit SHA: `git log --oneline -10`
2. Revert this PR: `git revert -m 1 <merge-commit-sha>`
3. Push the revert branch and open a new PR targeting `main`
4. Pipeline triggers on the revert branch — approve infrastructure destruction / recreation as needed
5. Verify rollback in AWS console and confirm Sentinel policies still pass

> Bob prompt: `Generate a rollback plan for the infrastructure changes in this PR.`

---

## Day-2 Drift Exposure

<!-- Assess whether this change could introduce drift vectors on live EC2 instances. -->

- [ ] No impact on running EC2 instances (new resources only)
- [ ] Change updates existing resources — drift detection playbook run after apply: `bash .scripts/drift-detect.sh <EC2_IP>`
- [ ] Ansible `baseline-config.yaml` updated to match new desired state
- [ ] Drift remediation playbook tested against change: `cd ansible && ansible-playbook drift-remediation.yaml`

---

## Checklist

- [ ] PR title follows `[type]: short description` convention (e.g. `feat: add port 8443 for HTTPS admin`)
- [ ] Branch name is descriptive (e.g. `feat/add-port-8443`, `fix/vault-ttl-policy`)
- [ ] All Sentinel policies pass locally (`sentinel test`)
- [ ] No secrets, tokens, or credentials in committed files
- [ ] `terraform plan` output reviewed
- [ ] `ports.yaml` is the sole source of port definitions (if ports changed)
- [ ] Documentation updated if behaviour changed (`docs/`, `README.md`)
- [ ] Relevant Bob skill invoked and output pasted above

---

## Reviewer Notes

<!-- Anything specific reviewers should focus on, edge cases, or areas of uncertainty. -->
