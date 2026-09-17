# EC2 Drift Detection & Remediation Guide

## Overview

This guide explains the Day-2 self-healing loop that keeps Golden Workflow EC2
instances in their **baseline "golden state"** at all times. Bob acts as the
intelligent triage layer: it reads structured JSON drift reports, classifies
findings by severity, and orchestrates targeted Ansible remediation playbooks —
all through natural-language conversation.

---

## Architecture

### Components

| Component | Path | Purpose |
|---|---|---|
| Baseline Config | `ansible/baseline-config.yaml` | Defines the golden state: packages, services, files, ports |
| Drift Detection Role | `ansible/roles/ec2_drift_detection/` | Compares instance vs. baseline; writes structured JSON report |
| Drift Remediation Role | `ansible/roles/ec2_drift_remediation/` | Restores baseline; writes structured JSON remediation report |
| Drift Detection Playbook | `ansible/drift-detection.yaml` | Entrypoint for detection runs |
| Drift Remediation Playbook | `ansible/drift-remediation.yaml` | Entrypoint for remediation runs |
| Drift Simulation Playbook | `ansible/simulate-apache-drift.yaml` | Injects controlled drift for demo/testing |
| Bob `drift-remediation` Skill | `.bob/skills/drift-remediation/SKILL.md` | Bob skill: parses JSON reports and triggers Ansible |

---

## Day-2 Bob Autonomous Self-Healing Loop

