#!/QOpenSys/pkgs/bin/bash
# =============================================================================
# status-mcp-server.sh
# Shows status, last 30 log lines, and tests the HTTP endpoint.
# =============================================================================

DEPLOY_DIR="/home/cecuser/samco-mcp"
PID_FILE="${DEPLOY_DIR}/mcp-server.pid"
LOG_FILE="${DEPLOY_DIR}/mcp-server.log"
PORT=3010

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " IBM i MCP Server — Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Process status
if [ -f "${PID_FILE}" ]; then
  PID=$(cat "${PID_FILE}")
  if kill -0 "${PID}" 2>/dev/null; then
    echo "● Process : RUNNING (PID ${PID})"
  else
    echo "● Process : STOPPED (stale PID file)"
  fi
else
  echo "● Process : STOPPED (no PID file)"
fi

# HTTP health check
echo ""
if curl -sf "http://localhost:${PORT}/health" > /dev/null 2>&1; then
  echo "● HTTP    : UP  → http://$(hostname):${PORT}/mcp"
else
  echo "● HTTP    : DOWN (port ${PORT} not responding)"
fi

# Last log lines
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Last 30 log lines:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
tail -30 "${LOG_FILE}" 2>/dev/null || echo "(no log file yet)"
