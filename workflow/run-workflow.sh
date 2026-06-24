#!/usr/bin/env bash
# =============================================================================
#  SAMCO Retail — IBM i × watsonx Orchestrate Full Deployment Workflow
#  run-workflow.sh
#
#  Runs all 6 phases end-to-end from a single command:
#    Phase 1 — Validate local prerequisites
#    Phase 2 — Deploy MCP server config + scripts to IBM i
#    Phase 3 — Install npm package + start MCP server on IBM i
#    Phase 4 — Start ngrok tunnel and capture the public URL
#    Phase 5 — Register MCP toolkit + import agent in Orchestrate
#    Phase 6 — End-to-end health check + live query verification
#
#  Usage:
#    chmod +x workflow/run-workflow.sh
#    ./workflow/run-workflow.sh [--skip-install] [--skip-ngrok] [--dry-run]
#
#  Flags:
#    --skip-install   Skip npm install on IBM i (use when already installed)
#    --skip-ngrok     Skip ngrok start (use when tunnel is already running)
#    --dry-run        Print every step without executing — safe preview mode
#
#  Requirements (local machine):
#    - workflow/workflow.env filled in (copy from workflow/workflow.env.example)
#    - .venv with ibm-watsonx-orchestrate ADK active
#    - ngrok installed and authenticated (ngrok config add-authtoken <token>)
#    - ssh + scp access to IBM i
#    - curl, jq (brew install jq)
#
#  Author: SAMCO Retail Integration Team
#  Based on: IMPLEMENTATION_GUIDE.md
# =============================================================================

set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log_phase()  { echo -e "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; \
               echo -e "${BOLD}${CYAN}  $1${RESET}"; \
               echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }
log_step()   { echo -e "${GREEN}  ▶ $1${RESET}"; }
log_warn()   { echo -e "${YELLOW}  ⚠ $1${RESET}"; }
log_error()  { echo -e "${RED}  ✖ $1${RESET}"; }
log_ok()     { echo -e "${GREEN}  ✔ $1${RESET}"; }
log_info()   { echo -e "    $1"; }

# ── Flag parsing ──────────────────────────────────────────────────────────────
SKIP_INSTALL=false
SKIP_NGROK=false
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --skip-install) SKIP_INSTALL=true ;;
    --skip-ngrok)   SKIP_NGROK=true ;;
    --dry-run)      DRY_RUN=true ;;
  esac
done

run() {
  # Execute or print depending on --dry-run
  if [ "$DRY_RUN" = true ]; then
    echo -e "    ${YELLOW}[DRY-RUN]${RESET} $*"
  else
    eval "$@"
  fi
}

# ── Load configuration ────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/workflow.env"

if [ ! -f "${ENV_FILE}" ]; then
  log_error "workflow.env not found at ${ENV_FILE}"
  log_info  "Copy the example and fill in your values:"
  log_info  "  cp ${SCRIPT_DIR}/workflow.env.example ${ENV_FILE}"
  exit 1
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

# ── Derived paths ─────────────────────────────────────────────────────────────
IBMI_DEPLOY_DIR="/home/${IBMI_USER}/samco-mcp"
TOOLS_YAML="${PROJECT_DIR}/tools/retail-services.yaml"
AGENT_YAML="${PROJECT_DIR}/agent/samco-retail-agent.yaml"
DEPLOY_ENV="${PROJECT_DIR}/ibmi-deploy/ibmi-deploy.env"
START_SCRIPT="${PROJECT_DIR}/ibmi-deploy/start-mcp-server.sh"
STOP_SCRIPT="${PROJECT_DIR}/ibmi-deploy/stop-mcp-server.sh"
STATUS_SCRIPT="${PROJECT_DIR}/ibmi-deploy/status-mcp-server.sh"

# Track state across phases
NGROK_URL=""
WORKFLOW_START=$(date +%s)

# ─────────────────────────────────────────────────────────────────────────────
#  PHASE 1 — Validate local prerequisites
# ─────────────────────────────────────────────────────────────────────────────
log_phase "PHASE 1 of 6 — Validate Local Prerequisites"

PREREQS_OK=true

log_step "Checking required local tools..."

