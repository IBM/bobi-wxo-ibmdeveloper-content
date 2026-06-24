# IBM Developer Works — Article Submission

> **Instructions:** Copy each section below into the corresponding field of the IBM Developer submission form.
> The image shows fields: Submitter's email, Title, Excerpt, Audience — and likely more below.
> Each field is filled with ready-to-paste content.

---

## Field 1 — Submitter's Email Address

```
<your IBM email address>
```

---

## Field 2 — Title of Content
*(255 character max — descriptive title for the blog, article, or tutorial)*

```
Connecting IBM i (DB2 for i) to watsonx Orchestrate Using Bob and the IBM i MCP Server
```

**Character count: 87 / 255**

---

## Field 3 — Excerpt
*(2000 character max — 2-3 paragraphs: what it covers + why a reader needs it)*

```
IBM i systems hold decades of mission-critical business data in DB2 for i, yet
exposing that data to modern AI agents has historically required complex middleware,
custom APIs, or full application rewrites. This article shows a different path:
using Bob (the IBM AI-powered developer assistant) as a coding co-pilot alongside
the open-source IBM i MCP Server (github.com/IBM/ibmi-mcp-server) to connect a
live DB2 for i database directly to a watsonx Orchestrate AI agent — with no
custom application code written from scratch.

The article walks through the complete end-to-end journey: using Bob's IBM i
developer mode to SSH into a PowerVS IBM i system, inspect a real DB2 schema,
install and configure the MCP server as a PASE background process, define SQL
query tools in a simple YAML file, expose the server through a secure tunnel,
and register it as a remote MCP toolkit in watsonx Orchestrate. A native
Orchestrate agent is then deployed that translates natural-language questions —
"Show me all electronics", "Who is customer 1?", "What was in order 1 from
2026?" — into live DB2 queries returning real results in under 500 milliseconds.

By the end of this article, readers will understand the full architecture: how
the Model Context Protocol (MCP) bridges watsonx Orchestrate and IBM i DB2, why
no custom skill code is needed, how to handle the network connectivity challenge
between IBM Cloud SaaS and a private PowerVS system, and the three query design
patterns available — static SQL tools, dynamic Text-to-SQL, and a hybrid
production approach — each with a security model appropriate for IBM i
environments.
```

**Character count: ~1,580 / 2000**

---

## Field 4 — Audience
*(Who is the primary audience and what will they learn)*

```
This article targets two overlapping audiences:

1. IBM i developers and architects who want to expose existing DB2 for i data
to AI agents without rewriting applications. They will learn how the IBM i MCP
Server works, how to configure it in PASE using Node.js (already available via
IBM i Open Source), and how to define SQL tools using a YAML file that maps
directly to their existing schema — no Java, no RPG changes, no middleware.

2. watsonx Orchestrate practitioners and AI solution architects building
enterprise agents that need to reach legacy or on-premises data sources. They
will learn the remote MCP toolkit registration pattern, the difference between
a toolkit and an agent, how tool naming (toolkit:tool_name) works in Orchestrate,
and how to design agent instructions that route questions to the right DB2 query
tool reliably.

Both audiences will gain practical knowledge of the Model Context Protocol (MCP)
as an integration standard, the security considerations unique to IBM i (DB2 user
authority, SELECT-only enforcement, Mapepire TLS), and a migration path from
static pre-written SQL tools toward dynamic Text-to-SQL generation for analyst
use cases. Readers should have basic familiarity with IBM i and with AI agent
concepts, but no prior MCP or Orchestrate experience is required.
```

---

## Field 5 — Content Type
*(Select from: Blog post / Tutorial / Article / Code pattern)*

```
Tutorial
```

*Rationale: The article is step-by-step, reproducible, and includes verified
commands, configuration files, and expected outputs at each stage.*

---

## Field 6 — Tags / Keywords

```
IBM i, DB2 for i, watsonx Orchestrate, MCP, Model Context Protocol,
IBM i MCP Server, Bob, PowerVS, PASE, AI agent, Text-to-SQL,
Mapepire, ngrok, IBM Cloud, enterprise AI, legacy modernization
```

---

## Field 7 — Outline / Structure of the Article

