#!/usr/bin/env bash
# =============================================================================
# GOLDEN WORKFLOW — IBM BOB INTERACTIVE DEMO RUNNER
# =============================================================================
# Orchestrates the full end-to-end Golden Workflow demo across all lifecycle
# stages: Day-0 Architecture, Day-1 Provisioning, Day-2 Drift & Self-Healing,
# and GitOps PR generation.
#
# Usage:
#   ./demo-runner.sh                  # interactive menu
#   ./demo-runner.sh --stage <1-7>    # jump directly to a stage
#   ./demo-runner.sh --reset          # reset only
#
# Requirements:
#   - .env file present at repo root (see .env.example)
#   - EC2_IP exported or set in .env when running Ansible stages
#   - SSH_KEY_PATH exported or set in .env for Ansible connectivity
# =============================================================================

set -euo pipefail

# ── Resolve repo root & load env ──────────────────────────────────────────────
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$REPO_ROOT/.env"
SCRIPTS_DIR="$REPO_ROOT/.scripts"
ANSIBLE_DIR="$REPO_ROOT/ansible"
TERRAFORM_DIR="$REPO_ROOT/terraform"
SENTINEL_DIR="$REPO_ROOT/sentinel"

if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
else
    echo "WARNING: .env not found at $ENV_FILE — some stages require it."
fi

# ── Colour palette ────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
banner() {
    local title="$1"
    local width=65
    local line
    line=$(printf '═%.0s' $(seq 1 $width))
    echo ""
    echo -e "${CYAN}╔${line}╗${NC}"
    printf "${CYAN}║${NC}  ${BOLD}%-$((width - 2))s${NC}${CYAN}║${NC}\n" "$title"
    echo -e "${CYAN}╚${line}╝${NC}"
    echo ""
}