for tool in ssh scp curl jq ngrok sshpass; do
  if command -v "$tool" &>/dev/null; then
    log_ok "$tool found: $(command -v $tool)"
  else
    if [ "$tool" = "sshpass" ]; then
      log_warn "sshpass not found — will prompt for SSH password interactively"
    elif [ "$tool" = "ngrok" ] && [ "$SKIP_NGROK" = true ]; then
      log_warn "ngrok not found — skipping (--skip-ngrok flag set)"
    else
      log_error "$tool not found — install it before continuing"
      PREREQS_OK=false
    fi
  fi
done

log_step "Checking .venv Orchestrate ADK..."
if [ -f "${VENV_PATH}/bin/activate" ]; then
  # shellcheck disable=SC1090
  source "${VENV_PATH}/bin/activate"
  ADK_VER=$(orchestrate --version 2>&1 | grep "ADK Version" | awk '{print $3}')
  log_ok "ADK Version: ${ADK_VER:-unknown}"
else
  log_error ".venv not found at ${VENV_PATH}"
  PREREQS_OK=false
fi

log_step "Checking Orchestrate environment..."
ACTIVE_ENV=$(orchestrate env list 2>&1 | grep "(active)" | awk '{print $1}')
if [ -n "$ACTIVE_ENV" ]; then
  log_ok "Active Orchestrate environment: ${ACTIVE_ENV}"
else
  log_error "No active Orchestrate environment found"
  log_info  "Run: orchestrate env set <env-name>"
  PREREQS_OK=false
fi

log_step "Checking required project files..."
for f in "${TOOLS_YAML}" "${AGENT_YAML}" "${DEPLOY_ENV}" "${START_SCRIPT}" "${STOP_SCRIPT}"; do
  if [ -f "$f" ]; then
    log_ok "$(basename $f)"
  else
    log_error "Missing: $f"
    PREREQS_OK=false
  fi
done

log_step "Testing SSH connectivity to IBM i..."
if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
       -o BatchMode=no \
       "${IBMI_USER}@${IBMI_HOST}" \
       "export PATH=/QOpenSys/pkgs/bin:\$PATH && node --version" \
       2>/dev/null | grep -q "v"; then
  NODE_VER=$(ssh -o StrictHostKeyChecking=no "${IBMI_USER}@${IBMI_HOST}" \
    "export PATH=/QOpenSys/pkgs/bin:\$PATH && node --version" 2>/dev/null)
  log_ok "IBM i reachable — Node.js ${NODE_VER}"
else
  log_error "Cannot reach ${IBMI_USER}@${IBMI_HOST} — check credentials and network"
  PREREQS_OK=false
fi

log_step "Checking ngrok auth..."
if [ "$SKIP_NGROK" = false ]; then
  if ngrok config check &>/dev/null; then
    log_ok "ngrok config valid"
  else
    log_warn "ngrok config check failed — tunnel may fail"
  fi
fi

if [ "$PREREQS_OK" = false ]; then
  log_error "Prerequisites check failed — fix the above errors and re-run"
  exit 1
fi

log_ok "All prerequisites satisfied ✔"

# ─────────────────────────────────────────────────────────────────────────────
#  PHASE 2 — Upload files to IBM i
# ─────────────────────────────────────────────────────────────────────────────
log_phase "PHASE 2 of 6 — Upload Config + Scripts to IBM i"

log_step "Creating deploy directory on IBM i..."
run ssh -o StrictHostKeyChecking=no "${IBMI_USER}@${IBMI_HOST}" \
  "mkdir -p ${IBMI_DEPLOY_DIR}"

log_step "Uploading .env config..."
run scp -o StrictHostKeyChecking=no \
  "${DEPLOY_ENV}" \
  "${IBMI_USER}@${IBMI_HOST}:${IBMI_DEPLOY_DIR}/.env"

log_step "Uploading SQL tools YAML..."
run scp -o StrictHostKeyChecking=no \
  "${TOOLS_YAML}" \
  "${IBMI_USER}@${IBMI_HOST}:${IBMI_DEPLOY_DIR}/retail-services.yaml"

log_step "Uploading management scripts..."
for script in start stop status; do
  run scp -o StrictHostKeyChecking=no \
    "${PROJECT_DIR}/ibmi-deploy/${script}-mcp-server.sh" \
    "${IBMI_USER}@${IBMI_HOST}:${IBMI_DEPLOY_DIR}/${script}-mcp-server.sh"
done

log_step "Setting script permissions..."
run ssh -o StrictHostKeyChecking=no "${IBMI_USER}@${IBMI_HOST}" \
  "chmod +x ${IBMI_DEPLOY_DIR}/start-mcp-server.sh \
             ${IBMI_DEPLOY_DIR}/stop-mcp-server.sh \
             ${IBMI_DEPLOY_DIR}/status-mcp-server.sh"