```
┌──────────────────────────────────────────────────────────────────────────┐
│                     DAY-2 SELF-HEALING LOOP                              │
│                                                                          │
│  1. TRIGGER          2. DETECT           3. REPORT           4. TRIAGE   │
│  ─────────           ────────            ────────            ───────     │
│  Scheduled /         Ansible runs        JSON written to     Bob reads   │
│  pipeline /          ec2_drift_          /var/log/drift-     report, →   │
│  manual              detection role      reports/            classifies  │
│                      against baseline    drift-report-       by severity │
│                                          <epoch>.json                    │
│                                                                          │
│  5. REMEDIATE        6. VERIFY           7. REPORT           8. CLOSE    │
│  ──────────          ────────            ────────            ───────     │
│  Bob triggers        Bob re-runs         JSON written to     Bob         │
│  drift-              detection or        remediation-        confirms    │
│  remediation.yaml    wait_for checks     report-<epoch>      outcome     │
│                                          .json               to Devin    │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## JSON Report Schemas (v1)

All reports are written to `/var/log/drift-reports/` on the managed EC2 node.

### Drift Report — `drift-report-<epoch>.json`

```json
{
  "schema_version": "1",
  "timestamp": "2024-11-01T14:23:07Z",
  "hostname": "ip-10-0-1-100",
  "instance_id": "i-0abc1234def56789",
  "drift_detected": true,
  "drift_count": 3,
  "has_critical": true,
  "summary": {
    "critical": 2,
    "high": 1,
    "medium": 0,
    "low": 0
  },
  "drifts": [
    {
      "type": "apache_service_down",
      "severity": "critical",
      "service": "httpd",
      "expected_state": "active",
      "actual_state": "inactive",
      "message": "Apache web server is not running - service may have crashed or been stopped"
    },
    {
      "type": "apache_port_not_listening",
      "severity": "critical",
      "port": 80,
      "message": "Apache is not accepting connections on port 80"
    },
    {
      "type": "missing_packages",
      "severity": "high",
      "details": ["aide"]
    }
  ]
}
```

#### Drift Object Field Reference

| Field | Type | Present On | Description |
|---|---|---|---|
| `type` | string | all | Drift category identifier (see table below) |
| `severity` | string | all | `critical` \| `high` \| `medium` \| `low` |
| `service` | string | service drifts | Systemd unit name |
| `expected_state` | string | service/apache drifts | Expected systemd ActiveState |
| `actual_state` | string | service/apache drifts | Observed systemd ActiveState |
| `expected_enabled` | bool | service drifts | Expected UnitFileState |
| `actual_enabled` | string | service drifts | Observed UnitFileState |
| `file` | string | file drifts | Absolute path to monitored file |
| `expected_mode` | string | permission drifts | Expected octal mode, e.g. `"0644"` |
| `actual_mode` | string | permission drifts | Observed octal mode |
| `expected_owner` | string | permission drifts | Expected file owner (username) |
| `actual_owner` | string | permission drifts | Observed file owner |
| `expected_group` | string | permission drifts | Expected file group |
| `actual_group` | string | permission drifts | Observed file group |
| `port` | integer | port drifts | Port number (unexpected or not listening) |
| `details` | string\|list | various | Human-readable detail or list of package names |
| `aide_output` | list[string] | AIDE drifts | Relevant AIDE stdout lines |
| `message` | string | Apache/AIDE | Short human-readable description |

#### Drift Type Catalogue

| `type` | Severity | Trigger |
|---|---|---|
| `missing_packages` | high | Required package absent from system |
| `forbidden_packages` | critical | Blacklisted package installed |
| `service_drift` | high | Required service not running or not enabled |
| `apache_service_down` | critical | httpd not in `active` ActiveState |
| `apache_port_not_listening` | critical | Nothing listening on port 80 |
| `apache_config_error` | high | `httpd -t` returns non-zero |
| `missing_config_file` | high | Monitored file does not exist |
| `config_file_permissions` | medium | Mode, owner, or group mismatch |
| `file_integrity_violation` | critical | AIDE --check returned non-zero |
| `unexpected_ports` | high | Ports listening beyond expected set |

---

### Remediation Report — `remediation-report-<epoch>.json`

```json
{
  "schema_version": "1",
  "timestamp": "2024-11-01T14:25:12Z",
  "hostname": "ip-10-0-1-100",
  "instance_id": "i-0abc1234def56789",
  "drift_report_source": "/var/log/drift-reports/drift-report-1730465987.json",
  "outcome": "success",
  "remediation_count": 4,
  "actions": [
    {
      "action": "restart_apache",
      "status": "success",
      "message": "Apache web server restarted and enabled",
      "detail": { "previous_state": "inactive" }
    },
    {
      "action": "verify_apache_port_80",
      "status": "success",
      "message": "Apache is accepting connections on port 80",
      "detail": { "port": 80 }
    },
    {
      "action": "install_packages",
      "status": "success",
      "message": "Missing required packages installed",
      "detail": { "packages": ["aide"] }
    },
    {
      "action": "verify_apache_config",
      "status": "success",
      "message": "Apache configuration syntax is valid",
      "detail": { "rc": 0, "stderr": [] }
    }
  ]
}
```

#### Outcome Values

| `outcome` | Meaning |
|---|---|
| `success` | All actions taken, none failed |
| `partial` | Some actions taken, one or more failed — manual follow-up needed |
| `no_action_needed` | No changes were required; system was already at baseline |

#### Action Status Values

| `status` | Meaning |
|---|---|
| `success` | Action completed without errors |
| `warning` | Action completed with non-fatal warnings (e.g., config syntax warnings) |
| `failed` | Action did not succeed; `error` field contains details |

---

## Bob Interaction — Step-by-Step Self-Healing Walkthrough

The following exact prompts demonstrate how Bob drives the full Day-2 cycle.
Copy-paste these into Bob during a live demo or practise session.

### Step 1 — Inject Drift (Demo Setup)

```
Simulate Apache drift on the EC2 instance at 54.x.x.x using the
simulate-apache-drift.yaml playbook.
```

> Bob will run:
> ```bash
> cd ansible && ansible-playbook simulate-apache-drift.yaml \
>   -i "54.x.x.x," --private-key="$SSH_KEY_PATH" -u ec2-user
> ```

---

### Step 2 — Trigger Drift Detection

```
Run drift detection against 54.x.x.x and fetch the latest drift report
from /var/log/drift-reports/ so I can review it.
```

> Bob will run detection and SCP the report locally:
> ```bash
> cd ansible && ansible-playbook drift-detection.yaml \
>   -i "54.x.x.x," --private-key="$SSH_KEY_PATH" -u ec2-user
>
> scp -i "$SSH_KEY_PATH" \
>   ec2-user@54.x.x.x:/var/log/drift-reports/drift-report-*.json \
>   ./drift-report-latest.json
> ```

---

### Step 3 — Bob Parses and Summarises the Report

```
Parse drift-report-latest.json and give me a structured triage summary.
Tell me the total drift count, whether anything is critical, and list
each finding with its severity and recommended action.
```

**Example Bob response (based on the schema):**

> **Drift Triage — `ip-10-0-1-100` (`i-0abc1234def56789`)**
> Timestamp: `2024-11-01T14:23:07Z`
>
> | Field | Value |
> |---|---|
> | Total Drifts | 3 |
> | Critical | **2** ⚠️ |
> | High | 1 |
> | Medium/Low | 0 |
>
> **Findings:**
>
> | # | Type | Severity | Key Detail |
> |---|---|---|---|
> | 1 | `apache_service_down` | 🔴 CRITICAL | httpd `inactive` — expected `active` |
> | 2 | `apache_port_not_listening` | 🔴 CRITICAL | Port 80 not accepting connections |
> | 3 | `missing_packages` | 🟠 HIGH | `aide` not installed |
>
> **Recommendation:** Run `drift-remediation.yaml` immediately.
> Critical service downtime is impacting port 80 availability.

---

### Step 4 — Bob Triggers Targeted Remediation

```
Remediate the drift on 54.x.x.x using drift-remediation.yaml, passing
in the latest drift report path so remediation is targeted.
```

> Bob will run:
> ```bash
> cd ansible && ansible-playbook drift-remediation.yaml \
>   -i "54.x.x.x," \
>   --private-key="$SSH_KEY_PATH" \
>   -u ec2-user \
>   -e "drift_report_file=/var/log/drift-reports/drift-report-1730465987.json"
> ```

---

### Step 5 — Bob Fetches and Validates the Remediation Report

```
Fetch the latest remediation report from the instance and confirm the
outcome. Were there any failed actions? Is Apache back online?
```

**Bob will SCP the report and parse it:**

```python
# Bob's internal JSON parsing logic (shown for transparency)
report = json.load(open("remediation-report-latest.json"))

