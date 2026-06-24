#!/usr/bin/env bash
# =============================================================================
# SAMCO Retail Prototype — Setup & Registration Script
#
# Usage:
#   chmod +x scripts/setup.sh
#
#   # Step 1 — generate RSA keys for IBM i HTTP auth (run once)
#   ./scripts/setup.sh --generate-keys
#
#   # Step 2 — register everything in watsonx Orchestrate (draft env)
#   ./scripts/setup.sh --register-all
#
#   # Individual steps
#   ./scripts/setup.sh --register-connection
#   ./scripts/setup.sh --register-toolkit
#   ./scripts/setup.sh --register-agent
#
# Prerequisites:
#   - .env file created from .env.example
#   - ibm-watsonx-orchestrate ADK CLI installed and authenticated
#     (pip install ibm-watsonx-orchestrate  &&  orchestrate env activate ...)
#   - Docker/Podman for running the MCP server (docker compose up -d)
#   - openssl available on PATH
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# ---------------------------------------------------------------------------
# Load .env
# ---------------------------------------------------------------------------
ENV_FILE="$ROOT_DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌  .env not found. Copy .env.example to .env and fill in your values."
  exit 1
fi
# shellcheck disable=SC1090
set -o allexport; source "$ENV_FILE"; set +o allexport

# ---------------------------------------------------------------------------
# Constants — edit these if you rename files or the connection
# ---------------------------------------------------------------------------
CONNECTION_NAME="samco-ibmi-connection"
TOOLKIT_NAME="samco-ibmi-db2-toolkit"
AGENT_FILE="$ROOT_DIR/agent/samco-retail-agent.yaml"
TOOLS_YAML="$ROOT_DIR/tools/retail-services.yaml"
SECRETS_DIR="$ROOT_DIR/secrets"

# MCP server URL — update to the real public URL when deploying to IBM i
MCP_SERVER_URL="${MCP_SERVER_URL:-http://localhost:3010/mcp}"

# ---------------------------------------------------------------------------
generate_keys() {
  echo "🔑  Generating RSA keypair for IBM i HTTP authentication..."
  mkdir -p "$SECRETS_DIR"
  openssl genpkey -algorithm RSA \
    -out "$SECRETS_DIR/private.pem" \
    -pkeyopt rsa_keygen_bits:2048
  openssl rsa -pubout \
    -in "$SECRETS_DIR/private.pem" \
    -out "$SECRETS_DIR/public.pem"
  chmod 600 "$SECRETS_DIR/private.pem"
  chmod 644 "$SECRETS_DIR/public.pem"
  echo "✅  Keys written to $SECRETS_DIR"
  echo "    Add secrets/ to .gitignore — NEVER commit private.pem to git."
}

# ---------------------------------------------------------------------------
register_connection() {
  echo "🔌  Registering Bearer Token connection: $CONNECTION_NAME"

  # Obtain a bearer token from the running MCP server
  # Requires: npm install / node get-access-token.js in the ibmi-mcp-server repo
  # Or set IBMI_MCP_ACCESS_TOKEN manually and export it before running this script.
  if [[ -z "${IBMI_MCP_ACCESS_TOKEN:-}" ]]; then
    echo "⚠️   IBMI_MCP_ACCESS_TOKEN is not set."
    echo "    Run the following against your running MCP server to get a token:"
    echo ""
    echo "      eval \$(node /path/to/ibmi-mcp-server/get-access-token.js \\"
    echo "        --user \$DB2i_USER --password \$DB2i_PASS \\"
    echo "        --host \$DB2i_HOST --server localhost --port 3010 --quiet)"
    echo ""
    echo "    Then re-run this script."
    exit 1
  fi

  orchestrate connections add -a "$CONNECTION_NAME" 2>/dev/null || true

  for env in draft live; do
    orchestrate connections configure \
      -a "$CONNECTION_NAME" \
      --env "$env" \
      --type team \
      --kind bearer \
      --server-url "$MCP_SERVER_URL"

    orchestrate connections set-credentials \
      -a "$CONNECTION_NAME" \
      --env "$env" \
      --token "$IBMI_MCP_ACCESS_TOKEN"
  done

  echo "✅  Connection registered: $CONNECTION_NAME"
}

# ---------------------------------------------------------------------------
register_toolkit() {
  echo "🧰  Registering Remote MCP toolkit: $TOOLKIT_NAME"

  # Remove existing toolkit if present (toolkit updates require remove + re-add)
  orchestrate toolkits remove -n "$TOOLKIT_NAME" 2>/dev/null || true

  orchestrate toolkits add \
    --kind mcp \
    --name "$TOOLKIT_NAME" \
    --description "SAMCO Retail IBM i DB2 service data via MCP. Provides tools to query the service catalogue, pricing, and coverage from DB2 for i." \
    --url "$MCP_SERVER_URL" \
    --transport streamable_http \
    --tools "*" \
    --app-id "$CONNECTION_NAME"

  echo "✅  Toolkit registered: $TOOLKIT_NAME"
  echo ""
  echo "    Tools imported from server:"
  orchestrate tools list | grep -E "get_service_info|list_active_services|find_services_by_type|search_services_by_name" || true
}

# ---------------------------------------------------------------------------
register_agent() {
  echo "🤖  Importing agent from: $AGENT_FILE"
  orchestrate agents import -f "$AGENT_FILE"
  echo "✅  Agent imported: samco_retail_service_agent"
  echo ""
  echo "    To test the agent:"
  echo "      orchestrate chat start -a samco_retail_service_agent"
}

# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------
case "${1:-}" in
  --generate-keys)    generate_keys ;;
  --register-connection) register_connection ;;
  --register-toolkit)    register_toolkit ;;
  --register-agent)      register_agent ;;
  --register-all)
    register_connection
    register_toolkit
    register_agent
    echo ""
    echo "🎉  All resources registered. Start chatting with:"
    echo "    orchestrate chat start -a samco_retail_service_agent"
    ;;
  *)
    echo "Usage: $0 [--generate-keys | --register-connection | --register-toolkit | --register-agent | --register-all]"
    exit 1
    ;;
esac