```
1. Introduction — The problem: AI agents can't easily reach IBM i DB2
   - Why IBM i data is valuable but isolated
   - What MCP is and why it changes the equation
   - What Bob Premium Package adds (IBM i developer mode, SSH tools,
     schema introspection, code generation)

2. Architecture overview
   - The 3-layer stack: Orchestrate → MCP toolkit → IBM i PASE process → DB2
   - Why the agent and the IBM i are decoupled by design
   - Network challenge: IBM Cloud SaaS vs private PowerVS (and how to solve it)

3. IBM i side — Step-by-step setup using Bob
   a. Using Bob to SSH in and verify prerequisites (Node.js, Mapepire)
   b. Using Bob to inspect the DB2 schema (DESCRIBE TABLE, DDL introspection)
   c. Installing @ibm/ibmi-mcp-server via npm in PASE
   d. Writing the .env configuration (DB2i_HOST=localhost, port 3011, HTTP mode)
   e. Defining SQL tools in retail-services.yaml (bind variables, readOnly flag)
   f. Starting the server as a nohup background process
   g. Verifying with a live MCP protocol handshake (curl test)

4. Network connectivity — Exposing IBM i to Orchestrate
   - Dev/demo: ngrok tunnel from Mac to IBM i
   - Production: IBM Cloud Transit Gateway (private backbone, zero firewall)

5. watsonx Orchestrate side — Step-by-step setup
   a. Activating the ADK virtual environment
   b. Registering the remote MCP toolkit (orchestrate toolkits add)
   c. Verifying all 9 tools were imported
   d. Writing the agent YAML (instructions, tool routing table, tool list)
   e. Importing the agent (orchestrate agents import)

6. End-to-end verification
   - "Show me all electronics" → 5 live DB2 rows, 401ms latency
   - Full JSON response shown (actual output, not mock data)
   - Tracing the call: user → LLM → toolkit URL → ngrok → IBM i → DB2 → response

7. Three query design patterns
   - Static SQL tools: pre-written, safe, predictable (production default)
   - Dynamic Text-to-SQL: LLM generates SQL at runtime (analyst use case)
   - Hybrid: static first, dynamic fallback (recommended for production)
   - Security model: SELECT-only guard, validate_query, IBM i *USE authority

8. Conclusion and next steps
   - No custom skill code was written — MCP + YAML is sufficient
   - Production path: Transit Gateway replaces ngrok
   - Extensibility: same pattern applies to any IBM i schema
   - Resources: github.com/IBM/ibmi-mcp-server, Bob documentation
```

---

## Field 8 — Abstract (for internal IBM review)

```
This tutorial demonstrates a complete, working integration between IBM i DB2
for i and watsonx Orchestrate, achieved entirely through configuration — no
custom application code. The approach uses Bob (IBM's AI developer assistant
with IBM i Premium capabilities) to guide every step: SSH-based schema
discovery, MCP server installation in PASE, SQL tool definition via YAML,
and Orchestrate agent deployment via the ADK CLI.

The core technology is @ibm/ibmi-mcp-server (open source, Apache-2.0,
github.com/IBM/ibmi-mcp-server), which runs as a Node.js HTTP server in
IBM i PASE and exposes DB2 queries as MCP-compliant tools. Orchestrate
registers this server as a remote MCP toolkit using the streamable_http
transport, and a native Orchestrate agent is configured to route
natural-language questions to the appropriate DB2 tool.

The article is based on a verified working prototype built on a PowerVS
IBM i V7R6M0 system using the SAMCO retail application schema. Every
command, configuration value, and expected output shown in the article
was tested live. Query latency measured end-to-end was 401ms including
a public ngrok tunnel — well within acceptable interactive response times.

Key differentiator: this integration requires no RPG changes, no Java
middleware, no REST API development, and no watsonx custom skill code.
It demonstrates that IBM i systems can participate in modern AI agent
architectures today, using only open-source tooling already available
on the platform.
```

---

## Field 9 — Related IBM Products / Technologies

```
- IBM i (OS/400, i5/OS) — V7R3 and above
- DB2 for i (Db2 for IBM i)
- IBM PowerVS (Power Virtual Server)
- watsonx Orchestrate (SaaS, IBM Cloud)
- watsonx Orchestrate ADK (Agent Developer Kit) v2.11
- Bob (IBM AI developer assistant, Premium Package — IBM i mode)
- IBM i Open Source (yum/ACS — Node.js, npm)
- Mapepire (IBM i DB2 connectivity layer)
- IBM Cloud Transit Gateway (production networking)
- @ibm/ibmi-mcp-server v0.5.1 (open source)
- Model Context Protocol (MCP) — Anthropic open standard
```