assert report["outcome"] == "success"
failed = [a for a in report["actions"] if a["status"] == "failed"]
apache_ok = any(
    a["action"] == "verify_apache_port_80" and a["status"] == "success"
    for a in report["actions"]
)
```

**Example Bob response:**

> **Remediation Report — `ip-10-0-1-100`**
>
> | Field | Value |
> |---|---|
> | Outcome | ✅ SUCCESS |
> | Actions Taken | 4 |
> | Failed | 0 |
>
> **Action Log:**
> - ✅ `restart_apache` — httpd restarted (was `inactive`)
> - ✅ `verify_apache_port_80` — port 80 accepting connections
> - ✅ `install_packages` — `aide` reinstalled
> - ✅ `verify_apache_config` — configuration syntax valid
>
> System is fully restored to baseline. No manual intervention needed.

---

### Step 6 — Verification Re-Run (Optional but Recommended)

```
Run drift detection one more time to confirm zero drift after remediation.
```

> Bob re-runs detection. Expected clean report:
> ```json
> {
>   "drift_detected": false,
>   "drift_count": 0,
>   "has_critical": false,
>   "summary": { "critical": 0, "high": 0, "medium": 0, "low": 0 },
>   "drifts": []
> }
> ```

---

## Multi-Vector Drift Scenarios

### Scenario A — Apache Service Down

**What drifted:** `httpd` stopped, port 80 not listening.

**Detected drifts:**
```json
[
  { "type": "apache_service_down", "severity": "critical", "actual_state": "inactive" },
  { "type": "apache_port_not_listening", "severity": "critical", "port": 80 }
]
```

**Bob remediation prompt:**
```
Apache is critical — restart it on 54.x.x.x immediately and verify port 80 recovers.
```

**Remediation actions taken:**
- `restart_apache` → httpd restarted and enabled
- `verify_apache_port_80` → confirmed port 80 accepting connections
- `verify_apache_config` → config syntax validated

---

### Scenario B — Unauthorized Package Installed

**What drifted:** `telnet` installed on instance.

**Detected drift:**
```json
{ "type": "forbidden_packages", "severity": "critical", "details": ["telnet"] }
```

**Bob remediation prompt:**
```
A forbidden package "telnet" has been detected. Remove it immediately
and generate a remediation report.
```

**Remediation actions taken:**
- `remove_packages` → `telnet` removed via `yum remove`

---

### Scenario C — Configuration File Permission Tampering

**What drifted:** `/etc/ssh/sshd_config` permissions changed from `0600` to `0644`.

**Detected drift:**
```json
{
  "type": "config_file_permissions",
  "severity": "medium",
  "file": "/etc/ssh/sshd_config",
  "expected_mode": "0600",
  "actual_mode": "0644"
}
```

**Bob remediation prompt:**
```
sshd_config has incorrect permissions on 54.x.x.x. Fix it back to 0600
and restart sshd.
```

**Remediation actions taken:**
- `fix_permissions` → mode restored to `0600` for `/etc/ssh/sshd_config`
- `harden_ssh` → PermitRootLogin, PasswordAuthentication, X11Forwarding verified
- Handler: `Restart sshd` triggered

---

### Scenario D — AIDE File Integrity Violation

**What drifted:** Unexpected file system changes detected by AIDE.

**Detected drift:**
```json
{
  "type": "file_integrity_violation",
  "severity": "critical",
  "details": "AIDE detected file system changes",
  "aide_output": ["f----- /etc/httpd/conf/httpd.conf"]
}
```

**Bob remediation prompt:**
```
AIDE is reporting file integrity violations. Reinitialize the AIDE
database and explain what was changed.
```

**Remediation actions taken:**
- `reinitialize_aide` → AIDE database rebuilt with `aide --init`

---

## Running Detection & Remediation Manually

### Detect Drift

```bash
cd ansible
ansible-playbook drift-detection.yaml \
  -i "<EC2_IP>," \
  --private-key="$SSH_KEY_PATH" \
  -u ec2-user \
  --ssh-extra-args="-o StrictHostKeyChecking=no"