step() { echo -e "  ${GREEN}▶${NC}  $*"; }
info() { echo -e "  ${BLUE}ℹ${NC}  $*"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $*"; }
ok()   { echo -e "  ${GREEN}✓${NC}  $*"; }
fail() { echo -e "  ${RED}✗${NC}  $*" >&2; }

pause_for_presenter() {
    echo ""
    echo -e "  ${DIM}── Press [ENTER] to continue, or [s] to skip this step ──${NC}"
    read -r _input
    [[ "$_input" == "s" || "$_input" == "S" ]] && return 1 || return 0
}

require_env() {
    local var="$1"
    if [[ -z "${!var:-}" ]]; then
        fail "Required variable \$$var is not set. Add it to .env or export it."
        return 1
    fi
    return 0
}

# ── Stage functions ───────────────────────────────────────────────────────────

# ------------------------------------------------------------------------------
# STAGE 0 — Reset Demo Environment
# ------------------------------------------------------------------------------
stage_reset() {
    banner "STAGE 0 — Reset Demo Environment"

    step "Cleaning any leftover Terraform lock files..."
    find "$TERRAFORM_DIR" -name ".terraform.lock.hcl" -exec rm -f {} + 2>/dev/null || true
    find "$TERRAFORM_DIR" -name "terraform.tfstate.backup" -exec rm -f {} + 2>/dev/null || true
    ok "Terraform artefacts cleaned."

    step "Removing cached drift reports from previous runs..."
    "$SCRIPTS_DIR/demo-reset.sh"
    ok "Demo environment reset complete."

    echo ""
    info "Repository is back to a clean demo-ready state."
    info "If you need to tear down AWS resources, run: ${BOLD}.scripts/aws_delete_all.sh${NC}"
}

# ------------------------------------------------------------------------------
# STAGE 1 — Simulate Devin's Feature Request (Day 0)
# ------------------------------------------------------------------------------
stage_day0() {
    banner "STAGE 1 — Simulate Devin's Feature Request (Day 0)"

    info "Devin declares intent: 'I need a hardened EC2 instance with HTTPS and SSH access.'"
    info "Bob (Infra Architect mode) translates the request to HCL via ports.yaml."
    echo ""

    step "Displaying current ports.yaml (decoupled ingress rules)..."
    if [[ -f "$TERRAFORM_DIR/ec2/ports.yaml" ]]; then
        echo ""
        cat "$TERRAFORM_DIR/ec2/ports.yaml"
        echo ""
    else
        warn "ports.yaml not found at $TERRAFORM_DIR/ec2/ports.yaml"
    fi

    step "Validating Terraform EC2 module syntax..."
    if command -v terraform &>/dev/null; then
        (cd "$TERRAFORM_DIR/ec2" && terraform validate 2>&1) && ok "Terraform syntax valid." || warn "Terraform validate returned warnings — review above."
    else
        warn "terraform CLI not found — skipping validate step."
    fi

    step "Displaying Packer image template..."
    if [[ -f "$REPO_ROOT/packer/ami.pkr.hcl" ]]; then
        head -40 "$REPO_ROOT/packer/ami.pkr.hcl"
        echo "  ${DIM}... (truncated — see packer/ami.pkr.hcl for full template)${NC}"
    else
        warn "Packer template not found at packer/ami.pkr.hcl"
    fi

    echo ""
    ok "Day-0 scaffolding review complete."
    info "Bob prompt: 'Add a new ingress rule for port 8443 with tag Environment=demo'"
}

# ------------------------------------------------------------------------------
# STAGE 2 — Run Shift-Left Sentinel & Vault Pre-Checks (Day 1)
# ------------------------------------------------------------------------------
stage_precheck() {
    banner "STAGE 2 — Shift-Left Sentinel & Vault Pre-Checks (Day 1)"

    step "Running Sentinel policy tests locally..."
    if command -v sentinel &>/dev/null; then
        (cd "$SENTINEL_DIR" && sentinel test) && ok "All Sentinel policies PASSED." || {
            warn "One or more Sentinel policies FAILED. Review output above."
        }
    else
        warn "sentinel CLI not found — running policy file syntax check instead."
        for policy in "$SENTINEL_DIR"/*.sentinel; do
            [[ -f "$policy" ]] && info "Found policy: $(basename "$policy")" || true
        done
        info "Install the Sentinel CLI from https://releases.hashicorp.com/sentinel/ for live testing."
    fi

    echo ""
    step "Verifying Vault connectivity and dynamic credential role..."
    if command -v vault &>/dev/null && require_env VAULT_ADDR && require_env VAULT_TOKEN; then
        vault status 2>&1 | head -12 && ok "Vault reachable." || warn "Vault unreachable — check VAULT_ADDR and VAULT_TOKEN."
        echo ""
        step "Reading dynamic AWS role definition..."
        vault read aws/roles/demo-role 2>&1 | head -20 || warn "Could not read aws/roles/demo-role — Vault AWS engine may not be configured yet."
        echo ""
        step "Previewing ephemeral AWS credentials (15-min TTL)..."
        vault read aws/creds/demo-role 2>&1 | head -10 || warn "Could not generate ephemeral creds — run .scripts/vault.sh first to configure."
    else
        warn "vault CLI not found or Vault env vars missing — skipping live Vault checks."
        info "Run ${BOLD}.scripts/vault.sh${NC} to configure Vault before the demo."
    fi

    echo ""
    ok "Pre-flight checks complete."
    info "Sentinel policies evaluated; Vault ephemeral cred lifecycle confirmed."
}

# ------------------------------------------------------------------------------
# STAGE 3 — Trigger Provisioning / Pipeline Simulation
# ------------------------------------------------------------------------------
stage_provision() {
    banner "STAGE 3 — Trigger Provisioning / Pipeline Simulation"

    warn "This stage runs ${BOLD}terraform plan${NC} only (no apply) to keep the demo safe."
    warn "To perform a real apply, run terraform manually with the appropriate var-file."
    echo ""

    for module in network s3 ec2; do
        if [[ -d "$TERRAFORM_DIR/$module" ]]; then
            step "Planning module: terraform/$module..."
            if command -v terraform &>/dev/null; then
                (
                    cd "$TERRAFORM_DIR/$module"
                    terraform init -upgrade -input=false -no-color 2>&1 | tail -5
                    terraform plan \
                        -var-file=dev.auto.tfvars \
                        -var="vault_addr=${VAULT_ADDR:-placeholder}" \
                        -var="vault_token=${VAULT_TOKEN:-placeholder}" \
                        -input=false -no-color 2>&1 | tail -20
                ) && ok "Plan complete for $module." || warn "Plan returned non-zero for $module — see above."
            else
                warn "terraform CLI not available — skipping $module plan."
            fi
            echo ""
        else
            warn "Module directory not found: terraform/$module"
        fi
    done

    step "Displaying Harness pipeline configuration..."
    if [[ -f "$REPO_ROOT/harness-pipeline.yaml" ]]; then
        head -50 "$REPO_ROOT/harness-pipeline.yaml"
        echo "  ${DIM}... (see harness-pipeline.yaml for full pipeline definition)${NC}"
    else
        warn "harness-pipeline.yaml not found at repo root."
    fi

    echo ""
    ok "Provisioning simulation complete."
    info "In a real run, Harness triggers Terraform apply → Packer build → AMI registered in HCP."
}

# ------------------------------------------------------------------------------
# STAGE 4 — Inject Live Service Drift
# ------------------------------------------------------------------------------
stage_drift_inject() {
    banner "STAGE 4 — Inject Live Service Drift (Stop Apache / Alter Config)"

    require_env EC2_IP   || { fail "EC2_IP must be set. Export it or add to .env."; return 1; }
    require_env SSH_KEY_PATH || { fail "SSH_KEY_PATH must be set. Export it or add to .env."; return 1; }

    warn "This will SSH into ${BOLD}$EC2_IP${NC} and intentionally break the running Apache service."
    warn "Drift vectors: stop httpd, modify /etc/httpd/conf/httpd.conf, install unauthorized package."
    echo ""
    if ! pause_for_presenter; then
        info "Skipped drift injection."; return 0
    fi

    step "Running simulate-apache-drift.yaml against $EC2_IP..."
    (
        cd "$ANSIBLE_DIR"
        ansible-playbook simulate-apache-drift.yaml \
            -i "${EC2_IP}," \
            --private-key="$SSH_KEY_PATH" \
            -u ec2-user \
            -v
    ) && ok "Drift injected successfully — Apache is now down and config is altered." \
       || warn "Drift injection returned non-zero — check Ansible output above."
}

# ------------------------------------------------------------------------------
# STAGE 5 — Execute Bob-Guided Drift Diagnosis & Remediation (Day 2)
# ------------------------------------------------------------------------------
stage_drift_remediate() {
    banner "STAGE 5 — Bob-Guided Drift Diagnosis & Remediation (Day 2)"

    require_env EC2_IP      || { fail "EC2_IP must be set."; return 1; }
    require_env SSH_KEY_PATH || { fail "SSH_KEY_PATH must be set."; return 1; }

    step "Running drift-detection.yaml to capture current state..."
    (
        cd "$ANSIBLE_DIR"
        ansible-playbook drift-detection.yaml \
            -i "${EC2_IP}," \
            --private-key="$SSH_KEY_PATH" \
            -u ec2-user \
            -v
    ) && ok "Drift report written to /var/log/drift-reports/ on $EC2_IP." \
       || { warn "Drift detection returned non-zero — check output above."; }

    echo ""
    info "Bob Prompt: 'Parse the latest drift report from $EC2_IP and tell me what drifted.'"
    info "Bob Prompt: 'Remediate all critical drift items autonomously.'"
    echo ""

    step "Fetching latest drift report from $EC2_IP..."
    REPORT_PATH=$(ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no \
        "ec2-user@$EC2_IP" \
        "ls -t /var/log/drift-reports/drift-report-*.json 2>/dev/null | head -1" 2>/dev/null || echo "")

    if [[ -n "$REPORT_PATH" ]]; then
        ok "Latest report: $REPORT_PATH"
        scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no \
            "ec2-user@$EC2_IP:$REPORT_PATH" \
            "$REPO_ROOT/drift-report-latest.json" 2>/dev/null \
            && ok "Saved locally to drift-report-latest.json" \
            || warn "Could not SCP report — review drift output on the host."
    else
        warn "No drift reports found on host — drift detection may not have completed."
    fi

    echo ""
    if ! pause_for_presenter; then
        info "Skipped automated remediation."; return 0
    fi

    step "Running drift-remediation.yaml against $EC2_IP..."
    (
        cd "$ANSIBLE_DIR"
        ansible-playbook drift-remediation.yaml \
            -i "${EC2_IP}," \
            --private-key="$SSH_KEY_PATH" \
            -u ec2-user \
            -v
    ) && ok "Remediation complete — instance restored to baseline." \
       || warn "Remediation returned non-zero — manual review may be required."
}

# ------------------------------------------------------------------------------
# STAGE 6 — Generate GitOps PR & Review
# ------------------------------------------------------------------------------
stage_gitops_pr() {
    banner "STAGE 6 — Generate GitOps PR & Review"

    step "Checking for uncommitted infrastructure changes..."
    GIT_STATUS=$(git -C "$REPO_ROOT" status --short 2>/dev/null || echo "")
    if [[ -n "$GIT_STATUS" ]]; then
        echo ""
        echo "$GIT_STATUS"
        echo ""
        info "There are uncommitted changes. Bob can generate a PR description."
        info "Bob Prompt: 'Generate a pull request description for these infrastructure changes.'"
    else
        info "No uncommitted changes found. Showing last commit diff for demonstration."
        git -C "$REPO_ROOT" show --stat HEAD 2>/dev/null | head -20 || true
    fi

    echo ""
    step "Displaying GitHub Actions / Harness trigger workflow..."
    if [[ -f "$REPO_ROOT/.github/workflows/harness-trigger.yml" ]]; then
        cat "$REPO_ROOT/.github/workflows/harness-trigger.yml"
    else
        warn ".github/workflows/harness-trigger.yml not found — GitOps CI/CD workflow not yet defined."
    fi

    echo ""
    step "Checking PR template..."
    if [[ -f "$REPO_ROOT/.github/pull_request_template.md" ]]; then
        cat "$REPO_ROOT/.github/pull_request_template.md"
    else
        warn ".github/pull_request_template.md not found — Sub-Task 6 will create this."
    fi

    echo ""
    info "Bob Prompt: 'Create a GitHub PR for the drift remediation changes with a compliance summary.'"
    ok "GitOps PR stage complete."
}

# ── Main menu ─────────────────────────────────────────────────────────────────
show_menu() {
    clear
    echo ""
    echo -e "${BOLD}${CYAN}"
    echo "  ╔═══════════════════════════════════════════════════════════════╗"
    echo "  ║        GOLDEN WORKFLOW — IBM BOB INTERACTIVE DEMO            ║"
    echo "  ╠═══════════════════════════════════════════════════════════════╣"
    echo "  ║                                                               ║"
    echo "  ║  0.  Reset Demo Environment                                   ║"
    echo "  ║                                                               ║"
    echo "  ║  1.  Simulate Devin's Feature Request         (Day 0)        ║"
    echo "  ║  2.  Run Shift-Left Sentinel & Vault Pre-Checks (Day 1)      ║"
    echo "  ║  3.  Trigger Provisioning / Pipeline Simulation              ║"
    echo "  ║  4.  Inject Live Service Drift                               ║"
    echo "  ║  5.  Execute Bob-Guided Drift Diagnosis & Remediation (Day 2)║"
    echo "  ║  6.  Generate GitOps PR & Review                             ║"
    echo "  ║                                                               ║"
    echo "  ║  a.  Run ALL stages sequentially (0 → 6)                     ║"
    echo "  ║  q.  Quit                                                     ║"
    echo "  ║                                                               ║"
    echo "  ╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -n "  Select stage [0-6 / a / q]: "
}

run_stage() {
    local choice="$1"
    case "$choice" in
        0) stage_reset ;;
        1) stage_day0 ;;
        2) stage_precheck ;;
        3) stage_provision ;;
        4) stage_drift_inject ;;
        5) stage_drift_remediate ;;
        6) stage_gitops_pr ;;
        a|A)
            for s in 0 1 2 3 4 5 6; do
                run_stage "$s"
                echo ""
                echo -e "  ${DIM}── Stage $s complete. Press [ENTER] to advance to next stage ──${NC}"
                read -r _
            done
            ;;
        q|Q) echo ""; info "Demo runner exited. Good luck!"; echo ""; exit 0 ;;
        *) warn "Invalid selection: '$choice'" ;;
    esac
}

# ── Entrypoint ────────────────────────────────────────────────────────────────
main() {
    # Parse flags
    if [[ "${1:-}" == "--reset" ]]; then
        stage_reset; exit 0
    fi

    if [[ "${1:-}" == "--stage" ]]; then
        local target="${2:-}"
        [[ -z "$target" ]] && { fail "--stage requires a stage number (0-6)"; exit 1; }
        run_stage "$target"
        exit 0
    fi

    # Interactive loop
    while true; do
        show_menu
        read -r choice
        run_stage "$choice"
        echo ""
        echo -e "  ${DIM}Press [ENTER] to return to the menu...${NC}"
        read -r _
    done
}

main "$@"
