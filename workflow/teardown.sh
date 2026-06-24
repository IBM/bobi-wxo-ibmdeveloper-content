#!/usr/bin/env bash
# =============================================================================
#  SAMCO Retail — Teardown Script
#  teardown.sh
#
#  Reverses everything run-workflow.sh did:
#    1. Stops ngrok tunnel
#    2. Stops MCP server on IBM i
#    3. Removes Orchestrate agent
#    4. Removes Orchestrate toolkit
#
#  Usage:
#    ./workflow/teardown.sh [--keep-ibmi] [--keep-orchestrate]
#
#  Flags:
#    --keep-ibmi         Skip stopping the IBM i MCP server
#    --keep-orchestrate  Skip removing Orchestrate agent + toolkit
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log_phase() { echo -e "\n${BOLD}${CYAN}━━━  $1  ━━━${RESET}"; }
log_step()  { echo -e "${GREEN}  ▶ $1${RESET}"; }
log_warn()  { echo -e "${YELLOW}  ⚠ $1${RESET}"; }
log_ok()    { echo -e "${GREEN}  ✔ $1${RESET}"; }

KEEP_IBMI=false
KEEP_ORCHESTRATE=false
for arg in "$@"; do
  case "$arg" in
    --keep-ibmi)         KEEP_IBMI=true ;;
    --keep-orchestrate)  KEEP_ORCHESTRATE=true ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/workflow.env"
[ -f "${ENV_FILE}" ] && source "${ENV_FILE}"

# ── 1. Stop ngrok ─────────────────────────────────────────────────────────────
log_phase "Stop ngrok tunnel"
if pkill ngrok 2>/dev/null; then
  log_ok "ngrok stopped"
else
  log_warn "ngrok was not running"
fi
rm -f /tmp/ngrok-clai.log /tmp/ngrok-clai.pid /tmp/clai-ngrok-url.txt

# ── 2. Stop IBM i MCP server ──────────────────────────────────────────────────
if [ "$KEEP_IBMI" = false ]; then
  log_phase "Stop MCP server on IBM i"
  IBMI_DEPLOY_DIR="/home/${IBMI_USER}/samco-mcp"
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
    "${IBMI_USER}@${IBMI_HOST}" \
    "${IBMI_DEPLOY_DIR}/stop-mcp-server.sh" 2>/dev/null && \
    log_ok "MCP server stopped on IBM i" || \
    log_warn "Could not stop MCP server — may already be stopped"
else
  log_warn "Skipping IBM i stop (--keep-ibmi)"
fi

# ── 3. Remove Orchestrate agent + toolkit ─────────────────────────────────────
if [ "$KEEP_ORCHESTRATE" = false ]; then
  log_phase "Remove Orchestrate agent + toolkit"
  # shellcheck disable=SC1090
  [ -f "${VENV_PATH}/bin/activate" ] && source "${VENV_PATH}/bin/activate"

  log_step "Removing agent: ${AGENT_NAME}..."
  orchestrate agents delete --name "${AGENT_NAME}" --kind native 2>&1 | \
    grep -v "^$" || log_warn "Agent not found or already removed"

  log_step "Removing toolkit: ${TOOLKIT_NAME}..."
  orchestrate toolkits remove --name "${TOOLKIT_NAME}" 2>&1 | \
    grep -v "^$" || log_warn "Toolkit not found or already removed"

  log_ok "Orchestrate resources removed"
else
  log_warn "Skipping Orchestrate cleanup (--keep-orchestrate)"
fi

echo ""
echo -e "${BOLD}${GREEN}━━━  TEARDOWN COMPLETE  ━━━${RESET}"
echo -e "  IBM i MCP server  : stopped"
echo -e "  ngrok tunnel      : stopped"
echo -e "  Orchestrate       : agent + toolkit removed"
echo -e "\n  To redeploy: ./workflow/run-workflow.sh"