log_ok "Files uploaded to ${IBMI_DEPLOY_DIR}"

# ─────────────────────────────────────────────────────────────────────────────
#  PHASE 3 — Install npm package + start MCP server on IBM i
# ─────────────────────────────────────────────────────────────────────────────
log_phase "PHASE 3 of 6 — Install + Start MCP Server on IBM i"

if [ "$SKIP_INSTALL" = false ]; then
  log_step "Installing @ibm/ibmi-mcp-server on IBM i (this takes ~45 seconds)..."
  run ssh -o StrictHostKeyChecking=no "${IBMI_USER}@${IBMI_HOST}" "
    export PATH=/QOpenSys/pkgs/bin:\$PATH
    cd ${IBMI_DEPLOY_DIR}
    npm install @ibm/ibmi-mcp-server@latest --save 2>&1 | tail -5
  "
  log_ok "@ibm/ibmi-mcp-server installed"
else
  log_warn "Skipping npm install (--skip-install)"
fi

log_step "Starting MCP server on IBM i (port ${IBMI_MCP_PORT})..."
run ssh -o StrictHostKeyChecking=no "${IBMI_USER}@${IBMI_HOST}" \
  "${IBMI_DEPLOY_DIR}/start-mcp-server.sh"

log_step "Waiting 5 seconds for server to initialise..."
if [ "$DRY_RUN" = false ]; then sleep 5; fi

