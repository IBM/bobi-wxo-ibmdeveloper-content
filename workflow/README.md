# SAMCO Retail — Deployment Workflow

End-to-end automation for the IBM i × watsonx Orchestrate integration.
A single command runs all 6 phases — from SSH into IBM i through to a
verified live DB2 query through the Orchestrate agent.

```
run-workflow.sh
    │
    ├── Phase 1 — Validate prerequisites (ssh, ngrok, ADK, project files)
    ├── Phase 2 — Upload config + scripts to IBM i via scp
    ├── Phase 3 — npm install + start MCP server on IBM i PASE
    ├── Phase 4 — Start ngrok tunnel, capture public HTTPS URL
    ├── Phase 5 — Register toolkit + import agent in Orchestrate
    └── Phase 6 — End-to-end health check + live DB2 query test
```

---

## Quick Start

```bash
# 1. Copy and fill in the config
cp workflow/workflow.env.example workflow/workflow.env
nano workflow/workflow.env          # set IBMI_HOST, IBMI_USER, VENV_PATH

# 2. Make scripts executable
chmod +x workflow/run-workflow.sh \
         workflow/teardown.sh \
         workflow/status.sh

# 3. Run the full workflow
cd samco-retail-prototype
./workflow/run-workflow.sh
```

**Total runtime: ~3 minutes** (npm install dominates; ~45 seconds)

---

## Flags

| Flag | Effect |
|------|--------|
| `--skip-install` | Skip `npm install` on IBM i — use when package is already installed |
| `--skip-ngrok` | Skip ngrok start — use when tunnel is already running or using static URL |
| `--dry-run` | Print every command without executing — safe preview of what will happen |

```bash
# Typical rerun after initial setup (install already done, keep ngrok running):
./workflow/run-workflow.sh --skip-install --skip-ngrok

# Safe preview of everything the script will do:
./workflow/run-workflow.sh --dry-run
```

---

## Files

| File | Purpose |
|------|---------|
| `run-workflow.sh` | Main workflow — runs all 6 phases end-to-end |
| `teardown.sh` | Reverses everything — stops ngrok + IBM i server + removes Orchestrate resources |
| `status.sh` | Shows current state of all 3 layers at a glance |
| `workflow.env.example` | Config template — copy to `workflow.env` and fill in |
| `workflow.env` | Your local config (**never commit to git** — listed in .gitignore) |

---

## Configuration

All values in `workflow.env`:

| Variable | Description | Example |
|----------|-------------|---------|
| `IBMI_HOST` | IBM i hostname or IP | `<your-ibmi-host>` |
| `IBMI_USER` | SSH username | `<ibmi-user>` |
| `IBMI_MCP_PORT` | MCP server port on IBM i | `3011` |
| `VENV_PATH` | Path to Python .venv with ADK | `/path/to/.venv` |
| `TOOLKIT_NAME` | Name to register toolkit under | `samco-ibmi-mcp` |
| `AGENT_NAME` | Name in agent YAML | `samco_retail_agent` |
| `NGROK_STATIC_URL` | Static ngrok domain (paid tier, optional) | *(blank = auto-capture)* |

---

## What Each Phase Does

### Phase 1 — Validate Prerequisites
- Checks that `ssh`, `scp`, `curl`, `jq`, `ngrok` are installed
- Activates `.venv` and confirms ADK version
- Confirms active Orchestrate environment
- Checks all project files exist
- Tests SSH connectivity to IBM i and reads Node.js version

### Phase 2 — Upload Files to IBM i
- Creates `/home/<user>/samco-mcp/` on IBM i
- Uploads `.env` config (from `ibmi-deploy/ibmi-deploy.env`)
- Uploads `retail-services.yaml` (8 SQL tool definitions)
- Uploads `start/stop/status-mcp-server.sh` scripts
- Sets execute permissions

### Phase 3 — Install + Start MCP Server
- Runs `npm install @ibm/ibmi-mcp-server@latest` in PASE
- Starts the server via `nohup node dist/index.js --transport http`
- Waits 5 seconds then verifies with a live MCP `initialize` handshake
- Fails fast with log location if server does not respond

### Phase 4 — Start ngrok Tunnel
- Kills any existing ngrok process
- Starts `ngrok http <ibmi-host>:<port>` in background
- Waits 8 seconds then queries the ngrok API (`localhost:4040`) for the public URL
- Verifies MCP handshake through the tunnel
- Saves URL to `/tmp/clai-ngrok-url.txt`

### Phase 5 — Register in Orchestrate
- Removes any existing `samco-ibmi-mcp` toolkit registration
- Re-registers with the freshly captured ngrok URL
- Verifies tool count imported
- Imports `agent/samco-retail-agent.yaml`

### Phase 6 — End-to-End Verification
- **Test 1:** `tools/list` — lists all 9 MCP tools through the tunnel
- **Test 2:** `tools/call get_products_by_category(ELE)` — live DB2 query, prints results and latency

---

## Teardown

```bash
# Remove everything
./workflow/teardown.sh

# Keep IBM i running (just update Orchestrate)
./workflow/teardown.sh --keep-ibmi

# Just stop ngrok and IBM i, keep Orchestrate registrations
./workflow/teardown.sh --keep-orchestrate
```

---

## Status Check

```bash
./workflow/status.sh
```

Output:
```
LAYER 1 — IBM i MCP Server
  ● Status   : RUNNING
    Server   : @ibm/ibmi-mcp-server 0.5.1
    Endpoint : http://<your-ibmi-host>:3011/mcp

LAYER 2 — ngrok Tunnel
  ● Status   : ACTIVE
    Public   : https://<your-ngrok-subdomain>.ngrok-free.app
    Target   : <your-ibmi-host>:3011

LAYER 3 — watsonx Orchestrate
  ● Toolkit  : samco-ibmi-mcp (9 tools)
  ● Agent    : samco_retail_agent
    Env      : domain_agents_testing
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Phase 1 fails: SSH refused | Check IBM i host/user in `workflow.env`; verify Mapepire is running |
| Phase 3 fails: npm not found | Run `yum install nodejs` on IBM i via ACS Open Source Package Manager |
| Phase 4 fails: ngrok URL empty | Run `ngrok config add-authtoken <token>` then retry |
| Phase 5 fails: toolkit error | Tunnel may have expired — re-run without `--skip-ngrok` |
| Phase 6: DB2 query returns nothing | Check `mcp-server.log` on IBM i: `ssh <ibmi-user>@<host> 'tail -20 /home/<ibmi-user>/samco-mcp/mcp-server.log'` |

---

## Production Notes

- **Replace ngrok** with IBM Cloud Transit Gateway for production (no URL rotation, IBM private backbone)
- **SSH keys** — set up `ssh-copy-id` to avoid password prompts in CI/CD
- **Rotate MCP credentials** — change `MCP_AUTH_MODE=none` to `bearer` and set a token in `workflow.env`
- **Automate ngrok URL updates** — with a paid ngrok static domain, `NGROK_STATIC_URL` stays constant and `--skip-ngrok` can be used permanently
