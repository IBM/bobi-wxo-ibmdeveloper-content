#!/QOpenSys/pkgs/bin/bash
# =============================================================================
# start-mcp-server.sh
# Starts the IBM i MCP Server as a background PASE HTTP process.
# Run this ON the IBM i (or via deploy-to-ibmi.sh from your local machine).
# =============================================================================

DEPLOY_DIR="/home/cecuser/samco-mcp"
LOG_FILE="${DEPLOY_DIR}/mcp-server.log"
PID_FILE="${DEPLOY_DIR}/mcp-server.pid"
NODE_BIN="/QOpenSys/pkgs/bin/node"
SERVER_BIN="${DEPLOY_DIR}/node_modules/@ibm/ibmi-mcp-server/dist/index.js"
TOOLS_YAML="${DEPLOY_DIR}/retail-services.yaml"

# Add PASE open-source binaries to PATH
export PATH=/QOpenSys/pkgs/bin:$PATH

cd "${DEPLOY_DIR}"

# Load .env file into the environment
set -o allexport
source "${DEPLOY_DIR}/.env"
set +o allexport

# Stop any existing instance
if [ -f "${PID_FILE}" ]; then
  OLD_PID=$(cat "${PID_FILE}")
  if kill -0 "${OLD_PID}" 2>/dev/null; then
    echo "Stopping existing MCP server (PID ${OLD_PID})..."
    kill "${OLD_PID}"
    sleep 2
  fi
  rm -f "${PID_FILE}"
fi

echo "Starting IBM i MCP Server (HTTP, port ${MCP_HTTP_PORT:-3010})..."
echo "Tools YAML: ${TOOLS_YAML}"
echo "Log: ${LOG_FILE}"

# Start server in background, redirect output to log
nohup "${NODE_BIN}" "${SERVER_BIN}" \
  --transport http \
  --tools "${TOOLS_YAML}" \
  >> "${LOG_FILE}" 2>&1 &

echo $! > "${PID_FILE}"
echo "MCP Server started — PID $(cat ${PID_FILE})"
echo "Endpoint: http://$(hostname):${MCP_HTTP_PORT:-3010}/mcp"
