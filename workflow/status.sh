#!/usr/bin/env bash
# =============================================================================
#  SAMCO Retail — Status Check
#  status.sh
#
#  Shows current state of all three layers at a glance:
#    - IBM i MCP server (via SSH)
#    - ngrok tunnel (local process + API)
#    - Orchestrate toolkit + agent (via ADK CLI)
#
#  Usage:
#    ./workflow/status.sh
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/workflow.env"
[ -f "${ENV_FILE}" ] && source "${ENV_FILE}"
[ -f "${VENV_PATH}/bin/activate" ] && source "${VENV_PATH}/bin/activate"

IBMI_DEPLOY_DIR="/home/${IBMI_USER}/samco-mcp"

echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}${CYAN}  SAMCO Retail — Integration Status${RESET}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

# ── Layer 1: IBM i MCP server ─────────────────────────────────────────────────
echo -e "${BOLD}  LAYER 1 — IBM i MCP Server${RESET}"
MCP_RESP=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 \
  "${IBMI_USER}@${IBMI_HOST}" \
  "curl -s --max-time 5 http://localhost:${IBMI_MCP_PORT}/mcp \
     -X POST -H 'Content-Type: application/json' \
     -H 'Accept: application/json, text/event-stream' \
     -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{},\"clientInfo\":{\"name\":\"status\",\"version\":\"1.0\"}}}' \
   2>/dev/null | grep -o '\"version\":\"[^\"]*\"' | head -1" 2>/dev/null || true)

if echo "$MCP_RESP" | grep -q "version"; then
  VER=$(echo "$MCP_RESP" | cut -d'"' -f4)
  echo -e "  ${GREEN}●${RESET} Status   : RUNNING"
  echo -e "    Server   : @ibm/ibmi-mcp-server ${VER}"
  echo -e "    Endpoint : http://${IBMI_HOST}:${IBMI_MCP_PORT}/mcp"
else
  echo -e "  ${RED}●${RESET} Status   : DOWN  (no response on port ${IBMI_MCP_PORT})"
  echo -e "    Fix      : ./workflow/run-workflow.sh --skip-ngrok --skip-install"
fi
echo ""

# ── Layer 2: ngrok tunnel ─────────────────────────────────────────────────────
echo -e "${BOLD}  LAYER 2 — ngrok Tunnel${RESET}"
NGROK_API=$(curl -s --max-time 3 http://localhost:4040/api/tunnels 2>/dev/null || true)
if echo "$NGROK_API" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    tunnels = [t for t in d.get('tunnels',[]) if t.get('proto')=='https']
    if tunnels:
        url = tunnels[0]['public_url']
        target = tunnels[0]['config']['addr']
        print(f'UP|{url}|{target}')
    else:
        print('DOWN||')
except:
    print('DOWN||')
" 2>/dev/null | grep -q "^UP"; then
  STATUS_LINE=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | \
    python3 -c "
import sys, json
d = json.load(sys.stdin)
tunnels = [t for t in d.get('tunnels',[]) if t.get('proto')=='https']
if tunnels:
    url = tunnels[0]['public_url']
    target = tunnels[0]['config']['addr']
    print(f'{url}|{target}')
" 2>/dev/null || true)
  NGROK_URL_LIVE=$(echo "$STATUS_LINE" | cut -d'|' -f1)
  NGROK_TARGET=$(echo "$STATUS_LINE" | cut -d'|' -f2)
  echo -e "  ${GREEN}●${RESET} Status   : ACTIVE"
  echo -e "    Public   : ${NGROK_URL_LIVE}"
  echo -e "    Target   : ${NGROK_TARGET}"
else
  echo -e "  ${RED}●${RESET} Status   : DOWN  (ngrok not running)"
  echo -e "    Fix      : ngrok http ${IBMI_HOST}:${IBMI_MCP_PORT}"
fi
echo ""

# ── Layer 3: Orchestrate toolkit + agent ─────────────────────────────────────
echo -e "${BOLD}  LAYER 3 — watsonx Orchestrate${RESET}"
TOOLKIT_LINE=$(orchestrate toolkits list 2>&1 | grep "${TOOLKIT_NAME}" | head -1 || true)
if [ -n "$TOOLKIT_LINE" ]; then
  TOOL_COUNT=$(orchestrate tools list 2>&1 | grep -c "${TOOLKIT_NAME}:" || true)
  echo -e "  ${GREEN}●${RESET} Toolkit  : ${TOOLKIT_NAME} (${TOOL_COUNT} tools)"
else
  echo -e "  ${RED}●${RESET} Toolkit  : NOT REGISTERED"
fi

AGENT_LINE=$(orchestrate agents list 2>&1 | grep "${AGENT_NAME}" | head -1 || true)
if [ -n "$AGENT_LINE" ]; then
  echo -e "  ${GREEN}●${RESET} Agent    : ${AGENT_NAME}"
else
  echo -e "  ${RED}●${RESET} Agent    : NOT IMPORTED"
fi

ACTIVE_ENV=$(orchestrate env list 2>&1 | grep "(active)" | awk '{print $1}' || true)
echo -e "    Env      : ${ACTIVE_ENV:-unknown}"
echo ""

echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
