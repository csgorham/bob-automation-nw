#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# GOLDEN WORKFLOW — Demo Preflight Check
# =============================================================================
# Verifies all required tools, credentials, and connectivity are in place
# before starting the demo. Run this before every demo session.
#
# Usage:
#   ./.scripts/demo-preflight.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$REPO_ROOT/.env"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0

ok()   { echo -e "  ${GREEN}✓${NC}  $*"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}✗${NC}  $*"; FAIL=$((FAIL + 1)); }
warn() { echo -e "  ${YELLOW}⚠${NC}  $*"; }
info() { echo -e "  ${CYAN}ℹ${NC}  $*"; }

banner() {
  local width=60
  local line
  line=$(printf '═%.0s' $(seq 1 $width))
  echo ""
  echo -e "${CYAN}╔${line}╗${NC}"
  printf "${CYAN}║${NC}  ${BOLD}%-$((width - 2))s${NC}${CYAN}║${NC}\n" "$1"
  echo -e "${CYAN}╚${line}╝${NC}"
  echo ""
}

# ── Load .env ─────────────────────────────────────────────────────────────────
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  info "Loaded .env from $ENV_FILE"
else
  warn ".env not found at $ENV_FILE — some checks will be skipped."
fi

# =============================================================================
banner "1 — Required CLI Tools"
# =============================================================================

check_tool() {
  local tool="$1"
  local version_cmd="${2:-}"
  if command -v "$tool" &>/dev/null; then
    local version="unknown"
    if [[ -n "$version_cmd" ]]; then
      version=$(eval "$version_cmd" 2>/dev/null | head -1 || echo "unknown")
    else
      version=$("$tool" --version 2>/dev/null | head -1 || echo "unknown")
    fi
    ok "$tool found — $version"
  else
    fail "$tool not found — install it before running the demo"
  fi
}

check_tool terraform  "terraform version"
check_tool sentinel   "sentinel version"
check_tool packer     "packer version"
check_tool ansible    "ansible --version"
check_tool vault      "vault version"
check_tool aws        "aws --version"
check_tool git        "git --version"
check_tool jq         "jq --version"

# =============================================================================
banner "2 — Environment Variables"
# =============================================================================

check_env() {
  local var="$1"
  local required="${2:-true}"
  if [[ -n "${!var:-}" ]]; then
    ok "\$$var is set"
  elif [[ "$required" == "true" ]]; then
    fail "\$$var is NOT set — add it to .env"
  else
    warn "\$$var is not set (optional)"
  fi
}

check_env VAULT_ADDR
check_env VAULT_TOKEN
check_env AWS_REGION
check_env AWS_ACCESS_KEY_ID
check_env AWS_SECRET_ACCESS_KEY
check_env GITHUB_TOKEN
check_env S3_BUCKET_NAME
check_env HCP_TERRAFORM_TOKEN
check_env hcp_client_id
check_env hcp_client_secret
check_env hcp_organization_id
check_env hcp_project_id
check_env EC2_IP "false"
check_env SSH_KEY_PATH "false"

# =============================================================================
banner "3 — Vault Connectivity"
# =============================================================================

if [[ -z "${VAULT_ADDR:-}" || -z "${VAULT_TOKEN:-}" ]]; then
  warn "VAULT_ADDR or VAULT_TOKEN not set — skipping Vault checks"
else
  if vault status &>/dev/null; then
    ok "Vault is reachable at $VAULT_ADDR"

    # Check sealed status
    sealed=$(vault status -format=json 2>/dev/null | jq -r '.sealed' 2>/dev/null || echo "unknown")
    if [[ "$sealed" == "false" ]]; then
      ok "Vault is unsealed"
    else
      fail "Vault is sealed — run 'vault operator unseal'"
    fi

    # Check required KV paths
    for path in \
      "secret/ami-pipeline/hcp-terraform" \
      "secret/ami-pipeline/hcp-packer" \
      "secret/ami-pipeline/s3" \
      "secret/ami-pipeline/github"; do
      if vault kv get "$path" &>/dev/null; then
        ok "Vault KV path exists: $path"
      else
        fail "Vault KV path missing: $path — run .scripts/vault.sh"
      fi
    done

    # Check AWS dynamic secrets engine
    if vault read aws/roles/demo-role &>/dev/null; then
      ok "Vault AWS secrets engine configured (demo-role exists)"
    else
      fail "Vault AWS demo-role not found — run .scripts/vault.sh"
    fi
  else
    fail "Vault is NOT reachable at ${VAULT_ADDR} — check VAULT_ADDR and network"
  fi
fi

# =============================================================================
banner "4 — AWS Connectivity"
# =============================================================================

if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
  warn "AWS credentials not set — skipping AWS checks"
else
  if aws sts get-caller-identity &>/dev/null; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
    ok "AWS credentials valid — Account ID: $ACCOUNT_ID"
  else
    fail "AWS credentials invalid or expired"
  fi
fi

# =============================================================================
banner "5 — HCP Terraform Workspace Connectivity"
# =============================================================================

if [[ -z "${HCP_TERRAFORM_TOKEN:-}" ]]; then
  warn "HCP_TERRAFORM_TOKEN not set — skipping workspace checks"
else
  for ws_name in ami-pipeline-s3-check ami-pipeline-s3 ami-pipeline-network ami-pipeline-ec2; do
    response=$(curl -sf \
      -H "Authorization: Bearer $HCP_TERRAFORM_TOKEN" \
      -H "Content-Type: application/vnd.api+json" \
      "https://app.terraform.io/api/v2/organizations/dev_space-cgh/workspaces/$ws_name" \
      2>/dev/null | jq -r '.data.attributes.name' 2>/dev/null || echo "")
    if [[ "$response" == "$ws_name" ]]; then
      ok "HCP Terraform workspace reachable: $ws_name"
    else
      fail "HCP Terraform workspace NOT reachable: $ws_name"
    fi
  done
fi

# =============================================================================
banner "6 — Sentinel Policies"
# =============================================================================

if command -v sentinel &>/dev/null; then
  if (cd "$REPO_ROOT/sentinel" && sentinel test &>/dev/null); then
    ok "All Sentinel policies PASS"
  else
    fail "One or more Sentinel policies FAILED — run 'cd sentinel && sentinel test' for details"
  fi
else
  warn "sentinel CLI not found — skipping policy tests"
fi

# =============================================================================
banner "7 — Packer Template"
# =============================================================================

if command -v packer &>/dev/null; then
  if [[ -f "$REPO_ROOT/packer/ami.pkr.hcl" ]]; then
    if (cd "$REPO_ROOT/packer" && packer validate -var-file=variables.pkr.hcl ami.pkr.hcl &>/dev/null); then
      ok "Packer template valid"
    else
      warn "Packer validate returned warnings — run manually to inspect"
    fi
  else
    fail "packer/ami.pkr.hcl not found"
  fi
else
  warn "packer CLI not found — skipping template validation"
fi

# =============================================================================
banner "Preflight Summary"
# =============================================================================

TOTAL=$((PASS + FAIL))
echo -e "  Checks passed : ${GREEN}${BOLD}$PASS${NC}"
echo -e "  Checks failed : ${RED}${BOLD}$FAIL${NC}"
echo -e "  Total         : $TOTAL"
echo ""

if [[ $FAIL -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}✓ All checks passed — demo is ready to run.${NC}"
  echo -e "  ${CYAN}ℹ Start with: ./demo-runner.sh${NC}"
  echo ""
  exit 0
else
  echo -e "  ${RED}${BOLD}✗ $FAIL check(s) failed — resolve issues above before starting the demo.${NC}"
  echo ""
  exit 1
fi
