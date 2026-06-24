#!/QOpenSys/pkgs/bin/bash
# =============================================================================
# deploy-to-ibmi.sh
# Copies the MCP server config + tools YAML to the IBM i via scp,
# then starts the HTTP server as a background PASE job.
#
# Run this from your local machine (Mac/Linux):
#   chmod +x deploy-to-ibmi.sh
#   ./deploy-to-ibmi.sh
# =============================================================================

set -e

IBMI_HOST="${IBMI_HOST:-YOUR_IBMI_HOSTNAME_OR_IP}"
IBMI_USER="${IBMI_USER:-YOUR_IBMI_USERNAME}"
IBMI_DEPLOY_DIR="/home/${IBMI_USER}/samco-mcp"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " SAMCO Retail — IBM i MCP Server Deployment"
echo " Target: ${IBMI_USER}@${IBMI_HOST}:${IBMI_DEPLOY_DIR}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Step 1: Create deploy directory on IBM i ─────────────────────────────────
echo ""
echo "▶ Step 1: Creating deploy directory on IBM i..."
ssh "${IBMI_USER}@${IBMI_HOST}" "mkdir -p ${IBMI_DEPLOY_DIR}"

# ── Step 2: Upload files ──────────────────────────────────────────────────────
echo "▶ Step 2: Uploading config + tools YAML..."
scp "${SCRIPT_DIR}/ibmi-deploy.env"           "${IBMI_USER}@${IBMI_HOST}:${IBMI_DEPLOY_DIR}/.env"
scp "${SCRIPT_DIR}/retail-services.yaml"    "${IBMI_USER}@${IBMI_HOST}:${IBMI_DEPLOY_DIR}/retail-services.yaml"
scp "${SCRIPT_DIR}/start-mcp-server.sh"       "${IBMI_USER}@${IBMI_HOST}:${IBMI_DEPLOY_DIR}/start-mcp-server.sh"
scp "${SCRIPT_DIR}/stop-mcp-server.sh"        "${IBMI_USER}@${IBMI_HOST}:${IBMI_DEPLOY_DIR}/stop-mcp-server.sh"

# ── Step 3: Make scripts executable ──────────────────────────────────────────
echo "▶ Step 3: Setting permissions..."
ssh "${IBMI_USER}@${IBMI_HOST}" "chmod +x ${IBMI_DEPLOY_DIR}/start-mcp-server.sh ${IBMI_DEPLOY_DIR}/stop-mcp-server.sh"

# ── Step 4: Install @ibm/ibmi-mcp-server on IBM i via npm ────────────────────
echo "▶ Step 4: Installing @ibm/ibmi-mcp-server on IBM i (one-time)..."
ssh "${IBMI_USER}@${IBMI_HOST}" "
  export PATH=/QOpenSys/pkgs/bin:\$PATH
  cd ${IBMI_DEPLOY_DIR}
  npm install @ibm/ibmi-mcp-server@latest --save 2>&1
"

# ── Step 5: Start the MCP server ─────────────────────────────────────────────
echo "▶ Step 5: Starting MCP HTTP server on port 3010..."
ssh "${IBMI_USER}@${IBMI_HOST}" "${IBMI_DEPLOY_DIR}/start-mcp-server.sh"

# ── Step 6: Health check ─────────────────────────────────────────────────────
echo "▶ Step 6: Waiting 5 seconds then checking server health..."
sleep 5
if ssh "${IBMI_USER}@${IBMI_HOST}" "curl -sf http://localhost:3010/health > /dev/null 2>&1"; then
  echo ""
  echo "✅ MCP Server is UP at http://${IBMI_HOST}:3010/mcp"
else
  echo ""
  echo "⚠️  Health check failed — check logs:"
  echo "   ssh ${IBMI_USER}@${IBMI_HOST} 'cat ${IBMI_DEPLOY_DIR}/mcp-server.log'"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " MCP Endpoint: http://${IBMI_HOST}:3010/mcp"
echo " Next step: Register in Orchestrate:"
echo "   orchestrate toolkits add --kind mcp \\"
echo "     --name samco-ibmi-mcp \\"
echo "     --url http://${IBMI_HOST}:3010/mcp \\"
echo "     --transport streamable_http \\"
echo "     --tools '*'"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