```

### Detect Drift and Fail on Critical Findings (CI gate)

```bash
ansible-playbook drift-detection.yaml \
  -i "<EC2_IP>," \
  --private-key="$SSH_KEY_PATH" \
  -u ec2-user \
  -e "fail_on_drift=true"
```

### Remediate with Targeted Report

```bash
cd ansible
ansible-playbook drift-remediation.yaml \
  -i "<EC2_IP>," \
  --private-key="$SSH_KEY_PATH" \
  -u ec2-user \
  -e "drift_report_file=/var/log/drift-reports/drift-report-1730465987.json"
```

### Fetch All Reports from Instance

```bash
scp -i /path/to/key.pem \
  "ec2-user@<EC2_IP>:/var/log/drift-reports/*.json" \
  ./drift-reports/
```

---

## Pipeline Integration (Harness)

```
Configure with Ansible
        │
        ▼
Drift Detection Stage      ← ansible-playbook drift-detection.yaml
        │
        ├── drift_detected == false ──► ✅ Pipeline passes
        │
        └── drift_detected == true  ──► Await Manual Approval
                                              │
                                              ▼
                                     Drift Remediation Stage
                                     (drift-remediation.yaml)
                                              │
                                              ▼
                                     Verification Re-run
                                     (drift-detection.yaml)