---

## Field 10 — GitHub Repository / Code Sample

```
Repository structure that will accompany the article:

samco-retail-prototype/
├── tools/
│   └── retail-services.yaml    ← 8 SQL tool definitions (ready to use)
├── agent/
│   └── samco-retail-agent.yaml  ← Orchestrate agent spec
├── ibmi-deploy/
│   ├── ibmi-deploy.env           ← .env template for IBM i
│   ├── start-mcp-server.sh       ← PASE startup script
│   ├── stop-mcp-server.sh
│   └── status-mcp-server.sh
├── IMPLEMENTATION_GUIDE.md       ← Full step-by-step reference
└── QUERY_APPROACHES.md           ← Static vs Dynamic vs Hybrid analysis
```

---

## Field 11 — Estimated Reading / Completion Time

```
Reading time (article only):     ~15 minutes
Hands-on completion time:        ~2 hours
  - IBM i setup:                 45 minutes
  - Network (ngrok):             15 minutes
  - Orchestrate setup:           30 minutes
  - Verification + testing:      30 minutes
```

---

## Full Draft Article Text
*(Paste this into the article body / content field if the form has one)*

---

### Connecting IBM i (DB2 for i) to watsonx Orchestrate Using Bob and the IBM i MCP Server

---

#### Introduction

Thousands of enterprises run business-critical applications on IBM i. Their data — orders, customers, inventory, payments — lives in DB2 for i tables that have been refined over decades. But when organisations want to expose that data to modern AI agents, the answer has usually been "build a REST API first", "migrate the data to a cloud database", or "use a middleware layer." That's expensive, time-consuming, and often politically difficult.

