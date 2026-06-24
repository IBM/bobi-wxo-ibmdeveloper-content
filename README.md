# SAMCO Retail — IBM i × watsonx Orchestrate Prototype

> **Phase 2 — Service Information Agent**  
> Integrates IBM i / DB2 for i with watsonx Orchestrate via the IBM i MCP Server,
> enabling clients to ask natural-language questions about SAMCO Retail services.

---

## Architecture

<img width="1761" height="595" alt="archsample3" src="https://github.com/user-attachments/assets/9c8dc6e9-aa4f-4942-a25d-488561e1beac" />


---

## Folder Structure

```
samco-retail-prototype/
├── .env.example                  ← copy to .env, fill in credentials
├── docker-compose.yml            ← runs the IBM i MCP Server
├── agent/
│   └── samco-retail-agent.yaml ← watsonx Orchestrate agent spec
├── scripts/
│   └── setup.sh                 ← one-command setup for Orchestrate resources
├── secrets/                     ← RSA keys live here (generated, never committed)
│   └── .gitkeep
└── tools/
    └── retail-services.yaml   ← DB2 SQL tool definitions (YAML, no code)
```

---

## Prerequisites

| Requirement | How to verify |
|---|---|
| Node.js 18+ (local dev) | `node --version` |
| Docker or Podman | `docker --version` |
| Mapepire running on IBM i | `sc check mapepire` (on IBM i) |
| watsonx Orchestrate ADK CLI | `orchestrate --version` |
| IBM i user with DB authority | provided by CLAI team |

---

## Step-by-Step Setup

### 1 — Configure credentials

```bash
cd samco-retail-prototype
cp .env.example .env
```

Edit `.env` and fill in:

| Variable | What to set |
|---|---|
| `DB2i_HOST` | IBM i hostname or IP (e.g. `ibmi.clai.com`) |
| `DB2i_USER` | IBM i user profile (read-only service account) |
| `DB2i_PASS` | IBM i password |
| `DB2i_PORT` | Mapepire port (default `8076`) |
| `CLAI_SCHEMA` | Library/schema name (e.g. `CLAILIB`) |

### 2 — Update the SQL tools for your schema

Open [`tools/retail-services.yaml`](tools/retail-services.yaml) and:

1. Replace `${CLAI_SCHEMA}.SERVICES` with your actual table name if different
2. Confirm column names match your DB2 table (`SERVICE_ID`, `SERVICE_NAME`, etc.)
3. Update the `enum` values for `service_type` to match your real data categories

> **Quick check** — run this query directly on IBM i to see your columns:
> ```sql
> SELECT COLUMN_NAME, DATA_TYPE, LENGTH
> FROM QSYS2.SYSCOLUMNS2
> WHERE TABLE_SCHEMA = 'YOUR_LIBRARY' AND TABLE_NAME = 'YOUR_TABLE'
> ORDER BY ORDINAL_POSITION
> ```

### 3 — Start the MCP server

```bash
# Start server in background
docker compose up -d

# Confirm it's running (should return HTTP 200)
curl http://localhost:3010/healthz

# Stream logs
docker compose logs -f
```

### 4 — Get a Bearer token

The watsonx Orchestrate connection needs a Bearer token to authenticate against the MCP server.

```bash
# Clone the IBM MCP server repo (needed for the token helper script)
git clone https://github.com/IBM/ibmi-mcp-server.git /tmp/ibmi-mcp-server

# Generate a token and export it into the shell
eval $(node /tmp/ibmi-mcp-server/get-access-token.js \
  --user "$DB2i_USER" \
  --password "$DB2i_PASS" \
  --host "$DB2i_HOST" \
  --server localhost \
  --port 3010 \
  --quiet)

echo $IBMI_MCP_ACCESS_TOKEN   # Should print a JWT string
```

### 5 — Register everything in watsonx Orchestrate

Make sure the ADK CLI is authenticated (`orchestrate login` or `orchestrate env activate`).

```bash
# Export the token from step 4 if not already set
# export IBMI_MCP_ACCESS_TOKEN="eyJ..."

# Register connection, toolkit, and agent in one command
./scripts/setup.sh --register-all
```

Or run individual steps:

```bash
./scripts/setup.sh --register-connection   # Bearer token connection
./scripts/setup.sh --register-toolkit      # Remote MCP toolkit (imports 4 tools)
./scripts/setup.sh --register-agent        # Import the agent spec
```

### 6 — Test the agent

```bash
orchestrate chat start -a samco_retail_service_agent
```

Try these sample prompts:

| Prompt | Expected tool called |
|---|---|
| "What services do you offer?" | `list_active_services` |
| "Tell me about service SVC001234" | `get_service_info` |
| "Show me all transfer options" | `find_services_by_type` |
| "Do you have anything called express?" | `search_services_by_name` |

---

## Production Hardening Checklist

- [ ] Generate RSA keys: `./scripts/setup.sh --generate-keys`
- [ ] Enable IBM i HTTP Auth in `.env` (uncomment `MCP_AUTH_MODE=ibmi` block)
- [ ] Place MCP server behind HTTPS reverse proxy (nginx / HAProxy)
- [ ] Set `IBMI_AUTH_ALLOW_HTTP=false` once HTTPS is in place
- [ ] Use a dedicated read-only IBM i user profile (`CLAI_AGENT`)
- [ ] Restrict port 3010 to watsonx Orchestrate egress IPs only
- [ ] Schedule token rotation (token TTL default: 1 hour)
- [ ] Switch to Docker Compose replicas or OpenShift for high availability

---

## Updating SQL Tools

The SQL tools are pure YAML — no code, no redeploy of the agent needed.

1. Edit [`tools/retail-services.yaml`](tools/retail-services.yaml)
2. Restart the MCP server: `docker compose restart`
3. Re-register the toolkit (required — toolkit updates are replace, not patch):
   ```bash
   ./scripts/setup.sh --register-toolkit
   ```

---

## Key References

| Resource | Link |
|---|---|
| IBM i MCP Server docs | https://ibm-d95bab6e.mintlify.app |
| GitHub repo (Jesse Gorzinski) | https://github.com/IBM/ibmi-mcp-server |
| watsonx Orchestrate ADK docs | https://developer.watson-orchestrate.ibm.com |
| Setup Mapepire | https://ibm-d95bab6e.mintlify.app/setup-mapepire |
| Remote MCP toolkits | https://developer.watson-orchestrate.ibm.com/tools/toolkits/remote_mcp_toolkits |
