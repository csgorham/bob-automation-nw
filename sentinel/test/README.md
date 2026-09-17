# Sentinel Policy Test Fixtures

This directory contains `sentinel test` fixtures for the three Golden Workflow policies.  Run them locally (no Terraform Cloud required) with:

```bash
cd sentinel
sentinel test
```

## Structure

```
sentinel/test/
├── require-tags/
│   ├── pass.json                      # Test: all mandatory tags present → PASS
│   ├── mock-tfplan-v2-pass.sentinel   # Mock plan with Name + Pipeline + Environment
│   ├── fail.json                      # Test: missing Pipeline + Environment → FAIL
│   └── mock-tfplan-v2-fail.sentinel   # Mock plan missing required tags
├── restrict-instance-types/
│   ├── pass.json                      # Test: t3.micro (allowed) → PASS
│   ├── mock-tfplan-v2-pass.sentinel   # Mock plan with t3.micro
│   ├── fail.json                      # Test: c5.4xlarge (blocked) → FAIL
│   └── mock-tfplan-v2-fail.sentinel   # Mock plan with c5.4xlarge
└── enforce-s3-encryption/
    ├── pass.json                      # Test: bucket + SSE config present → PASS
    ├── mock-tfplan-v2-pass.sentinel   # Mock plan with KMS encryption
    ├── fail.json                      # Test: bucket with no SSE config → FAIL
    └── mock-tfplan-v2-fail.sentinel   # Mock plan missing encryption resource
```

## Policy Enforcement Levels

| Policy                    | Level          | Effect if Fails                          |
|---------------------------|----------------|------------------------------------------|
| `require-tags`            | hard-mandatory | Plan **blocked**, cannot override        |
| `restrict-instance-types` | soft-mandatory | Plan **blocked**, requires operator override |
| `enforce-s3-encryption`   | hard-mandatory | Plan **blocked**, cannot override        |

## Bob Integration

Bob's `sentinel-audit` skill references these fixtures.  When a developer asks
"Will my changes pass Sentinel?", Bob will:

1. Run `sentinel test` in the `sentinel/` directory.
2. Parse stdout for `PASS` / `FAIL` per policy.
3. On any `FAIL`, quote the policy's `print()` message and recommend a fix.
4. Produce a structured GO / NO-GO compliance report before the PR is created.

### Example Bob Prompt

```
Bob, run Sentinel compliance checks against the current Terraform plan.
```

### Expected Bob Output (all passing)

```
╔══════════════════════════════════════════════════════╗
║         SENTINEL COMPLIANCE REPORT — GO / NO-GO      ║
╠════════════════════════════╦════════════╦════════════╣
║ Policy                     ║ Level      ║ Result     ║
╠════════════════════════════╬════════════╬════════════╣
║ require-tags               ║ hard-mand  ║ ✅ PASS    ║
║ restrict-instance-types    ║ soft-mand  ║ ✅ PASS    ║
║ enforce-s3-encryption      ║ hard-mand  ║ ✅ PASS    ║
╚════════════════════════════╩════════════╩════════════╝
Verdict: ✅ GO — all policies passed. Safe to create PR.
```

### Expected Bob Output (instance type blocked)

```
╔══════════════════════════════════════════════════════╗
║         SENTINEL COMPLIANCE REPORT — GO / NO-GO      ║
╠════════════════════════════╦════════════╦════════════╣
║ Policy                     ║ Level      ║ Result     ║
╠════════════════════════════╬════════════╬════════════╣
║ require-tags               ║ hard-mand  ║ ✅ PASS    ║
║ restrict-instance-types    ║ soft-mand  ║ ❌ FAIL    ║
║ enforce-s3-encryption      ║ hard-mand  ║ ✅ PASS    ║
╚════════════════════════════╩════════════╩════════════╝
Verdict: ❌ NO-GO — 1 policy failed.

Details:
  restrict-instance-types (soft-mandatory)
    Instance aws_instance.web uses disallowed type: c5.4xlarge
    Allowed types: ["t2.micro", "t2.small", "t3.micro", "t3.small"]
    Fix: Update instance_type in dev.auto.tfvars to an allowed value.
```

## Adding a New Test Case

1. Create a new `*.json` file in the relevant policy subdirectory.
2. Create a matching `mock-tfplan-v2-<scenario>.sentinel` mock.
3. Set `"test": { "main": true }` for expected-pass cases and `false` for expected-fail.
4. Run `sentinel test` to verify.
