# IBM i DB2 Query Approaches — Static vs Dynamic vs Hybrid

**Project:** SAMCO Retail Phase 2 — IBM i DB2 with watsonx Orchestrate  
**Applies to:** `@ibm/ibmi-mcp-server` v0.5.1 on PowerVS IBM i V7R6M0  
**Related document:** [`IMPLEMENTATION_GUIDE.md`](IMPLEMENTATION_GUIDE.md)  
**Status:** Approach 1 implemented and verified ✅ — Approaches 2 & 3 designed, ready to implement

---

## Table of Contents

1. [Overview — Three Approaches](#1-overview--three-approaches)
2. [Approach 1 — Static SQL Tools (Implemented ✅)](#2-approach-1--static-sql-tools-implemented-)
3. [Approach 2 — Text-to-SQL (Dynamic Query Generation)](#3-approach-2--text-to-sql-dynamic-query-generation)
4. [Approach 3 — Hybrid (Recommended for Production)](#4-approach-3--hybrid-recommended-for-production)
5. [Security Model for Dynamic SQL on IBM i](#5-security-model-for-dynamic-sql-on-ibm-i)
6. [Feasibility Comparison Matrix](#6-feasibility-comparison-matrix)
7. [Migration Path — Phase 1 → Phase 2 → Phase 3](#7-migration-path--phase-1--phase-2--phase-3)
8. [Verified Live Evidence](#8-verified-live-evidence)

---

## 1. Overview — Three Approaches

The core question is: **who writes the SQL — the developer at authoring time, or the LLM at runtime?**

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│  APPROACH 1 — STATIC                                                        │
│  Developer writes SQL → stored in YAML → LLM picks tool + fills params     │
│                                                                             │
│  User: "Show me electronics"                                                │
│  LLM:  → get_products_by_category(ELE)  ← pre-written SQL in YAML          │
│  DB2:  → 5 rows, 401ms ✅                                                   │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  APPROACH 2 — DYNAMIC (Text-to-SQL)                                         │
│  LLM reads schema → generates SQL at runtime → validates → executes         │
│                                                                             │
│  User: "Which customers have credit > $5000 and ordered this year?"         │
│  LLM:  → reads DDL → writes SQL → validate_query → execute_sql             │
│  DB2:  → any question the schema supports                                   │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  APPROACH 3 — HYBRID (Recommended)                                          │
│  Static tools for known business flows + dynamic for ad-hoc analysis        │
│                                                                             │
│  Known question  → static tool  (fast, safe, predictable)                  │
│  Unknown question → dynamic SQL (flexible, validated, SELECT-only)          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Approach 1 — Static SQL Tools (Implemented ✅)

### How it works

The developer pre-writes every SQL query in [`tools/retail-services.yaml`](tools/retail-services.yaml). The LLM's only runtime job is to:
1. Decide **which tool** to call based on the user's question
2. Extract the correct **parameter values** from the conversation
3. **Format** the returned rows into a readable response

The SQL itself never changes at runtime.

### Architecture

```
Agent instructions
  "When user asks about a category → call get_products_by_category"
        │
        ▼
LLM selects tool: get_products_by_category
LLM extracts param: category_id = "ELE"
        │
        ▼
MCP server reads retail-services.yaml:
  statement: |
    SELECT A.ARID, TRIM(A.ARDESC), A.ARSALEPR, A.ARSTOCK
    FROM SAMCO.ARTICLE A
    WHERE A.ARTIFA = :category_id   ← bind variable substituted
      AND A.ARDEL <> 'X'
    ORDER BY A.ARDESC
    FETCH FIRST 50 ROWS ONLY
        │
        ▼
DB2 executes → returns rows → LLM formats → user sees clean table
```

### The YAML tool definition structure

```yaml
# retail-services.yaml

sources:
  samco-db:
    host: ${DB2i_HOST}       # from .env — localhost on IBM i
    user: ${DB2i_USER}
    password: ${DB2i_PASS}
    port: ${DB2i_PORT}       # 8076 (Mapepire)
    ignore-unauthorized: true

tools:
  get_products_by_category:
    source: samco-db
    description: >
      List all products within a specific category using the 3-letter
      category ID. Available IDs: BOO=Books, CLO=Clothing, ELE=Electronics,
      FOO=Food, FUR=Furniture, GAR=Garden, HOM=Home Appliances,
      OFF=Office Supplies, SPO=Sports Equipment, TOY=Toys.
    parameters:
      - name: category_id
        type: string
        required: true
        description: "3-letter category ID (e.g. ELE for Electronics)"
        enum: ["BOO","CLO","ELE","FOO","FUR","GAR","HOM","OFF","SPO","TOY"]
    security:
      readOnly: true           # marks this as SELECT-only
    statement: |
      SELECT
        A.ARID            AS ARTICLE_ID,
        TRIM(A.ARDESC)    AS PRODUCT_NAME,
        A.ARSALEPR        AS SALE_PRICE,
        A.ARSTOCK         AS STOCK_LEVEL
      FROM SAMCO.ARTICLE A
      WHERE A.ARTIFA = :category_id
        AND A.ARDEL <> 'X'
      ORDER BY A.ARDESC
      FETCH FIRST 50 ROWS ONLY
```

### The 8 tools currently deployed

| Tool | Tables | What it answers |
|------|--------|----------------|
| `get_product_by_id` | ARTICLE + FAMILLY | "Look up article 000001" |
| `list_all_products` | ARTICLE + FAMILLY | "Show me the full catalogue" |
| `list_categories` | FAMILLY | "What categories do you carry?" |
| `get_products_by_category` | ARTICLE | "Show me all electronics / furniture" |
| `search_products` | ARTICLE + FAMILLY | "Find anything wireless / coffee" |
| `get_customer` | CUSTOMER | "Who is customer 1?" |
| `get_customer_orders` | ORDER + CUSTOMER | "Show orders for Acme Corp" |
| `get_order_detail` | DETORD + ARTICLE | "What was in order 1 from 2026?" |

### Key design rules followed

```sql
-- 1. Always use bind variables — NEVER string concatenation
WHERE A.ARTIFA = :category_id        ✅
WHERE A.ARTIFA = 'ELE'               ❌ (hardcoded — not parameterised)
WHERE A.ARTIFA = '${userInput}'      ❌ (SQL injection risk)

-- 2. Always filter soft-deleted records
AND A.ARDEL <> 'X'                   ✅ (ARTICLE)
AND FADEL <> 'X'                     ✅ (FAMILLY)
AND CUDEL <> 'X'                     ✅ (CUSTOMER)

-- 3. Always limit rows
FETCH FIRST 50 ROWS ONLY             ✅

-- 4. Always quote the ORDER reserved word
FROM SAMCO."ORDER" O                 ✅
FROM SAMCO.ORDER O                   ❌ (SQL syntax error)

-- 5. Always alias columns to human-readable names
A.ARID     AS ARTICLE_ID             ✅ (agent instructions hide raw names)
A.ARID                               ❌ (LLM might expose ARID to user)
```

### When to use Approach 1

✅ Business workflows with well-defined, repeatable questions  
✅ Compliance environments where every query must be reviewed before deployment  
✅ Production IBM i with sensitive data — zero risk of unexpected SQL  
✅ Performance-critical applications — no LLM reasoning overhead per query  
✅ Demonstrating to clients (fully predictable, always works)

### When Approach 1 falls short

❌ User asks a question no tool covers: *"Show me the top 3 best-selling products by revenue"*  
❌ User wants to combine data across tables in a new way  
❌ Ad-hoc reporting / analyst use cases  
❌ Schema changes require updating every affected tool manually

---

## 3. Approach 2 — Text-to-SQL (Dynamic Query Generation)

### How it works

The LLM reads the schema (embedded in agent instructions or fetched via `describe_sql_object`), **generates a DB2 SQL query** tailored to the user's question, validates it, and executes it. No SQL is pre-written by the developer.

### Architecture

```
Agent instructions contain full schema DDL
        │
User: "Which customers have credit > $5000 and placed an order in 2026?"
        │
        ▼
Step 1 — LLM generates SQL:
  SELECT C.CUSTNM, C.CUCREDIT, COUNT(O.ORID) AS ORDER_COUNT
  FROM SAMCO.CUSTOMER C
  JOIN SAMCO."ORDER" O ON O.ORCUID = C.CUID
  WHERE C.CUCREDIT > 5000
    AND O.ORYEAR = 2026
    AND C.CUDEL <> 'X'
  GROUP BY C.CUSTNM, C.CUCREDIT
  ORDER BY C.CUCREDIT DESC
  FETCH FIRST 20 ROWS ONLY
        │
        ▼
Step 2 — validate_query(sql):
  Checks: syntax correct ✅, SAMCO.CUSTOMER exists ✅,
          CUCREDIT column exists ✅, SAMCO."ORDER" quoted ✅
        │
  If invalid: LLM corrects and retries
        │
        ▼
Step 3 — execute_sql(sql):
  DB2 runs the query → returns rows
        │
        ▼
Step 4 — LLM formats and returns clean response to user
```

### Agent YAML for Text-to-SQL

```yaml
spec_version: v1
kind: native

name: samco_analyst_agent
llm: groq/openai/gpt-oss-120b
style: default

description: |
  An ad-hoc SQL analyst for the SAMCO database. Can answer any question
  about products, customers, and orders by generating and executing live
  DB2 for i SQL queries. Uses schema introspection + query validation
  before execution for safety.

instructions: |
  You are a DB2 for i SQL expert for the SAMCO retail database.
  You answer questions by writing SQL, validating it, and executing it.
  You MUST follow all SQL rules listed below — no exceptions.

  ## SAMCO Schema Reference

  ### SAMCO.ARTICLE — Products (33 rows)
  | Column    | Type         | Description              |
  |-----------|-------------|--------------------------|
  | ARID      | CHAR(6)     | Article ID (PK)          |
  | ARDESC    | CHAR(50)    | Product description       |
  | ARSALEPR  | DEC(7,2)    | Sale price                |
  | ARWHSPR   | DEC(7,2)    | Stock/wholesale price     |
  | ARTIFA    | CHAR(3)     | Category ID (FK→FAMILLY)  |
  | ARSTOCK   | DEC(5,0)    | Current stock level       |
  | ARMINQTY  | DEC(5,0)    | Minimum stock threshold   |
  | ARCUSQTY  | DEC(5,0)    | Customer order quantity   |
  | ARPURQTY  | DEC(5,0)    | Purchase order quantity   |
  | ARVATCD   | CHAR(1)     | VAT code                  |
  | ARDEL     | CHAR(1)     | Deleted flag (X=deleted)  |

  ### SAMCO.FAMILLY — Product Categories (10 rows)
  | Column  | Type      | Description              |
  |---------|----------|--------------------------|
  | FAID    | CHAR(3)  | Category ID (PK)         |
  | FADESC  | CHAR(30) | Category description      |
  | FADEL   | CHAR(1)  | Deleted flag (X=deleted) |

  Category IDs: BOO=Books, CLO=Clothing, ELE=Electronics, FOO=Food,
  FUR=Furniture, GAR=Garden, HOM=Home Appliances, OFF=Office Supplies,
  SPO=Sports Equipment, TOY=Toys

  ### SAMCO.CUSTOMER — Customers (10 rows)
  | Column   | Type       | Description               |
  |----------|-----------|---------------------------|
  | CUID     | INTEGER   | Customer ID (PK)          |
  | CUSTNM   | CHAR(40)  | Customer name             |
  | CUCITY   | CHAR(25)  | City                      |
  | CUCOUN   | CHAR(25)  | Country                   |
  | CULIMCRE | DEC(9,2)  | Credit limit              |
  | CUCREDIT | DEC(9,2)  | Outstanding credit        |
  | CUDEL    | CHAR(1)   | Deleted flag (X=deleted)  |

  ### SAMCO."ORDER" — Orders (10 rows)  ← MUST be double-quoted
  | Column   | Type      | Description                        |
  |----------|-----------|------------------------------------|
  | ORID     | INTEGER   | Order number (PK)                  |
  | ORYEAR   | INTEGER   | Order year (PK)                    |
  | ORCUID   | INTEGER   | Customer ID (FK→CUSTOMER.CUID)     |
  | ORDATE   | INTEGER   | Order date as YYYYMMDD integer     |
  | ORDATDEL | INTEGER   | Expected delivery date (YYYYMMDD)  |
  | ORDATCLO | INTEGER   | Close date (YYYYMMDD)              |

  ### SAMCO.DETORD — Order Lines (22 rows)
  | Column   | Type      | Description                      |
  |----------|-----------|----------------------------------|
  | ODORID   | INTEGER   | Order number (FK→ORDER.ORID)     |
  | ODYEAR   | INTEGER   | Order year (FK→ORDER.ORYEAR)     |
  | ODLINE   | INTEGER   | Line number within order         |
  | ODARID   | CHAR(6)   | Article ID (FK→ARTICLE.ARID)    |
  | ODQTY    | DEC(5,0)  | Quantity ordered                 |
  | ODQTYLIV | DEC(5,0)  | Quantity delivered               |
  | ODPRICE  | DEC(7,2)  | Unit price at order time         |
  | ODTOT    | DEC(9,2)  | Line total (qty × price)         |
  | ODTOTVAT | DEC(9,2)  | Line total including VAT         |

  ## SQL Rules — MANDATORY
  1. ORDER is a reserved word — always write SAMCO."ORDER" (double-quoted)
  2. Always filter deleted records:
       ARDEL <> 'X'  (ARTICLE)
       FADEL <> 'X'  (FAMILLY)
       CUDEL <> 'X'  (CUSTOMER)
  3. Always add FETCH FIRST N ROWS ONLY (never omit — default N=50, max=100)
  4. Only write SELECT statements — never INSERT, UPDATE, DELETE, DROP, ALTER
  5. Always call validate_query BEFORE execute_sql
  6. If validate_query returns an error, fix the SQL and re-validate before executing
  7. Never expose raw column names (ARID, ARDESC etc.) to the user — alias them
  8. Dates are stored as YYYYMMDD integers — translate to readable form in your response

  ## Workflow — follow this every time
  1. Understand the user's question
  2. Write a DB2 for i SQL SELECT statement using the schema above
  3. Call validate_query(sql) to check syntax and objects
  4. If validation fails → fix and re-validate (max 2 retries)
  5. Call execute_sql(sql) to run the query
  6. Format results as a clean table or bullet list — never show raw column names

tools:
  - samco-ibmi-mcp:describe_sql_object   # introspect schema at runtime if needed
  - samco-ibmi-mcp:validate_query        # ALWAYS call before execute_sql
  - samco-ibmi-mcp:execute_sql           # run the generated SQL

collaborators: []
```

### How to deploy Approach 2

```bash
# 1. Check that execute_sql and validate_query are exposed by the running MCP server
curl -s https://<ngrok-url>/mcp \
  -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' \
  | grep -o '"name":"[^"]*"'
# Look for: execute_sql, validate_query, describe_sql_object

# 2. Re-register the toolkit if new tools appear
source .venv/bin/activate
orchestrate toolkits remove --name "samco-ibmi-mcp"
orchestrate toolkits add \
  --kind mcp \
  --name "samco-ibmi-mcp" \
  --description "IBM i MCP Server — SAMCO retail on PowerVS." \
  --url "https://<ngrok-url>/mcp" \
  --transport streamable_http \
  --tools "*"

# 3. Save the analyst agent YAML
# (write the YAML above to agent/samco-analyst-agent.yaml)

# 4. Import the agent
orchestrate agents import -f agent/samco-analyst-agent.yaml
```

### Example interactions Approach 2 enables

```
User:  "Which product category has the highest average sale price?"
SQL:   SELECT TRIM(F.FADESC) AS CATEGORY, AVG(A.ARSALEPR) AS AVG_PRICE
       FROM SAMCO.ARTICLE A
       JOIN SAMCO.FAMILLY F ON F.FAID = A.ARTIFA
       WHERE A.ARDEL <> 'X' AND F.FADEL <> 'X'
       GROUP BY F.FADESC ORDER BY AVG_PRICE DESC FETCH FIRST 10 ROWS ONLY

User:  "Show me orders that have not been closed yet"
SQL:   SELECT O.ORID, O.ORYEAR, TRIM(C.CUSTNM) AS CUSTOMER, O.ORDATE
       FROM SAMCO."ORDER" O
       JOIN SAMCO.CUSTOMER C ON C.CUID = O.ORCUID
       WHERE O.ORDATCLO = 0 AND C.CUDEL <> 'X'
       ORDER BY O.ORDATE DESC FETCH FIRST 20 ROWS ONLY

User:  "What is the total revenue from order 1 in 2026?"
SQL:   SELECT SUM(D.ODTOTVAT) AS TOTAL_WITH_VAT, SUM(D.ODTOT) AS TOTAL_EX_VAT
       FROM SAMCO.DETORD D
       WHERE D.ODORID = 1 AND D.ODYEAR = 2026
```

### Limitations to be aware of

| Limitation | Detail | Mitigation |
|-----------|--------|-----------|
| LLM accuracy | Complex multi-table queries with aggregations: ~85–92% first-attempt accuracy | validate_query catches syntax errors; retry loop handles most failures |
| Schema drift | If a column is renamed on IBM i, the embedded DDL in agent instructions goes stale | Refresh DDL in instructions after schema changes; or fetch live DDL via describe_sql_object |
| Hallucinated columns | LLM may invent column names that don't exist | validate_query catches this before execution |
| Slow first response | Schema reasoning + validate + execute = 3–5 LLM/tool round trips | Acceptable for analyst use cases; not for high-frequency transactional queries |
| Non-SELECT risk | LLM may attempt UPDATE/DELETE if not clearly restricted | Agent instructions + DB2 user authority (see §5) |

---

## 4. Approach 3 — Hybrid (Recommended for Production)

### How it works

Keep the **8 static tools** for the known, high-frequency business questions. Add **`validate_query` + `execute_sql`** as a fallback for questions the static tools cannot answer. The LLM decides which path to take based on the agent instructions.

### Architecture

```
User question
      │
      ▼
LLM checks: does a static tool answer this?
      │
      ├─── YES → call static tool (fast path)
      │          get_products_by_category(ELE) → 401ms → done
      │
      └─── NO  → dynamic path
                  LLM writes SQL → validate_query → execute_sql
                  "top 3 products by revenue" → custom SELECT → done
```

### Agent YAML for Hybrid approach

```yaml
spec_version: v1
kind: native

name: samco_hybrid_agent
llm: groq/openai/gpt-oss-120b
style: default

description: |
  SAMCO retail assistant with both pre-built tools for common questions
  and dynamic SQL generation for ad-hoc analysis. Queries live IBM i DB2.

instructions: |
  You are a SAMCO data expert. You have two capabilities:

  ## CAPABILITY A — Pre-built tools (use these first)
  For common questions, always prefer the pre-built tools — they are
  faster, safer, and do not require SQL generation.

  | User asks about                          | Tool to use                |
  |------------------------------------------|----------------------------|
  | A specific product code (e.g. "000001")  | get_product_by_id          |
  | Full product catalogue                   | list_all_products          |
  | What categories exist                    | list_categories            |
  | A category (Electronics, Furniture etc.) | get_products_by_category   |
  | Keyword search (wireless, coffee etc.)   | search_products            |
  | Customer profile by ID                   | get_customer               |
  | Customer order history                   | get_customer_orders        |
  | Line detail of a specific order          | get_order_detail           |

  ## CAPABILITY B — Dynamic SQL (fallback for ad-hoc questions)
  If no pre-built tool can answer the question, generate a DB2 SQL
  SELECT statement and execute it using this workflow:
    1. Write the SQL using the schema reference below
    2. Call validate_query(sql) — fix and retry if it fails (max 2 retries)
    3. Call execute_sql(sql)
    4. Format the results cleanly for the user

  ## Schema Reference (for dynamic SQL only)

  SAMCO.ARTICLE:   ARID(PK,CHAR6), ARDESC(CHAR50), ARSALEPR(DEC7.2),
                   ARWHSPR(DEC7.2), ARTIFA(CHAR3→FAMILLY), ARSTOCK(DEC5),
                   ARCUSQTY(DEC5), ARDEL(CHAR1,'X'=deleted)

  SAMCO.FAMILLY:   FAID(PK,CHAR3), FADESC(CHAR30), FADEL(CHAR1,'X'=deleted)
                   IDs: BOO CLO ELE FOO FUR GAR HOM OFF SPO TOY

  SAMCO.CUSTOMER:  CUID(PK,INT), CUSTNM(CHAR40), CUCITY(CHAR25),
                   CUCOUN(CHAR25), CULIMCRE(DEC9.2), CUCREDIT(DEC9.2),
                   CUDEL(CHAR1,'X'=deleted)

  SAMCO."ORDER":   ORID(PK,INT), ORYEAR(PK,INT), ORCUID(INT→CUSTOMER),
                   ORDATE(INT,YYYYMMDD), ORDATDEL(INT), ORDATCLO(INT)
                   ⚠ ORDER is reserved — always write SAMCO."ORDER"

  SAMCO.DETORD:    ODORID(INT→ORDER), ODYEAR(INT), ODLINE(INT),
                   ODARID(CHAR6→ARTICLE), ODQTY(DEC5), ODQTYLIV(DEC5),
                   ODPRICE(DEC7.2), ODTOT(DEC9.2), ODTOTVAT(DEC9.2)

  ## SQL Rules — always apply to dynamic queries
  - Only SELECT — never INSERT, UPDATE, DELETE, DROP, ALTER
  - Filter deleted: ARDEL <> 'X', FADEL <> 'X', CUDEL <> 'X'
  - Always FETCH FIRST N ROWS ONLY (max 100)
  - Always validate_query before execute_sql
  - Never show raw column names (ARID, ARDESC etc.) to the user

  ## Response guidelines (both capabilities)
  - Present data as clean tables or bullet lists
  - Format prices as $ with 2 decimal places
  - Translate YYYYMMDD integers to readable dates (20260115 → Jan 15, 2026)

tools:
  # Capability A — static pre-built tools
  - samco-ibmi-mcp:get_product_by_id
  - samco-ibmi-mcp:list_all_products
  - samco-ibmi-mcp:list_categories
  - samco-ibmi-mcp:get_products_by_category
  - samco-ibmi-mcp:search_products
  - samco-ibmi-mcp:get_customer
  - samco-ibmi-mcp:get_customer_orders
  - samco-ibmi-mcp:get_order_detail
  # Capability B — dynamic SQL
  - samco-ibmi-mcp:validate_query
  - samco-ibmi-mcp:execute_sql
  - samco-ibmi-mcp:describe_sql_object

collaborators: []
```

### How to deploy Approach 3

```bash
source .venv/bin/activate

# 1. Save the YAML above as agent/samco-hybrid-agent.yaml

# 2. Import (or update if samco_hybrid_agent already exists)
orchestrate agents import -f agent/samco-hybrid-agent.yaml

# 3. Verify both tool groups appear
orchestrate agents list | grep samco_hybrid
```

### Decision flow the LLM follows

```
"Show me electronics"
  → Matched by pre-built tool table → get_products_by_category(ELE) ✅ fast path

"Which customer placed the most orders in 2026?"
  → No matching pre-built tool
  → LLM writes:
      SELECT TRIM(C.CUSTNM), COUNT(O.ORID) AS ORDER_COUNT
      FROM SAMCO.CUSTOMER C
      JOIN SAMCO."ORDER" O ON O.ORCUID = C.CUID
      WHERE O.ORYEAR = 2026 AND C.CUDEL <> 'X'
      GROUP BY C.CUSTNM
      ORDER BY ORDER_COUNT DESC
      FETCH FIRST 5 ROWS ONLY
  → validate_query → execute_sql ✅ dynamic path

"What is article 000001?"
  → Matched by pre-built tool → get_product_by_id(000001) ✅ fast path

"Show me all products with stock below their minimum stock level"
  → No pre-built tool covers this
  → LLM writes:
      SELECT TRIM(A.ARDESC), A.ARSTOCK, A.ARMINQTY,
             (A.ARMINQTY - A.ARSTOCK) AS SHORTFALL
      FROM SAMCO.ARTICLE A
      WHERE A.ARSTOCK < A.ARMINQTY AND A.ARDEL <> 'X'
      ORDER BY SHORTFALL DESC
      FETCH FIRST 50 ROWS ONLY
  → validate_query → execute_sql ✅ dynamic path
```

---

## 5. Security Model for Dynamic SQL on IBM i

This section is **mandatory reading** before enabling Approach 2 or 3 in production.

### Threat model

```
Threat 1 — SQL Injection via user input
  User: "Show products where id = '1'; DELETE FROM SAMCO.ARTICLE --"
  Risk: Data loss

Threat 2 — LLM generates destructive SQL
  LLM misinterprets: "clear the test orders" → DELETE FROM SAMCO."ORDER"
  Risk: Data loss

Threat 3 — Schema enumeration
  User: "List all tables in all schemas"
  Risk: Sensitive schema/data exposure

Threat 4 — Privilege escalation
  LLM uses GRANT or ALTER SYSTEM commands
  Risk: Security bypass
```

### Three mandatory guards — implement all three

#### Guard 1 — SELECT-only enforcement at agent level

The agent instructions must explicitly state:
```
Only write SELECT statements.
Never write INSERT, UPDATE, DELETE, DROP, ALTER, GRANT, REVOKE, CALL, EXECUTE.
```

This is the first line of defence — the LLM will refuse to generate non-SELECT SQL.

#### Guard 2 — `validate_query` before every `execute_sql`

`validate_query` uses IBM i's `PARSE_STATEMENT` internally + cross-references `SYSTABLES` and `SYSCOLUMNS`. It will:
- Reject syntax errors
- Reject references to tables/columns that don't exist
- Reject statements that are not valid SELECT

Always enforce this in the agent workflow:
```
validate_query(sql) → only if VALID → execute_sql(sql)
                    → if INVALID    → do NOT execute, report error
```

#### Guard 3 — IBM i DB2 user authority (most important)

This is the last line of defence — enforced at the OS level regardless of what SQL the LLM generates.

```
# On IBM i — restrict <ibmi-user> to read-only on SAMCO
GRTOBJAUT OBJ(SAMCO/ARTICLE)   OBJTYPE(*FILE) USER(CECUSER) AUT(*USE)
GRTOBJAUT OBJ(SAMCO/FAMILLY)   OBJTYPE(*FILE) USER(CECUSER) AUT(*USE)
GRTOBJAUT OBJ(SAMCO/CUSTOMER)  OBJTYPE(*FILE) USER(CECUSER) AUT(*USE)
GRTOBJAUT OBJ(SAMCO/ORDER)     OBJTYPE(*FILE) USER(CECUSER) AUT(*USE)
GRTOBJAUT OBJ(SAMCO/DETORD)    OBJTYPE(*FILE) USER(CECUSER) AUT(*USE)

# Verify
DSPOBJAUT OBJ(SAMCO/ARTICLE) OBJTYPE(*FILE)
# CECUSER should show *USE only — not *CHANGE or *ALL
```

With `*USE` authority, even if a DELETE statement somehow reaches DB2, the database will reject it with `SQL0551 — Not authorized to object`.

### Additional hardening for production

```yaml
# In .env on IBM i — add query restrictions
MCP_SQL_ALLOW_SCHEMA=SAMCO        # only allow queries against SAMCO schema
MCP_SQL_MAX_ROWS=100              # hard cap on rows returned
MCP_SQL_TIMEOUT_MS=10000          # 10-second query timeout
MCP_RATE_LIMIT_ENABLED=true
MCP_RATE_LIMIT_REQUESTS=30        # max 30 tool calls per minute per session
MCP_AUTH_MODE=bearer              # require bearer token (not 'none')
```

### Security checklist

- [ ] Agent instructions explicitly forbid non-SELECT statements
- [ ] `validate_query` is called before every `execute_sql` in agent workflow
- [ ] DB2 user (`<ibmi-user>`) has `*USE` authority only on SAMCO tables
- [ ] `MCP_AUTH_MODE=bearer` with rotated token (not `none`)
- [ ] `MCP_SQL_ALLOW_SCHEMA=SAMCO` to block queries against system tables
- [ ] `MCP_RATE_LIMIT_ENABLED=true` to prevent abuse
- [ ] All executed SQL logged to IBM i journal (QAUDJRN) for audit trail

---

## 6. Feasibility Comparison Matrix

| Factor | Approach 1 — Static | Approach 2 — Dynamic | Approach 3 — Hybrid |
|--------|--------------------|--------------------|---------------------|
| **Query accuracy** | ✅ 100% — SQL is authored | ⚠️ 85–95% first attempt | ✅ 100% for static path, 85–95% for dynamic |
| **Question coverage** | ⚠️ Only predefined questions | ✅ Any SELECT the schema supports | ✅ Predefined + ad-hoc |
| **Security** | ✅ No injection risk | ⚠️ Requires all 3 guards | ✅ Guards apply only to dynamic path |
| **Response speed** | ✅ Fast — 1 tool call | ⚠️ Slower — 3–5 round trips | ✅ Fast for static, acceptable for dynamic |
| **Setup complexity** | ✅ Low — YAML authoring | ⚠️ Medium — schema embedding | ⚠️ Medium |
| **Maintenance** | ⚠️ Update YAML on schema change | ⚠️ Update instructions on schema change | ⚠️ Both, but less YAML needed |
| **IBM i risk** | ✅ Zero — read-only, pre-audited | ⚠️ Moderate — mitigated by guards | ✅ Low — static is safe, dynamic is guarded |
| **Debuggability** | ✅ SQL visible in YAML | ⚠️ SQL generated fresh each time | ✅ Easy for static path |
| **LLM cost** | ✅ Low — just tool selection | ⚠️ Higher — SQL generation reasoning | ✅ Low for static, higher for dynamic |
| **Compliance** | ✅ Every query pre-approved | ⚠️ Queries not pre-approved | ⚠️ Static queries pre-approved, dynamic not |
| **Recommended for** | Production transactional | Internal analyst tools | Production + analytics |

---

## 7. Migration Path — Phase 1 → Phase 2 → Phase 3

### Phase 1 — Static only (current state ✅)

```
Status: DONE
Agent:  samco_retail_agent
Tools:  8 static tools in retail-services.yaml
Covers: all predefined SAMCO retail queries
```

No changes needed. Already running and verified.

### Phase 2 — Add dynamic SQL to current agent

```
Target: samco_retail_agent gets execute_sql + validate_query
Effort: ~2 hours
Risk:   Low — guards are in place

Steps:
  1. Confirm execute_sql and validate_query appear in:
       orchestrate tools list | grep samco-ibmi
     (If not, they need to be enabled in the MCP server config on IBM i)

  2. Update agent/samco-retail-agent.yaml — add:
       tools:
         ...existing 8 tools...
         - samco-ibmi-mcp:validate_query
         - samco-ibmi-mcp:execute_sql
         - samco-ibmi-mcp:describe_sql_object

  3. Add schema reference and SQL rules to agent instructions

  4. Re-import:
       orchestrate agents import -f agent/samco-retail-agent.yaml

  5. Apply IBM i authority restrictions:
       GRTOBJAUT OBJ(SAMCO/*ALL) OBJTYPE(*FILE) USER(CECUSER) AUT(*USE)

  6. Test with ad-hoc queries
```

### Phase 3 — Separate agents for separate audiences

```
Target: Two agents — one for business users, one for analysts
Effort: ~4 hours
Risk:   Low

  samco_retail_agent  ← business users, static tools only, no dynamic SQL
  samco_analyst_agent ← internal analysts, dynamic SQL + all safety guards

Both use the same samco-ibmi-mcp toolkit and the same IBM i backend.
```

---

## 8. Verified Live Evidence

The following data was returned by a live DB2 query through the full stack (user → Orchestrate → ngrok → IBM i → DB2) during the verified demo run:

### Test executed: `get_products_by_category("ELE")`

```json
{
  "success": true,
  "data": [
    { "ARTICLE_ID": "000004", "PRODUCT_NAME": "Bluetooth Headphones",  "SALE_PRICE": 79.99,  "STOCK_LEVEL": 80  },
    { "ARTICLE_ID": "000001", "PRODUCT_NAME": "Laptop Computer 15 inch","SALE_PRICE": 899.99, "STOCK_LEVEL": 25  },
    { "ARTICLE_ID": "000005", "PRODUCT_NAME": "Smartphone 128GB",      "SALE_PRICE": 599.99, "STOCK_LEVEL": 40  },
    { "ARTICLE_ID": "000003", "PRODUCT_NAME": "USB-C Cable 2m",        "SALE_PRICE": 12.99,  "STOCK_LEVEL": 200 },
    { "ARTICLE_ID": "000002", "PRODUCT_NAME": "Wireless Mouse",        "SALE_PRICE": 29.99,  "STOCK_LEVEL": 150 }
  ],
  "metadata": {
    "executionTime": 401,
    "rowCount": 5,
    "toolName": "get_products_by_category",
    "sqlStatement": "SELECT A.ARID AS ARTICLE_ID, TRIM(A.ARDESC) AS PRODUCT_NAME,\nA.ARSALEPR AS SALE_PRICE, A.ARSTOCK AS STOCK_LEVEL\nFROM SAMCO.ARTICLE A\nWHERE A.ARTIFA = :category_id AND A.ARDEL <> 'X'\nORDER BY A.ARDESC FETCH FIRST 50 ROWS ONLY",
    "parameters": { "category_id": "ELE" }
  }
}
```

**Query latency: 401ms** end-to-end including ngrok tunnel overhead.

### Live DDL introspection: `describe_sql_object("ARTICLE", "SAMCO")`

The MCP server successfully returned the full `CREATE TABLE` DDL for `SAMCO.ARTICLE` including all 14 columns with their CCSID, types, and IBM i column labels. This confirms `describe_sql_object` works live — which is the foundation of the dynamic SQL schema-discovery pattern in Approaches 2 and 3.

---

*This document covers design decisions grounded in a working implementation. All SQL statements shown for Approaches 2 and 3 were written based on the real SAMCO schema DDL returned live from the IBM i system.*