The IBM i MCP Server (https://github.com/IBM/ibmi-mcp-server), referenced by Jesse Gorzinski of IBM US, changes this. It runs directly on the IBM i as a PASE process, connects to DB2 via Mapepire (the IBM i DB2 connectivity layer), and exposes any SQL query as a Model Context Protocol (MCP) tool — the same open standard used by Claude, Cursor, and now watsonx Orchestrate.

In this article, we use **Bob** (IBM's AI developer assistant with IBM i Premium Package capabilities) as a co-pilot throughout. Bob can SSH into IBM i, inspect DB2 schemas, generate correct PASE shell scripts, write SQL with proper IBM i conventions (quoted reserved words, soft-delete filters, FETCH FIRST), and register everything in Orchestrate via the ADK CLI — all from a single chat session.

The result is a live AI agent that answers natural-language questions about real IBM i data. No RPG code changes. No Java middleware. No custom Orchestrate skill code.

---

#### What is MCP and Why Does It Matter for IBM i?

The **Model Context Protocol** (MCP) is an open standard that lets AI agents call external tools over HTTP using a simple JSON-RPC protocol. An AI agent registers a "toolkit" (an MCP server URL), and at runtime calls individual tools by name, passing typed parameters and receiving structured results.

For IBM i, this means:

```
User: "Show me all electronics"
         ↓
watsonx Orchestrate agent
         ↓  MCP tools/call → get_products_by_category(ELE)
IBM i MCP Server (PASE, port 3011)
         ↓  Mapepire
DB2 for i: SELECT ... FROM SAMCO.ARTICLE WHERE ARTIFA = 'ELE'
         ↑
5 rows returned in 401ms
```

The agent never directly connects to DB2. It calls an MCP tool. The MCP server — running on the IBM i itself — handles the DB2 connection. This separation is what makes the integration clean, secure, and replicable.

---

#### Prerequisites

**On the IBM i system:**
- IBM i V7R3M0 or higher (V7R6M0 used here)
- Node.js v18+ installed via IBM i Open Source (yum/ACS)
- Mapepire service running on port 8076
- SSH access with a user that has DB2 `*USE` read authority

**On your local machine:**
- Bob Premium Package (with IBM i developer mode)
- Python `.venv` with `ibm-watsonx-orchestrate` ADK installed
- `ngrok` (for dev/demo) or IBM Cloud Transit Gateway (for production)

**In watsonx Orchestrate:**
- Active SaaS account and ADK environment configured

---

#### Step 1 — Discover the IBM i System Using Bob

Open Bob and activate IBM i developer mode. Bob can SSH into the system and verify every prerequisite before a single file is deployed:

```bash
# Bob executes these via its IBM i SSH tools
ssh <ibmi-user>@<your-ibmi-host> \
  "export PATH=/QOpenSys/pkgs/bin:\$PATH && node --version && npm --version"
# Output: v20.20.1 / 10.8.2  ✅

# Bob inspects the DB2 schema using the MCP server's describe_sql_object tool
# Returns full CREATE TABLE DDL for SAMCO.ARTICLE including all column names,
# types, CCSID, and IBM i column labels — the source of truth for SQL authoring
```

Bob uses this DDL output to generate correct SQL throughout the setup — knowing, for example, that `ORDER` is a reserved word requiring double-quoting (`SAMCO."ORDER"`), that deleted records are flagged with `ARDEL = 'X'`, and that article IDs are `CHAR(6)` not integers.

---

#### Step 2 — Install the IBM i MCP Server

From your local machine, Bob deploys the server in one SSH session:

```bash
ssh <ibmi-user>@<your-ibmi-host>
export PATH=/QOpenSys/pkgs/bin:$PATH

mkdir -p /home/<ibmi-user>/samco-mcp
cd /home/<ibmi-user>/samco-mcp
npm install @ibm/ibmi-mcp-server@latest --save
# Installs @ibm/ibmi-mcp-server@0.5.1 in ~45 seconds
```

The server entry point is `node_modules/@ibm/ibmi-mcp-server/dist/index.js`. It supports three transport modes: `stdio` (for IDE tools), `http` (for remote access), and `agent` (for embedded use). We use `http`.

---

#### Step 3 — Configure the Server

Bob generates the `.env` file based on the verified system details:

```bash
# /home/<ibmi-user>/samco-mcp/.env
DB2i_HOST=localhost        # MCP server is ON the IBM i — no network hop needed
DB2i_PORT=8076             # Mapepire default port
DB2i_USER=YOUR_IBMI_USERNAME
DB2i_PASS=<password>
DB2i_IGNORE_UNAUTHORIZED=true   # Mapepire uses self-signed cert in lab

MCP_TRANSPORT_TYPE=http
MCP_HTTP_PORT=3011          # 3010 was already in use — 3011 is clean
MCP_HTTP_HOST=0.0.0.0       # Bind all interfaces so tunnel can reach it
MCP_AUTH_MODE=none           # Secure via tunnel in dev; use bearer in production
TOOLS_YAML_PATH=./retail-services.yaml
```

Key insight: `DB2i_HOST=localhost` because the MCP server runs **on the same IBM i machine** as DB2. Mapepire is a local socket connection — no network latency, no firewall, no credentials travelling over the network.

---

#### Step 4 — Define SQL Tools in YAML

Bob generates the SQL tool definitions in `retail-services.yaml`, writing correct DB2 for i SQL using the DDL it introspected in Step 1:

```yaml
sources:
  samco-db:
    host: ${DB2i_HOST}
    user: ${DB2i_USER}
    password: ${DB2i_PASS}
    port: ${DB2i_PORT}
    ignore-unauthorized: true

tools:
  get_products_by_category:
    source: samco-db
    description: >
      List all products in a category using the 3-letter ID.
      ELE=Electronics, FUR=Furniture, CLO=Clothing, etc.
    parameters:
      - name: category_id
        type: string
        required: true
        enum: ["BOO","CLO","ELE","FOO","FUR","GAR","HOM","OFF","SPO","TOY"]
    security:
      readOnly: true
    statement: |
      SELECT A.ARID AS ARTICLE_ID, TRIM(A.ARDESC) AS PRODUCT_NAME,
             A.ARSALEPR AS SALE_PRICE, A.ARSTOCK AS STOCK_LEVEL
      FROM SAMCO.ARTICLE A
      WHERE A.ARTIFA = :category_id
        AND A.ARDEL <> 'X'       ← soft-delete filter, correct for IBM i
      ORDER BY A.ARDESC
      FETCH FIRST 50 ROWS ONLY   ← IBM i syntax (not LIMIT)
```

Three IBM i-specific SQL conventions Bob applied automatically:
1. **Bind variables** (`:category_id`) — not string concatenation, no SQL injection
2. **Soft-delete filter** (`ARDEL <> 'X'`) — IBM i applications use a delete flag, not physical deletes
3. **FETCH FIRST N ROWS ONLY** — the DB2 for i row-limiting syntax (not MySQL's `LIMIT`)

Eight tools were defined covering products, categories, customers, and orders.

---

#### Step 5 — Start the MCP Server as a PASE Background Process

```bash
# On IBM i — Bob generated this script
export PATH=/QOpenSys/pkgs/bin:$PATH
cd /home/<ibmi-user>/samco-mcp

set -o allexport; source .env; set +o allexport

nohup /QOpenSys/pkgs/bin/node \
  node_modules/@ibm/ibmi-mcp-server/dist/index.js \
  --transport http \
  --tools ./retail-services.yaml \
  >> mcp-server.log 2>&1 &

echo $! > mcp-server.pid
```

**Verify the server is responding:**

```bash
curl -s http://localhost:3011/mcp \
  -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{
        "protocolVersion":"2024-11-05","capabilities":{},
        "clientInfo":{"name":"test","version":"1.0"}}}'

# Response:
# event: message
# data: {"result":{"protocolVersion":"2024-11-05",
#        "serverInfo":{"name":"@ibm/ibmi-mcp-server","version":"0.5.1"}...}}
```

The IBM i MCP server is live.

---

#### Step 6 — Network Connectivity

The PowerVS IBM i is on a private network. watsonx Orchestrate SaaS (IBM Cloud public) cannot reach it directly.

**For development/demo — ngrok tunnel** (runs on your Mac, not on IBM i):

```bash
ngrok http <your-ibmi-host>:3011
# Prints: https://<your-ngrok-subdomain>.ngrok-free.app → IBM i:3011
```

Verify the tunnel reaches IBM i:
```bash
curl -s https://<ngrok-url>/mcp -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{...}}'
# Same response as local ✅
```

**For production — IBM Cloud Transit Gateway:**
Connect your PowerVS workspace and Orchestrate VPC to the same Transit Gateway. Use the IBM i's private IP directly — no public exposure, IBM private backbone only.

---

#### Step 7 — Register the Toolkit in watsonx Orchestrate

```bash
source .venv/bin/activate

orchestrate toolkits add \
  --kind mcp \
  --name "samco-ibmi-mcp" \
  --description "IBM i MCP Server — live DB2 for i on PowerVS." \
  --url "https://<ngrok-url>/mcp" \
  --transport streamable_http \
  --tools "*"

# Output: [INFO] - Successfully imported tool kit samco-ibmi-mcp
```

Verify all tools were imported:
```bash
orchestrate tools list | grep "samco-ibmi"
# samco-ibmi-mcp:get_product_by_id
# samco-ibmi-mcp:list_all_products
# samco-ibmi-mcp:list_categories
# samco-ibmi-mcp:get_products_by_category
# samco-ibmi-mcp:search_products
# samco-ibmi-mcp:get_customer
# samco-ibmi-mcp:get_customer_orders
# samco-ibmi-mcp:get_order_detail
# samco-ibmi-mcp:describe_sql_object
# → 9 tools ✅
```

Note the **`samco-ibmi-mcp:` prefix**. Orchestrate namespaces every tool under its toolkit. The agent must reference tools with this prefix.

---

#### Step 8 — Deploy the Orchestrate Agent

Bob generates the agent YAML based on the confirmed tool names and schema knowledge:

```yaml
spec_version: v1
kind: native

name: samco_retail_agent
llm: groq/openai/gpt-oss-120b
style: default

description: |
  SAMCO retail assistant — answers questions about products, customers,
  and orders using live IBM i DB2 data.

instructions: |
  You are a helpful assistant for SAMCO.
  Always query the tools — never guess or invent data.

  | User asks                     | Tool to call              |
  |-------------------------------|---------------------------|
  | About a product code          | get_product_by_id         |
  | Full catalogue                | list_all_products         |
  | What categories exist         | list_categories           |
  | Products in a category        | get_products_by_category  |
  | Keyword search                | search_products           |
  | Customer profile              | get_customer              |
  | Customer order history        | get_customer_orders       |
  | Order line detail             | get_order_detail          |

tools:
  - samco-ibmi-mcp:get_product_by_id
  - samco-ibmi-mcp:list_all_products
  - samco-ibmi-mcp:list_categories
  - samco-ibmi-mcp:get_products_by_category
  - samco-ibmi-mcp:search_products
  - samco-ibmi-mcp:get_customer
  - samco-ibmi-mcp:get_customer_orders
  - samco-ibmi-mcp:get_order_detail
```

```bash
orchestrate agents import -f agent/samco-retail-agent.yaml
# Output: [INFO] - Agent 'samco_retail_agent' imported successfully
```

---

#### Step 9 — End-to-End Verification

**Prompt:** *"Show me all electronics"*

The agent called `get_products_by_category("ELE")`. The MCP server executed:

```sql
SELECT A.ARID AS ARTICLE_ID, TRIM(A.ARDESC) AS PRODUCT_NAME,
       A.ARSALEPR AS SALE_PRICE, A.ARSTOCK AS STOCK_LEVEL
FROM SAMCO.ARTICLE A
WHERE A.ARTIFA = 'ELE' AND A.ARDEL <> 'X'
ORDER BY A.ARDESC FETCH FIRST 50 ROWS ONLY
```

**Actual response from live DB2 (401ms end-to-end):**

| Article ID | Product | Price | Stock |
|------------|---------|-------|-------|
| 000004 | Bluetooth Headphones | $79.99 | 80 |
| 000001 | Laptop Computer 15 inch | $899.99 | 25 |
| 000005 | Smartphone 128GB | $599.99 | 40 |
| 000003 | USB-C Cable 2m | $12.99 | 200 |
| 000002 | Wireless Mouse | $29.99 | 150 |

Live IBM i DB2 data, delivered through watsonx Orchestrate, in under half a second. ✅

---

#### Three Query Design Patterns

Now that the foundation is in place, three patterns are available depending on your use case:

**Pattern 1 — Static SQL Tools (shown above)**
Pre-written SQL in YAML. The LLM only decides which tool to call and what parameter values to pass. 100% predictable, zero SQL injection risk, ideal for production business workflows.

**Pattern 2 — Dynamic Text-to-SQL**
Add `execute_sql` and `validate_query` tools to the agent. Embed the full schema DDL in the agent instructions. The LLM generates SQL at runtime, validates it, and executes it — answering any question the schema supports. Best for analyst/reporting use cases. Requires: SELECT-only enforcement in instructions, `validate_query` before every `execute_sql`, and IBM i `*USE` authority on the DB2 user.

**Pattern 3 — Hybrid (recommended for production)**
Keep the 8 static tools for known business questions (fast, safe). Add `execute_sql` + `validate_query` as a fallback for ad-hoc questions no static tool covers. The LLM chooses the right path based on the agent instructions.

---

#### Architecture: Why the Agent Has No Direct IBM i Connection

A common question when viewing the agent in the Orchestrate UI: "Where is the IBM i connection?" The answer is that the IBM i endpoint is stored in the **toolkit**, not the agent. The agent only stores tool names. The toolkit stores the URL. This decoupling is intentional:

```
Agent (samco_retail_agent)
  → knows: "I have tool samco-ibmi-mcp:get_products_by_category"
  → does NOT know: the IBM i IP, ngrok URL, DB2 credentials

Toolkit (samco-ibmi-mcp)
  → stores: https://<ngrok-url>/mcp, transport: streamable_http
  → bridges: Orchestrate ↔ IBM i

IBM i (.env)
  → stores: DB2 credentials, Mapepire port, SQL definitions
```

You can change the IBM i endpoint (e.g. swap ngrok for Transit Gateway) by updating only the toolkit registration — the agent is unchanged.

---

#### Conclusion

The combination of Bob, the IBM i MCP Server, and watsonx Orchestrate creates a path to expose any DB2 for i data to an AI agent with:

- **No custom code** — YAML configuration, not programming
- **No schema changes** — the existing IBM i tables are queried as-is
- **No middleware** — the MCP server runs directly on IBM i PASE
- **No data movement** — DB2 data stays on IBM i, only query results travel
- **Production-ready architecture** — IBM Cloud Transit Gateway for secure private connectivity

The same pattern applies to any IBM i application: ERP, HRMS, payment processing, order management. If it has a DB2 schema and a user with read authority, it can have a watsonx Orchestrate AI agent in under two hours.

**Resources:**
- IBM i MCP Server: https://github.com/IBM/ibmi-mcp-server
- watsonx Orchestrate ADK: `pip install ibm-watsonx-orchestrate`
- Bob documentation: https://ibm.biz/bob-docs
- IBM i Open Source: https://ibm.biz/ibmi-oss

---

*Article based on a verified working prototype built on PowerVS IBM i V7R6M0
with the SAMCO retail schema. All commands, configuration values, and outputs
shown were executed live and verified.*