```

All pipeline stages read Vault for the EC2 private key:

```bash
INSTANCE_IP=$(vault kv get -field=instance_ip secret/ami-pipeline/ec2)
PRIVATE_KEY=$(vault kv get -field=private_key secret/ami-pipeline/ec2)
echo "$PRIVATE_KEY" > /tmp/ec2_key.pem && chmod 600 /tmp/ec2_key.pem

ansible-playbook drift-detection.yaml \
  -i "$INSTANCE_IP," \
  --private-key="$EC2_KEY_PATH" \
  -u ec2-user
```

---

## Vault Integration

```bash
# Required Vault secrets
secret/ami-pipeline/ec2
  instance_ip  : Public IP of EC2 instance
  private_key  : PEM-format SSH private key
  instance_id  : EC2 instance ID

secret/ami-pipeline/github
  token        : GitHub personal access token (for report archiving)
```

---

## Customising the Baseline

Edit [`ansible/baseline-config.yaml`](../ansible/baseline-config.yaml) to adjust
the golden state definition.

```yaml
baseline:
  required_packages:
    - httpd
    - aide
    - fail2ban
    - chrony
    # Add your packages here

  forbidden_packages:
    - telnet
    - rsh
    # Add other dangerous packages

  required_services:
    - name: httpd
      state: started
      enabled: true
    # Add other services

  config_files:
    - path: /path/to/your/config
      owner: root
      group: root
      mode: '0644'

  expected_ports:
    - 22   # SSH
    - 80   # HTTP
    - 443  # HTTPS
    # Add application ports
```

---

## Adding Custom Drift Checks

Extend [`ansible/roles/ec2_drift_detection/tasks/main.yaml`](../ansible/roles/ec2_drift_detection/tasks/main.yaml):

```yaml
- name: Check custom configuration
  ansible.builtin.stat:
    path: /your/custom/path
  register: custom_check

- name: Record custom drift
  ansible.builtin.set_fact:
    drift_detected: true
    drift_report: >-
      {{ drift_report | combine({
        'drifts': drift_report.drifts + [{
          'type': 'custom_check_failed',
          'severity': 'high',
          'file': '/your/custom/path',
          'details': 'Custom configuration file is missing'
        }]
      }) }}
  when: not custom_check.stat.exists
```

---

## Troubleshooting

**1. Drift Detection Cannot Connect to EC2**
```bash
ssh -i /path/to/key.pem ec2-user@<EC2_IP>
vault kv get secret/ami-pipeline/ec2
```

**2. AIDE Check Fails or Database Is Missing**
```bash
sudo aide --init
sudo mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
```
Then re-run detection — the `reinitialize_aide` remediation action handles this automatically.

**3. Remediation Outcome Is `partial`**
- Look at `actions[].status == "failed"` entries and read the `error` field.
- Common cause: `yum` failures due to missing internet access or repo issues.
- Bob prompt: `Show me the failed actions from the remediation report and suggest next steps.`

**4. False Positives**
- A package installed by an AWS bootstrap script may show as `unexpected`.
- Add it to `baseline.required_packages` or `baseline.expected_ports` in `baseline-config.yaml`.

---

## Severity Reference

| Severity | Examples | Bob Action |
|---|---|---|
| 🔴 **Critical** | Apache down, forbidden packages, AIDE violations | Immediate auto-remediation |
| 🟠 **High** | Missing packages, service drift, missing config files | Remediate in current cycle |
| 🟡 **Medium** | File permission drift | Remediate; log for audit |
| ⚪ **Low** | Minor config discrepancies | Log only; review at next cycle |

---

## Best Practices

1. **Run detection before and after every Terraform apply** to catch unexpected side-effects.
2. **Archive reports to S3** for audit trail: `aws s3 cp ./drift-reports/ s3://your-bucket/drift-reports/ --recursive`.
3. **Set `fail_on_drift=true` as a CI gate** so pipelines block on critical findings.
4. **Never modify `baseline-config.yaml` without a PR review** — every change alters what counts as drift.
5. **Treat `has_critical: true` as a security incident** — investigate before remediation to understand root cause.