log_step "Verifying MCP server health on IBM i..."
if [ "$DRY_RUN" = false ]; then
  MCP_HEALTH=$(ssh -o StrictHostKeyChecking=no "${IBMI_USER}@${IBMI_HOST}" \
    "curl -s --max-time 8 \
       -X POST http://localhost:${IBMI_MCP_PORT}/mcp \
       -H 'Content-Type: application/json' \
       -H 'Accept: application/json, text/event-stream' \
       -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{},\"clientInfo\":{\"name\":\"healthcheck\",\"version\":\"1.0\"}}}' \
     2>/dev/null | grep -o '\"version\":\"[^\"]*\"' | head -1" 2>/dev/null || true)

  if echo "$MCP_HEALTH" | grep -q "version"; then
    MCP_VER=$(echo "$MCP_HEALTH" | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
    log_ok "MCP server running — @ibm/ibmi-mcp-server ${MCP_VER}"
    log_info "Endpoint: http://${IBMI_HOST}:${IBMI_MCP_PORT}/mcp"
  else
    log_error "MCP server health check failed"
    log_info  "Check logs: ssh ${IBMI_USER}@${IBMI_HOST} 'tail -30 ${IBMI_DEPLOY_DIR}/mcp-server.log'"
    exit 1
  fi
else
  run "ssh ${IBMI_USER}@${IBMI_HOST} 'curl -s http://localhost:${IBMI_MCP_PORT}/health'"
fi

# ─────────────────────────────────────────────────────────────────────────────
#  PHASE 4 — Start ngrok tunnel
# ─────────────────────────────────────────────────────────────────────────────
log_phase "PHASE 4 of 6 — Start ngrok Tunnel"

if [ "$SKIP_NGROK" = true ]; then
  log_warn "Skipping ngrok start (--skip-ngrok flag set)"
  if [ -n "${NGROK_STATIC_URL:-}" ]; then
    NGROK_URL="${NGROK_STATIC_URL}"
    log_ok "Using static ngrok URL from workflow.env: ${NGROK_URL}"
  else
    log_error "NGROK_STATIC_URL not set in workflow.env — cannot continue without a tunnel URL"
    exit 1
  fi
else
  log_step "Killing any existing ngrok processes..."
  pkill ngrok 2>/dev/null || true
  sleep 1

  log_step "Starting ngrok tunnel → ${IBMI_HOST}:${IBMI_MCP_PORT}..."
  if [ "$DRY_RUN" = false ]; then
    nohup ngrok http "${IBMI_HOST}:${IBMI_MCP_PORT}" \
      --log=stdout \
      --log-format=json \
      > /tmp/ngrok-clai.log 2>&1 &
    NGROK_PID=$!
    echo "$NGROK_PID" > /tmp/ngrok-clai.pid
    log_info "ngrok PID: ${NGROK_PID}, log: /tmp/ngrok-clai.log"

    log_step "Waiting 8 seconds for ngrok tunnel to establish..."
    sleep 8

    # Fetch the public URL from ngrok API
    NGROK_URL=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null \
      | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    tunnels = d.get('tunnels', [])
    for t in tunnels:
        if t.get('proto') == 'https':
            print(t['public_url'])
            break
except:
    pass
" 2>/dev/null || true)

    if [ -z "$NGROK_URL" ]; then
      log_error "Could not retrieve ngrok URL from http://localhost:4040/api/tunnels"
      log_info  "Is ngrok authenticated? Run: ngrok config add-authtoken <your-token>"
      log_info  "ngrok log: $(cat /tmp/ngrok-clai.log | tail -5)"
      exit 1
    fi

    log_ok "ngrok tunnel active: ${NGROK_URL}"
    log_info "→ forwards to: http://${IBMI_HOST}:${IBMI_MCP_PORT}"

    # Verify MCP handshake through the tunnel
    log_step "Verifying MCP handshake through ngrok tunnel..."
    TUNNEL_CHECK=$(curl -s --max-time 15 \
      -X POST "${NGROK_URL}/mcp" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json, text/event-stream" \
      -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"healthcheck","version":"1.0"}}}' \
      2>/dev/null | grep -o '"name":"@ibm/ibmi-mcp-server"' || true)

    if echo "$TUNNEL_CHECK" | grep -q "ibmi-mcp-server"; then
      log_ok "MCP handshake verified through tunnel ✔"
    else
      log_warn "MCP handshake through tunnel returned unexpected response"
      log_info "Continuing anyway — check manually: curl -s ${NGROK_URL}/mcp ..."
    fi
  else
    run "nohup ngrok http ${IBMI_HOST}:${IBMI_MCP_PORT} > /tmp/ngrok-clai.log 2>&1 &"
    NGROK_URL="https://<ngrok-url-would-be-here>"
  fi
fi

# Write the captured URL to a state file for teardown and reference
echo "$NGROK_URL" > /tmp/clai-ngrok-url.txt
log_info "URL saved to /tmp/clai-ngrok-url.txt"

# ─────────────────────────────────────────────────────────────────────────────
#  PHASE 5 — Register toolkit + import agent in Orchestrate
# ─────────────────────────────────────────────────────────────────────────────
log_phase "PHASE 5 of 6 — Register Toolkit + Import Agent in Orchestrate"

MCP_ENDPOINT="${NGROK_URL}/mcp"
log_info "MCP endpoint: ${MCP_ENDPOINT}"

log_step "Removing existing toolkit registration (if any)..."
if [ "$DRY_RUN" = false ]; then
  orchestrate toolkits remove --name "${TOOLKIT_NAME}" 2>&1 | grep -v "^$" || true
else
  run "orchestrate toolkits remove --name ${TOOLKIT_NAME}"
fi

log_step "Registering MCP toolkit: ${TOOLKIT_NAME}..."
run orchestrate toolkits add \
  --kind mcp \
  --name \"${TOOLKIT_NAME}\" \
  --description \"IBM i MCP Server — live DB2 for i queries against the SAMCO retail schema on PowerVS. SAMCO Retail integration demo.\" \
  --url \"${MCP_ENDPOINT}\" \
  --transport streamable_http \
  --tools \"*\"

if [ "$DRY_RUN" = false ]; then
  # Verify tools were imported
  TOOL_COUNT=$(orchestrate tools list 2>&1 | grep -c "${TOOLKIT_NAME}:" || true)
  if [ "$TOOL_COUNT" -gt 0 ]; then
    log_ok "${TOOL_COUNT} tools imported from ${TOOLKIT_NAME}"
    orchestrate tools list 2>&1 | grep "${TOOLKIT_NAME}:" | \
      awk -F'│' '{print "    •", $2}' | tr -s ' '
  else
    log_warn "No tools found for ${TOOLKIT_NAME} — toolkit may not have imported correctly"
  fi
fi

log_step "Importing Orchestrate agent from ${AGENT_YAML}..."
run orchestrate agents import -f \"${AGENT_YAML}\"

if [ "$DRY_RUN" = false ]; then
  AGENT_CHECK=$(orchestrate agents list 2>&1 | grep "${AGENT_NAME}" || true)
  if [ -n "$AGENT_CHECK" ]; then
    log_ok "Agent '${AGENT_NAME}' is live in Orchestrate"
  else
    log_warn "Agent '${AGENT_NAME}' not found after import — check manually"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
#  PHASE 6 — End-to-end verification
# ─────────────────────────────────────────────────────────────────────────────
log_phase "PHASE 6 of 6 — End-to-End Verification"

log_step "Test 1: MCP tools/list through tunnel..."
if [ "$DRY_RUN" = false ]; then
  TOOLS_RESP=$(curl -s --max-time 15 \
    -X POST "${NGROK_URL}/mcp" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
    2>/dev/null | grep "^data:" | python3 -c "
import sys, json
raw = sys.stdin.read().replace('data: ','').strip()
try:
    d = json.loads(raw)
    tools = d['result']['tools']
    print(f'  {len(tools)} tools available:')
    for t in tools:
        print(f'    • {t[\"name\"]}')
except Exception as e:
    print(f'  parse error: {e}')
    print(f'  raw: {raw[:200]}')
" 2>/dev/null || true)
  if [ -n "$TOOLS_RESP" ]; then
    log_ok "tools/list responded:"
    echo "$TOOLS_RESP"
  else
    log_warn "tools/list returned no parseable output"
  fi
else
  run "curl -s ${NGROK_URL}/mcp -X POST ... tools/list"
fi

log_step "Test 2: Live DB2 query — get_products_by_category(ELE)..."
if [ "$DRY_RUN" = false ]; then
  QUERY_RESP=$(curl -s --max-time 20 \
    -X POST "${NGROK_URL}/mcp" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_products_by_category","arguments":{"category_id":"ELE"}}}' \
    2>/dev/null | grep "^data:" | python3 -c "
import sys, json
raw = sys.stdin.read().replace('data: ','').strip()
try:
    d = json.loads(raw)
    content = d['result']['content'][0]['text']
    payload = json.loads(content)
    rows = payload.get('data', [])
    ms   = payload.get('metadata', {}).get('executionTime', '?')
    print(f'  {len(rows)} rows returned in {ms}ms')
    for r in rows:
        name  = r.get('PRODUCT_NAME','?')
        price = r.get('SALE_PRICE','?')
        stock = r.get('STOCK_LEVEL','?')
        print(f'    • {name:<30} \${price}  stock:{stock}')
except Exception as e:
    print(f'  parse error: {e}')
" 2>/dev/null || true)

  if [ -n "$QUERY_RESP" ]; then
    log_ok "Live DB2 query returned data:"
    echo "$QUERY_RESP"
  else
    log_warn "DB2 query returned no parseable output — check server logs"
  fi
else
  run "curl -s ${NGROK_URL}/mcp -X POST ... get_products_by_category(ELE)"
fi

# ─────────────────────────────────────────────────────────────────────────────
#  Summary
# ─────────────────────────────────────────────────────────────────────────────
WORKFLOW_END=$(date +%s)
ELAPSED=$(( WORKFLOW_END - WORKFLOW_START ))

echo ""
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}${GREEN}  WORKFLOW COMPLETE  (${ELAPSED}s)${RESET}"
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  ${GREEN}✔${RESET} IBM i MCP Server  : http://${IBMI_HOST}:${IBMI_MCP_PORT}/mcp"
echo -e "  ${GREEN}✔${RESET} ngrok tunnel      : ${NGROK_URL}"
echo -e "  ${GREEN}✔${RESET} Orchestrate       : toolkit=${TOOLKIT_NAME}, agent=${AGENT_NAME}"
echo ""
echo -e "  ${BOLD}Try it now in Orchestrate chat:${RESET}"
echo -e "    \"Show me all electronics\""
echo -e "    \"Who is customer 1?\""
echo -e "    \"What was in order 1 from 2026?\""
echo ""
echo -e "  ${BOLD}Manage the IBM i server:${RESET}"
echo -e "    Status : ssh ${IBMI_USER}@${IBMI_HOST} '${IBMI_DEPLOY_DIR}/status-mcp-server.sh'"
echo -e "    Logs   : ssh ${IBMI_USER}@${IBMI_HOST} 'tail -f ${IBMI_DEPLOY_DIR}/mcp-server.log'"
echo -e "    Stop   : ssh ${IBMI_USER}@${IBMI_HOST} '${IBMI_DEPLOY_DIR}/stop-mcp-server.sh'"
echo ""
echo -e "  ${BOLD}To teardown everything:${RESET}"
echo -e "    ./workflow/teardown.sh"
echo ""
