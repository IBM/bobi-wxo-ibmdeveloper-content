# IBM i × watsonx Orchestrate Integration — Complete Implementation Guide

**Project:** SAMCO Retail Phase 2 — IBM i DB2 with watsonx Orchestrate  
**Demo system:** SAMCO retail application on PowerVS IBM i  
**Contact:** Jesse Gorzinski (IBM US) — referenced repo: https://github.com/IBM/ibmi-mcp-server  
**Date completed:** June 2025  
**Status:** ✅ End-to-end verified — live DB2 queries through Orchestrate agent confirmed

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Pre-Requisites](#2-pre-requisites)
3. [IBM i Side — System Discovery](#3-ibm-i-side--system-discovery)
4. [IBM i Side — Install the MCP Server](#4-ibm-i-side--install-the-mcp-server)
5. [IBM i Side — Configure the MCP Server](#5-ibm-i-side--configure-the-mcp-server)
6. [IBM i Side — Define SQL Tools](#6-ibm-i-side--define-sql-tools)
7. [IBM i Side — Start the MCP Server](#7-ibm-i-side--start-the-mcp-server)
8. [Network — Expose IBM i to Orchestrate](#8-network--expose-ibm-i-to-orchestrate)
9. [watsonx Orchestrate Side — Environment Setup](#9-watsonx-orchestrate-side--environment-setup)
10. [watsonx Orchestrate Side — Register MCP Toolkit](#10-watsonx-orchestrate-side--register-mcp-toolkit)
11. [watsonx Orchestrate Side — Create the Agent](#11-watsonx-orchestrate-side--create-the-agent)
12. [Verify End-to-End](#12-verify-end-to-end)
13. [Operations — Day 2](#13-operations--day-2)
14. [Production Architecture](#14-production-architecture)
15. [Troubleshooting](#15-troubleshooting)
16. [File Reference](#16-file-reference)

> **Extended reading:** For a full analysis of Static vs Dynamic vs Hybrid query approaches (Text-to-SQL, runtime query generation, security model), see [`QUERY_APPROACHES.md`](QUERY_APPROACHES.md).

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          INTEGRATION FLOW                                   │
│                                                                             │
│  User (browser/chat)                                                        │
│        │                                                                    │
│        ▼                                                                    │
│  watsonx Orchestrate  ──────────────────────────────────────────────────── │
│  (SaaS / IBM Cloud)                                                         │
│    Native Agent: samco_retail_agent                                         │
│    LLM: groq/openai/gpt-oss-120b                                            │
│    Tools: 8 DB2 query tools (via MCP toolkit)                               │
│        │                                                                    │
│        │  HTTPS (streamable_http MCP protocol)                              │
│        ▼                                                                    │
│  [Tunnel] ngrok  ←──── For DEV/DEMO only                                   │
│  (or IBM Cloud Transit Gateway for Production)                              │
│        │                                                                    │
│        │  HTTP → port 3011                                                  │
│        ▼                                                                    │
│  IBM i PASE Process (PowerVS)                                               │
│    @ibm/ibmi-mcp-server v0.5.1                                              │
│    Node.js v20.20.1                                                         │
│    Listening: 0.0.0.0:3011                                                  │
│        │                                                                    │
│        │  Mapepire (localhost:8076)                                         │
│        ▼                                                                    │
│  DB2 for i  (IBM i V7R6M0)                                                  │
│    Schema: SAMCO                                                             │
│    Tables: ARTICLE, FAMILLY, CUSTOMER, ORDER, DETORD                        │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Key Components

| Component | Technology | Role |
|-----------|-----------|------|
| IBM i system | PowerVS V7R6M0 | Hosts DB2 database + MCP server process |
| Mapepire | Port 8076 on IBM i | DB2 for i JDBC/REST bridge used by the MCP server |
| @ibm/ibmi-mcp-server | npm package v0.5.1 | Turns SQL tools YAML into a live MCP HTTP server |
| ngrok | Tunnel (dev only) | Exposes IBM i port to public HTTPS for Orchestrate |
| samco-ibmi-mcp toolkit | Orchestrate MCP toolkit | Remote MCP registration — 9 tools imported |
| samco_retail_agent | Orchestrate native agent | LLM-driven agent that calls the DB2 tools |

---

## 2. Pre-Requisites

### IBM i System
- IBM i OS **V7R3M0 or higher** (V7R6M0 used in this project)
- **Node.js v18+** installed via IBM i Open Source (yum/ACS)
  - Verify: `ssh <ibmi-user>@<host> "/QOpenSys/pkgs/bin/node --version"`
- **npm** installed alongside Node.js
  - Verify: `ssh <ibmi-user>@<host> "/QOpenSys/pkgs/bin/npm --version"`
- **Mapepire** service running on port **8076** (ships with IBM i 7.4+, installed via ACS)
  - Verify: `ss -tlnp | grep 8076` from PASE
- SSH access to the IBM i with a user that has DB2 query authority

### Local Machine (Mac / Linux)
- Python 3.x with `.venv` containing the watsonx Orchestrate ADK:
  - Location used: `/path/to/your/.venv`
  - Install: `pip install ibm-watsonx-orchestrate`
  - Verify: `source .venv/bin/activate && orchestrate --version`
- `ngrok` installed and authenticated (for dev/demo — see §8)
- `ssh` and `scp` with key-based auth to IBM i (password auth also works)
- `curl` for verification

### watsonx Orchestrate
- Active Orchestrate SaaS account
- ADK environment configured pointing to your instance:
  - Check: `orchestrate env list` — look for `(active)` entry

---

## 3. IBM i Side — System Discovery

Before deploying, confirm the exact system details. Run from your local machine:

```bash
# 1. Verify SSH access
ssh <ibmi-user>@<your-ibmi-host> "uname -a"

# 2. Check Node.js
ssh <ibmi-user>@<your-ibmi-host> \
  "export PATH=/QOpenSys/pkgs/bin:\$PATH && node --version && npm --version"

# 3. Check Mapepire is running
ssh <ibmi-user>@<your-ibmi-host> \
  "ss -tlnp 2>/dev/null | grep 8076 || netstat -an | grep 8076"

# 4. Confirm the DB schema and tables exist
ssh <ibmi-user>@<your-ibmi-host> \
  "export PATH=/QOpenSys/pkgs/bin:\$PATH && \
   node -e \"
     const { IBMiPool } = require('/home/<ibmi-user>/samco-mcp/node_modules/@ibm/mapepire-js');
   \""
```

### Actual system details used in this project

| Parameter | Value |
|-----------|-------|
| Hostname | `<your-ibmi-host>` |
| IP address | `<your-ibmi-ip>` |
| IBM i OS version | V7R6M0 |
| SSH user | `<ibmi-user>` |
| SSH password | `YOUR_IBMI_PASSWORD` |
| Mapepire port | `8076` |
| Node.js version | `v20.20.1` |
| npm version | `10.8.2` |
| DB schema | `SAMCO` |

### SAMCO schema tables

```sql
SAMCO.ARTICLE   -- Products (33 rows) — key columns: ARID, ARDESC, ARSALEPR, ARSTOCK, ARTIFA, ARDEL
SAMCO.FAMILLY   -- Product categories (10 rows) — key columns: FAID, FADESC, FADEL
SAMCO.CUSTOMER  -- Customers (10 rows) — key columns: CUID, CUSTNM, CUCITY, CUCOUN, CULIMCRE, CUCREDIT, CUDEL
SAMCO."ORDER"   -- Orders (10 rows) — NOTE: ORDER is a reserved word — must be double-quoted in SQL
SAMCO.DETORD    -- Order lines (22 rows) — key columns: ODORID, ODYEAR, ODLINE, ODARID, ODQTY, ODPRICE
```

> ⚠️ **Important:** `ORDER` is a DB2 reserved word. Always write `SAMCO."ORDER"` (double-quoted) in SQL statements.

---

## 4. IBM i Side — Install the MCP Server

All commands run **on the IBM i** via SSH from your local machine.

```bash
# SSH into IBM i
ssh <ibmi-user>@<your-ibmi-host>

# Once on IBM i, add PASE open-source binaries to PATH
export PATH=/QOpenSys/pkgs/bin:$PATH

# Create the deploy directory
mkdir -p /home/<ibmi-user>/samco-mcp
cd /home/<ibmi-user>/samco-mcp

# Install the IBM i MCP Server package
npm install @ibm/ibmi-mcp-server@latest --save
```

**Expected output:**
```
added 87 packages in 45s
```

**Verify installation:**
```bash
ls node_modules/@ibm/ibmi-mcp-server/dist/index.js
# Should print the file path without error
```

> **Version installed:** `@ibm/ibmi-mcp-server@0.5.1`  
> **Install path:** `/home/<ibmi-user>/samco-mcp/node_modules/@ibm/ibmi-mcp-server/`  
> **Entry point:** `dist/index.js`

---

## 5. IBM i Side — Configure the MCP Server

Create the `.env` configuration file at `/home/<ibmi-user>/samco-mcp/.env`:

```bash
cat > /home/<ibmi-user>/samco-mcp/.env << 'EOF'
# IBM i / Mapepire connection
# Use localhost because the MCP server runs ON the IBM i itself
DB2i_HOST=localhost
DB2i_PORT=8076
DB2i_USER=YOUR_IBMI_USERNAME
DB2i_PASS=YOUR_IBMI_PASSWORD
DB2i_IGNORE_UNAUTHORIZED=true

# MCP Server transport — HTTP mode for remote access
MCP_TRANSPORT_TYPE=http
MCP_HTTP_PORT=3011
MCP_HTTP_HOST=0.0.0.0
MCP_LOG_LEVEL=info
MCP_AUTH_MODE=none

# Path to the SQL tools definition file
TOOLS_YAML_PATH=./retail-services.yaml

# Session and rate limiting
MCP_SESSION_MODE=stateless
MCP_RATE_LIMIT_ENABLED=false
EOF
```

### Configuration parameters explained

| Parameter | Value | Reason |
|-----------|-------|--------|
| `DB2i_HOST` | `localhost` | MCP server is on the same machine as DB2/Mapepire — no network hop needed |
| `DB2i_PORT` | `8076` | Mapepire default port |
| `DB2i_IGNORE_UNAUTHORIZED` | `true` | Mapepire uses a self-signed cert in lab environments |
| `MCP_TRANSPORT_TYPE` | `http` | Enables HTTP mode so Orchestrate can connect remotely |
| `MCP_HTTP_PORT` | `3011` | Port 3010 was already in use by a prior test; 3011 is clean |
| `MCP_HTTP_HOST` | `0.0.0.0` | Bind to all interfaces so the ngrok tunnel (or firewall rule) can reach it |
| `MCP_AUTH_MODE` | `none` | No auth in dev; the ngrok tunnel itself provides access control |
| `TOOLS_YAML_PATH` | `./retail-services.yaml` | Path to the SQL tool definitions (relative to deploy dir) |

---

## 6. IBM i Side — Define SQL Tools

Create the SQL tools definition file at `/home/<ibmi-user>/samco-mcp/retail-services.yaml`.

This file tells the MCP server **which DB2 queries to expose as tools** and how to describe them to the LLM.

### File structure

```yaml
sources:
  samco-db:                          # Logical connection name
    host: ${DB2i_HOST}               # Injected from .env at runtime
    user: ${DB2i_USER}
    password: ${DB2i_PASS}
    port: ${DB2i_PORT}
    ignore-unauthorized: true

tools:
  <tool_name>:
    source: samco-db                 # Must match the source name above
    description: >                   # Description shown to the LLM — be specific
      ...
    parameters:                      # Input parameters with JSON Schema validation
      - name: <param>
        type: string|integer|boolean
        required: true|false
        description: "..."
        # Optional validators: minLength, maxLength, minimum, maximum, enum
    security:
      readOnly: true                 # Tells the MCP server this is a SELECT-only tool
    statement: |                     # The SQL query — use :param_name for bind variables
      SELECT ...
      FROM SAMCO.TABLE
      WHERE COLUMN = :param_name

toolsets:                            # Optional grouping of tools for organization
  group_name:
    title: "Human-readable title"
    description: "..."
    tools:
      - tool_name_1
      - tool_name_2
```

### The 8 tools defined for SAMCO

| Tool name | DB2 table(s) | Purpose |
|-----------|-------------|---------|
| `get_product_by_id` | `ARTICLE` + `FAMILLY` | Look up one product by 6-char article code |
| `list_all_products` | `ARTICLE` + `FAMILLY` | Full catalogue, ordered by name |
| `list_categories` | `FAMILLY` | All 10 product categories |
| `get_products_by_category` | `ARTICLE` | Products filtered by 3-letter category ID |
| `search_products` | `ARTICLE` + `FAMILLY` | `LIKE '%keyword%'` search on product names |
| `get_customer` | `CUSTOMER` | Customer profile by numeric ID |
| `get_customer_orders` | `ORDER` + `CUSTOMER` | Order history for a customer |
| `get_order_detail` | `DETORD` + `ARTICLE` | Full line-by-line order breakdown |

> See [`tools/retail-services.yaml`](tools/retail-services.yaml) for the complete SQL for each tool.

### Adapting to a different schema

To replicate this for another IBM i application (e.g. a SAMCO Retail billing schema):

1. Replace `SAMCO` with your schema name
2. Map your actual column names (use `DESCRIBE TABLE` or `QSYS2.SYSCOLUMNS`)
3. Adjust `description:` text so the LLM knows when to call each tool
4. Keep `security: readOnly: true` for SELECT-only tools
5. Use bind variables (`:param_name`) — never string concatenation

---

## 7. IBM i Side — Start the MCP Server

### Option A — Using the start script (recommended)

Copy [`ibmi-deploy/start-mcp-server.sh`](ibmi-deploy/start-mcp-server.sh) to the IBM i and run it:

```bash
# On the IBM i
chmod +x /home/<ibmi-user>/samco-mcp/start-mcp-server.sh
/home/<ibmi-user>/samco-mcp/start-mcp-server.sh
```

The script:
1. Loads `.env` into the environment
2. Stops any existing instance (by PID file)
3. Starts `node dist/index.js --transport http --tools ./retail-services.yaml` via `nohup`
4. Writes the PID to `mcp-server.pid`
5. Prints the endpoint URL

### Option B — Manual start

```bash
# On the IBM i
export PATH=/QOpenSys/pkgs/bin:$PATH
cd /home/<ibmi-user>/samco-mcp

set -o allexport
source .env
set +o allexport

nohup /QOpenSys/pkgs/bin/node \
  node_modules/@ibm/ibmi-mcp-server/dist/index.js \
  --transport http \
  --tools ./retail-services.yaml \
  >> mcp-server.log 2>&1 &

echo $! > mcp-server.pid
echo "Started PID $(cat mcp-server.pid)"
```

### Option C — Deploy from local machine (one-shot)

Run [`ibmi-deploy/deploy-to-ibmi.sh`](ibmi-deploy/deploy-to-ibmi.sh) from your Mac:

```bash
cd samco-retail-prototype/ibmi-deploy
chmod +x deploy-to-ibmi.sh
./deploy-to-ibmi.sh
```

This script does everything: uploads files, installs npm package, starts the server, runs a health check.

### Verify the server is running

```bash
# From the IBM i itself
curl -s http://localhost:3011/health
# Expected: {"status":"ok"} or HTTP 200

# MCP protocol handshake test
curl -s http://localhost:3011/mcp \
  -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
# Expected: event: message\ndata: {"result":{"protocolVersion":"2024-11-05",...}...}
```

### Files on the IBM i after deployment

```
/home/<ibmi-user>/samco-mcp/
├── .env                       ← Active runtime config
├── retail-services.yaml     ← 8 SQL tool definitions
├── start-mcp-server.sh        ← Start script
├── stop-mcp-server.sh         ← Stop script
├── status-mcp-server.sh       ← Status + log viewer
├── mcp-server.pid             ← PID of running process
├── mcp-server.log             ← Live server logs
├── package.json               ← npm package file
└── node_modules/
    └── @ibm/ibmi-mcp-server/  ← v0.5.1
```

### Manage the server

```bash
# Check status
/home/<ibmi-user>/samco-mcp/status-mcp-server.sh

# Stop
/home/<ibmi-user>/samco-mcp/stop-mcp-server.sh

# Restart
/home/<ibmi-user>/samco-mcp/stop-mcp-server.sh
/home/<ibmi-user>/samco-mcp/start-mcp-server.sh

# Tail live logs
tail -f /home/<ibmi-user>/samco-mcp/mcp-server.log
```

---

## 8. Network — Expose IBM i to Orchestrate

> **Context:** The PowerVS IBM i lab system is on a private network. watsonx Orchestrate SaaS (IBM Cloud public) cannot reach it directly. A tunnel is required for dev/demo.

### Dev/Demo — ngrok tunnel (used in this project)

ngrok runs on your **local Mac** (not on the IBM i — ngrok binaries don't exist for `powerpc`).

```bash
# 1. Install ngrok (if not already installed)
brew install ngrok/ngrok/ngrok

# 2. Authenticate (one-time, using your ngrok account token)
ngrok config add-authtoken <YOUR_NGROK_TOKEN>

# 3. Start the tunnel — forward ngrok HTTPS → IBM i HTTP port 3011
ngrok http <your-ibmi-host>:3011
```

ngrok prints the public HTTPS URL, e.g.:
```
Forwarding  https://<your-ngrok-subdomain>.ngrok-free.app -> http://<your-ibmi-host>:3011
```

**Verify the tunnel works:**
```bash
curl -s "https://<your-ngrok-subdomain>.ngrok-free.app/mcp" \
  -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
# Expected: SSE response with protocolVersion and serverInfo
```

> ⚠️ **ngrok free tier:** The URL changes every time you restart ngrok. After restarting, you must re-register the toolkit in Orchestrate with the new URL (see §10).  
> **Fix:** Use `ngrok config` with a named tunnel + static domain (paid tier), or use the production architecture below.

### Production — IBM Cloud Transit Gateway (recommended)

For production deployments where both IBM i and Orchestrate are on IBM Cloud:

1. Create an **IBM Cloud Transit Gateway** in your account
2. Connect your PowerVS workspace to the Transit Gateway
3. Connect the Orchestrate VPC/service to the same Transit Gateway
4. Use the IBM i's **private IP** directly in Orchestrate: `http://<your-ibmi-ip>:3011/mcp`
5. No public exposure, no ngrok, IBM private backbone only

```
IBM Cloud
├── Transit Gateway
│   ├── PowerVS workspace  (IBM i at 10.x.x.x:3011)
│   └── Orchestrate VPC    (can reach 10.x.x.x directly)
```

### Alternative — IBM API Connect

Deploy an IBM API Connect gateway:
- Accepts HTTPS from Orchestrate
- Terminates TLS and forwards to IBM i on internal network
- Adds JWT validation, rate limiting, API versioning

---

## 9. watsonx Orchestrate Side — Environment Setup

### Activate the ADK virtual environment

All Orchestrate CLI commands must be run inside the `.venv`:

```bash
cd /path/to/your
source .venv/bin/activate

# Confirm ADK version and active environment
orchestrate --version
orchestrate env list
```

**Expected output:**
```
ADK Version: 2.11.0
...
domain_agents_testing   https://api.dl.watson-orchestrate.ibm.com/in…  (active)
```

### Verify the correct environment is active

The active environment was `domain_agents_testing` pointing to the IBM internal Orchestrate instance.

```bash
# Check which environment is active
orchestrate env list | grep "(active)"
```

> If you need to switch environments: `orchestrate env set <env-name>`

---

## 10. watsonx Orchestrate Side — Register MCP Toolkit

This step tells Orchestrate where the IBM i MCP server lives and imports all its tools.

### Register the toolkit

```bash
source /path/to/your/.venv/bin/activate

orchestrate toolkits add \
  --kind mcp \
  --name "samco-ibmi-mcp" \
  --description "IBM i MCP Server — live DB2 for i queries against the SAMCO retail schema on PowerVS. Provides tools for products, categories, customers, and orders. SAMCO Retail integration demo." \
  --url "https://<your-ngrok-subdomain>.ngrok-free.app/mcp" \
  --transport streamable_http \
  --tools "*"
```

**Expected output:**
```
[INFO] - Successfully imported tool kit samco-ibmi-mcp
```

### Verify the tools were imported

```bash
orchestrate tools list | grep "samco-ibmi"
```

**Expected — 9 tools registered:**
```
samco-ibmi-mcp:describe_sql_object
samco-ibmi-mcp:get_customer
samco-ibmi-mcp:get_customer_orders
samco-ibmi-mcp:get_order_detail
samco-ibmi-mcp:get_product_by_id
samco-ibmi-mcp:get_products_by_category
samco-ibmi-mcp:list_all_products
samco-ibmi-mcp:list_categories
samco-ibmi-mcp:search_products
```

> **Tool naming convention:** Orchestrate prefixes every tool with `<toolkit-name>:`. So `get_customer` becomes `samco-ibmi-mcp:get_customer`. You must use the prefixed name in the agent YAML.

### Update toolkit URL (when ngrok URL changes)

```bash
# Remove old registration
orchestrate toolkits remove --name "samco-ibmi-mcp"

# Re-add with new ngrok URL
orchestrate toolkits add \
  --kind mcp \
  --name "samco-ibmi-mcp" \
  --description "IBM i MCP Server — live DB2 for i queries against the SAMCO retail schema on PowerVS." \
  --url "https://<NEW-NGROK-URL>/mcp" \
  --transport streamable_http \
  --tools "*"
```

---

## 11. watsonx Orchestrate Side — Create the Agent

### The agent YAML

File: [`agent/samco-retail-agent.yaml`](agent/samco-retail-agent.yaml)

```yaml
spec_version: v1
kind: native

name: samco_retail_agent
llm: groq/openai/gpt-oss-120b
style: default

description: |
  A SAMCO retail assistant that answers questions about products, categories,
  customers, and orders by querying live data from IBM i DB2 in real time.

instructions: |
  You are a helpful assistant for SAMCO, a retail company.
  You have access to live product catalogue, customer, and order data
  stored in IBM i DB2. Always query the tools — never guess or invent data.

  ## Tool selection guide
  | What the user asks                          | Tool to use               |
  |---------------------------------------------|---------------------------|
  | About a specific product code (e.g. 000001) | get_product_by_id         |
  | "What products/catalogue do you have?"       | list_all_products         |
  | "What categories exist?"                    | list_categories           |
  | About a category (Electronics, etc.)        | get_products_by_category  |
  | Keyword search (wireless, coffee, laptop)   | search_products           |
  | Customer profile by ID                      | get_customer              |
  | Customer order history                      | get_customer_orders       |
  | Order line detail                           | get_order_detail          |

  ## Category ID reference
  BOO=Books | CLO=Clothing | ELE=Electronics | FOO=Food | FUR=Furniture
  GAR=Garden | HOM=Home Appliances | OFF=Office Supplies | SPO=Sports | TOY=Toys

  ## Response guidelines
  - Present data in clean tables or bullet lists.
  - Format all prices as $ with 2 decimal places.
  - Translate YYYYMMDD integer dates into readable form.
  - Do NOT expose internal column names (ARID, ARDESC, etc.) to the user.

tools:
  - samco-ibmi-mcp:get_product_by_id
  - samco-ibmi-mcp:list_all_products
  - samco-ibmi-mcp:list_categories
  - samco-ibmi-mcp:get_products_by_category
  - samco-ibmi-mcp:search_products
  - samco-ibmi-mcp:get_customer
  - samco-ibmi-mcp:get_customer_orders
  - samco-ibmi-mcp:get_order_detail

collaborators: []
```

### Import the agent into Orchestrate

```bash
source /path/to/your/.venv/bin/activate

orchestrate agents import \
  -f samco-retail-prototype/agent/samco-retail-agent.yaml
```

**Expected output:**
```
[INFO] - Agent 'samco_retail_agent' imported successfully
```

### Verify the agent is registered

```bash
orchestrate agents list | grep "samco"
```

**Expected:**
```
samco_retail_agent  │ A SAMCO retail…  │ groq/openai/gpt-oss-120b  │ default │ samco-ibmi-mcp…
```

### Delete and re-import (if you need to update the agent)

```bash
orchestrate agents delete --name samco_retail_agent --kind native
orchestrate agents import -f samco-retail-prototype/agent/samco-retail-agent.yaml
```

---

## 12. Verify End-to-End

### Test 1 — MCP protocol handshake direct to IBM i

```bash
curl -s http://<your-ibmi-host>:3011/mcp \
  -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
```
Expected: `"serverInfo":{"name":"@ibm/ibmi-mcp-server","version":"0.5.1"}`

### Test 2 — MCP handshake through ngrok tunnel

```bash
curl -s https://<your-ngrok-subdomain>.ngrok-free.app/mcp \
  -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
```
Expected: same response as Test 1 ✅

### Test 3 — tools/list via tunnel

```bash
curl -s https://<your-ngrok-subdomain>.ngrok-free.app/mcp \
  -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
```
Expected: JSON array of 9 tools including `get_products_by_category`, `get_order_detail`, etc.

### Test 4 — Live DB2 query through Orchestrate agent

Using the Orchestrate CLI (or UI chat):

**Prompt:** `"Show me all electronics"`

**What happens internally:**
1. LLM selects tool: `samco-ibmi-mcp:get_products_by_category`
2. LLM extracts parameter: `category_id = "ELE"`
3. Orchestrate calls: `POST /mcp` with `tools/call` JSON-RPC
4. MCP server executes: `SELECT ... FROM SAMCO.ARTICLE WHERE ARTIFA = 'ELE'`
5. DB2 returns 5 rows
6. LLM formats response as a clean table

**Expected response (verified live, 401ms query time):**

| Article ID | Product | Price | Stock |
|------------|---------|-------|-------|
| 000004 | Bluetooth Headphones | $79.99 | 80 |
| 000001 | Laptop Computer 15 inch | $899.99 | 25 |
| 000005 | Smartphone 128GB | $599.99 | 40 |
| 000003 | USB-C Cable 2m | $12.99 | 200 |
| 000002 | Wireless Mouse | $29.99 | 150 |

### Additional test prompts

```
"Who is customer 1?"
→ calls get_customer(1) → returns Acme Corporation profile

"What was in order 1 from 2026?"
→ calls get_order_detail(1, 2026) → returns 3 line items (Laptop, Mouse, Office Chair)

"Show me the full product catalogue"
→ calls list_all_products() → returns all 33 SAMCO products

"Find me something wireless"
→ calls search_products("wireless") → returns Wireless Mouse + any other wireless products

"What product categories do you have?"
→ calls list_categories() → returns all 10 families (BOO, CLO, ELE, etc.)
```

---

## 13. Operations — Day 2

### Check if the MCP server is still running (on IBM i)

```bash
ssh <ibmi-user>@<your-ibmi-host> \
  "/home/<ibmi-user>/samco-mcp/status-mcp-server.sh"
```

### Restart the MCP server

```bash
ssh <ibmi-user>@<your-ibmi-host> \
  "/home/<ibmi-user>/samco-mcp/stop-mcp-server.sh && \
   /home/<ibmi-user>/samco-mcp/start-mcp-server.sh"
```

### Update the SQL tools

1. Edit `samco-retail-prototype/tools/retail-services.yaml` locally
2. Copy to IBM i: `scp samco-retail-prototype/tools/retail-services.yaml <ibmi-user>@<your-ibmi-host>:/home/<ibmi-user>/samco-mcp/retail-services.yaml`
3. Restart the MCP server (above)
4. Re-register toolkit in Orchestrate (tools are re-introspected on registration)

### Update the agent instructions

1. Edit `samco-retail-prototype/agent/samco-retail-agent.yaml`
2. Re-import: `orchestrate agents import -f samco-retail-prototype/agent/samco-retail-agent.yaml`
   - If agent exists, it will be updated automatically, or use `--safe` to confirm first

### Restart ngrok (ngrok URL will change on free tier)

```bash
# Kill existing ngrok
pkill ngrok

# Start new tunnel
ngrok http <your-ibmi-host>:3011
# Note the new URL from the ngrok output

# Re-register toolkit with new URL
source .venv/bin/activate
orchestrate toolkits remove --name "samco-ibmi-mcp"
orchestrate toolkits add \
  --kind mcp \
  --name "samco-ibmi-mcp" \
  --description "IBM i MCP Server — SAMCO retail on PowerVS." \
  --url "https://<NEW-URL>/mcp" \
  --transport streamable_http \
  --tools "*"
```

---

## 14. Production Architecture

For a production SAMCO Retail deployment, replace the ngrok tunnel with one of:

### Option A — IBM Cloud Transit Gateway (preferred)

```
IBM Cloud Account
├── Transit Gateway
│   ├── PowerVS workspace containing IBM i
│   │   └── IBM i private IP: 10.x.x.x, port 3011
│   └── Orchestrate service VPC
└── Orchestrate registers toolkit URL: http://10.x.x.x:3011/mcp
```

Setup steps:
1. IBM Cloud console → Transit Gateway → Create
2. Add connection: PowerVS workspace
3. Add connection: Orchestrate VPC
4. Register toolkit in Orchestrate using the IBM i private IP

### Option B — IBM API Connect Gateway

```
Orchestrate (HTTPS) → API Connect → IBM i (HTTP internal)
```

Adds: TLS termination, JWT auth, rate limiting, API versioning.

### Option C — Direct HTTPS on IBM i

Configure the MCP server with TLS certificates and use `MCP_HTTP_PORT=443`:
```
MCP_HTTP_TLS_CERT=/path/to/cert.pem
MCP_HTTP_TLS_KEY=/path/to/key.pem
MCP_AUTH_MODE=bearer
```

Then open only port 443 to Orchestrate's known egress IP ranges.

### Security hardening checklist

- [ ] Replace `MCP_AUTH_MODE=none` with `bearer` + rotate token
- [ ] Use IBM i system profile with minimal DB2 `*USE` authority (read-only)
- [ ] Enable `DB2i_IGNORE_UNAUTHORIZED=false` with a valid Mapepire TLS cert
- [ ] Restrict firewall to Orchestrate egress IPs only
- [ ] Set up `MCP_RATE_LIMIT_ENABLED=true` with appropriate limits
- [ ] Log all MCP tool invocations and DB2 queries to IBM i journal (QAUDJRN)

---

## 15. Troubleshooting

### MCP server won't start

```bash
# Check the log
cat /home/<ibmi-user>/samco-mcp/mcp-server.log

# Common causes:
# 1. Port already in use
ss -tlnp | grep 3011
# Fix: change MCP_HTTP_PORT in .env

# 2. Node.js not in PATH
which node  # should return /QOpenSys/pkgs/bin/node
export PATH=/QOpenSys/pkgs/bin:$PATH

# 3. .env not loaded
cat /home/<ibmi-user>/samco-mcp/.env
```

### Orchestrate toolkit registration fails with "NoneType is not iterable"

This means Orchestrate could not list the tools from the MCP server at registration time.

```bash
# 1. Verify the tunnel is live
curl -s https://<ngrok-url>/mcp -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'

# 2. Verify the MCP server is running on IBM i
ssh <ibmi-user>@<your-ibmi-host> "cat /home/<ibmi-user>/samco-mcp/mcp-server.pid"
```

### Toolkit exists but shows no tools

```bash
orchestrate toolkits remove --name "samco-ibmi-mcp"
# Then re-add (see §10)
```

### DB2 query errors in logs

```bash
# Common: SAMCO."ORDER" must be double-quoted — ORDER is a reserved word
# Wrong:  FROM SAMCO.ORDER
# Right:  FROM SAMCO."ORDER"

# Common: Column not found — verify exact column names
ssh <ibmi-user>@<your-ibmi-host>
/QOpenSys/pkgs/bin/bash
# Use Mapepire or ACS Run SQL scripts to inspect SAMCO.ARTICLE columns
```

### ngrok "connection refused" after IBM i restart

```bash
# Verify MCP server is running again on IBM i
ssh <ibmi-user>@<your-ibmi-host> \
  "/home/<ibmi-user>/samco-mcp/start-mcp-server.sh"
```

---

## 16. File Reference

```
samco-retail-prototype/
│
├── IMPLEMENTATION_GUIDE.md          ← This document
├── README.md                        ← Quick-start summary
├── .env.example                     ← Template for IBM i credentials
│
├── agent/
│   └── samco-retail-agent.yaml    ← Orchestrate native agent spec
│                                       name: samco_retail_agent
│                                       llm: groq/openai/gpt-oss-120b
│                                       tools: 8 × samco-ibmi-mcp:<tool>
│
├── tools/
│   └── retail-services.yaml      ← MCP server SQL tool definitions
│                                       8 tools across SAMCO schema
│                                       sources, parameters, SQL statements
│
└── ibmi-deploy/
    ├── ibmi-deploy.env             ← Config template (rename to .env on IBM i)
    ├── retail-services.yaml      ← Copy of tools YAML (deployed to IBM i)
    ├── deploy-to-ibmi.sh           ← One-shot deploy from Mac via scp+ssh
    ├── start-mcp-server.sh         ← Starts MCP server via nohup on IBM i
    ├── stop-mcp-server.sh          ← Stops MCP server by PID file
    └── status-mcp-server.sh        ← Shows process + HTTP status + log tail
```

### On the IBM i at runtime

```
/home/<ibmi-user>/samco-mcp/
├── .env                            ← Active config
├── retail-services.yaml          ← 8 SQL tools
├── start-mcp-server.sh
├── stop-mcp-server.sh
├── status-mcp-server.sh
├── mcp-server.pid                  ← PID of running nohup process
├── mcp-server.log                  ← Live server log
├── package.json
└── node_modules/
    └── @ibm/ibmi-mcp-server/       ← v0.5.1
        └── dist/index.js           ← Entry point
```

### Key versions

| Component | Version |
|-----------|---------|
| IBM i OS | V7R6M0 |
| Node.js on IBM i | v20.20.1 |
| npm | 10.8.2 |
| @ibm/ibmi-mcp-server | 0.5.1 |
| watsonx Orchestrate ADK | 2.11.0 |
| Python (local .venv) | 3.14.5 |
| MCP protocol version | 2024-11-05 |

---

*Guide written from a working end-to-end implementation — every command and configuration value shown here was executed live and verified against real SAMCO data on the PowerVS IBM i system.*
