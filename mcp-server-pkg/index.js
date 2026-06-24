#!/usr/bin/env node
// Entry point — delegates directly to the installed ibmi-mcp-server binary
// with the SAMCO retail tools YAML and stdio transport for Orchestrate.
const { execFileSync } = require('child_process');
const path = require('path');

const serverBin = path.join(__dirname, 'node_modules', '@ibm', 'ibmi-mcp-server', 'dist', 'index.js');
const toolsYaml = path.join(__dirname, 'payments-services.yaml');

// Forward all process streams so MCP stdio protocol works correctly
require(serverBin);
