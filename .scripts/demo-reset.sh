#!/usr/bin/env bash
# =============================================================================
# GOLDEN WORKFLOW — Demo Reset
# =============================================================================
# Cleans all runtime artefacts from a previous demo run so the repo is back
# to a clean, demo-ready state. Safe to run multiple times.
#
# Called by: demo-runner.sh stage 0
# Usage:     ./.scripts/demo-reset.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC}  $*"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $*"; }
info() { echo -e "  ${CYAN}ℹ${NC}  $*"; }

echo ""
echo -e "${CYAN}══════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Golden Workflow — Demo Reset${NC}"
echo -e "${CYAN}══════════════════════════════════════════════${NC}"
echo ""

# ── Remove local drift report ──────────────────────────────────────────────
if [[ -f "$REPO_ROOT/drift-report-latest.json" ]]; then
  rm -f "$REPO_ROOT/drift-report-latest.json"
  ok "Removed drift-report-latest.json"
else
  info "No drift-report-latest.json to remove"
fi

# ── Remove Terraform lock files and backup state ───────────────────────────
find "$REPO_ROOT/terraform" -name ".terraform.lock.hcl" -exec rm -f {} + 2>/dev/null && \
  ok "Removed .terraform.lock.hcl files" || true

find "$REPO_ROOT/terraform" -name "terraform.tfstate.backup" -exec rm -f {} + 2>/dev/null && \
  ok "Removed terraform.tfstate.backup files" || true

find "$REPO_ROOT/terraform" -name "*.tfstate" -not -path "*/.terraform/*" -exec rm -f {} + 2>/dev/null && \
  ok "Removed local .tfstate files" || true

# ── Remove Packer manifest (regenerated on each build) ────────────────────
if [[ -f "$REPO_ROOT/packer/manifest.json" ]]; then
  rm -f "$REPO_ROOT/packer/manifest.json"
  ok "Removed packer/manifest.json"
else
  info "No packer/manifest.json to remove"
fi

# ── Remove Ansible retry files ─────────────────────────────────────────────
find "$REPO_ROOT/ansible" -name "*.retry" -exec rm -f {} + 2>/dev/null && \
  ok "Removed Ansible .retry files" || true

# ── Clear any exported EC2_IP from current shell ──────────────────────────
if [[ -n "${EC2_IP:-}" ]]; then
  warn "EC2_IP is still exported in this shell (\$EC2_IP=$EC2_IP)."
  warn "If the instance has been destroyed, unset it: 'unset EC2_IP'"
fi

echo ""
ok "Demo environment reset complete."
info "Run .scripts/demo-preflight.sh to verify readiness before the next demo."
echo ""
