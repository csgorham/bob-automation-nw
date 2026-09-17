#!/usr/bin/env bash
# =============================================================================
# GOLDEN WORKFLOW — AWS Teardown (Delete All)
# =============================================================================
# Destroys all AWS resources provisioned by the Golden Workflow demo:
#   1. EC2 instance + security group  (terraform/ec2)
#   2. VPC + subnet + IGW             (terraform/network)
#   3. S3 bucket                      (terraform/s3)
#
# WARNING: This is DESTRUCTIVE and IRREVERSIBLE.
# All provisioned infrastructure will be permanently deleted.
#
# Usage:
#   ./.scripts/aws_delete_all.sh
#   ./.scripts/aws_delete_all.sh --force   # skip confirmation prompts
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$REPO_ROOT/.env"
TERRAFORM_DIR="$REPO_ROOT/terraform"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC}  $*"; }
fail() { echo -e "  ${RED}✗${NC}  $*" >&2; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $*"; }
info() { echo -e "  ${CYAN}ℹ${NC}  $*"; }

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

# ── Load .env ─────────────────────────────────────────────────────────────────
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  info "Loaded .env"
else
  fail ".env not found at $ENV_FILE — cannot proceed without VAULT_ADDR and VAULT_TOKEN"
  exit 1
fi

# ── Require Vault credentials ─────────────────────────────────────────────────
if [[ -z "${VAULT_ADDR:-}" || -z "${VAULT_TOKEN:-}" ]]; then
  fail "VAULT_ADDR and VAULT_TOKEN must be set in .env"
  exit 1
fi

TF_VARS="-var=vault_addr=${VAULT_ADDR} -var=vault_token=${VAULT_TOKEN}"

# ── Confirmation ──────────────────────────────────────────────────────────────
echo ""
echo -e "${RED}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}${BOLD}║          ⚠  DESTRUCTIVE OPERATION — TEARDOWN  ⚠         ║${NC}"
echo -e "${RED}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
warn "This will PERMANENTLY DESTROY all demo AWS resources:"
echo "    • EC2 instance + security group"
echo "    • VPC, subnets, internet gateway, route tables"
echo "    • S3 bucket and all its contents"
echo ""

if [[ "$FORCE" != "true" ]]; then
  echo -n -e "  ${BOLD}Type 'yes' to confirm teardown: ${NC}"
  read -r confirm
  if [[ "$confirm" != "yes" ]]; then
    info "Teardown cancelled."
    exit 0
  fi
fi

echo ""
info "Starting teardown — destroying in dependency order (EC2 → Network → S3)..."
echo ""

run_destroy() {
  local module="$1"
  local module_dir="$TERRAFORM_DIR/$module"
  local extra_vars="${2:-}"

  echo -e "${CYAN}── Destroying: terraform/$module ──${NC}"

  if [[ ! -d "$module_dir" ]]; then
    warn "Module directory not found: $module_dir — skipping"
    return 0
  fi

  (
    cd "$module_dir"

    # Init if needed
    if [[ ! -d ".terraform" ]]; then
      info "Initialising $module..."
      terraform init -input=false -no-color 2>&1 | tail -3
    fi

    terraform destroy \
      -auto-approve \
      -var-file=dev.auto.tfvars \
      ${TF_VARS} \
      ${extra_vars} \
      -input=false \
      -no-color 2>&1
  ) && ok "terraform/$module destroyed." || {
    warn "terraform/$module destroy returned non-zero — some resources may need manual cleanup."
  }

  echo ""
}

# Destroy in reverse dependency order
run_destroy "ec2"
run_destroy "network"
run_destroy "s3"

# ── Post-teardown cleanup ──────────────────────────────────────────────────────
echo ""
info "Cleaning up local runtime artefacts..."
"$SCRIPT_DIR/demo-reset.sh"

echo ""
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  Teardown complete. All demo AWS resources destroyed.${NC}"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════════${NC}"
echo ""
info "To reprovision from scratch, run:"
info "  1. source .env"
info "  2. .scripts/demo-preflight.sh"
info "  3. ./demo-runner.sh --stage 3"
echo ""
