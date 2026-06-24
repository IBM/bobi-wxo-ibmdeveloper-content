#!/QOpenSys/pkgs/bin/bash
# =============================================================================
# stop-mcp-server.sh
# Stops the running IBM i MCP Server background process.
# =============================================================================

DEPLOY_DIR="/home/cecuser/samco-mcp"
PID_FILE="${DEPLOY_DIR}/mcp-server.pid"

if [ -f "${PID_FILE}" ]; then
  PID=$(cat "${PID_FILE}")
  if kill -0 "${PID}" 2>/dev/null; then
    echo "Stopping MCP server (PID ${PID})..."
    kill "${PID}"
    rm -f "${PID_FILE}"
    echo "MCP server stopped."
  else
    echo "MCP server process (PID ${PID}) is not running."
    rm -f "${PID_FILE}"
  fi
else
  echo "No PID file found — MCP server may not be running."
fi
