#!/usr/bin/env node
// floatingmacro-mcp — MCP stdio server for FloatingMacro.
//
// Reads JSON-RPC envelopes from stdin (one per line), proxies tool calls to
// FloatingMacro's local HTTP API at http://127.0.0.1:<port>, writes JSONL
// responses to stdout. No state. No keychain access. Multiple instances can
// run in parallel — they all hit the same single FloatingMacro app.
//
// Hard contract:
//   1. JSONL framing (one JSON-RPC envelope per line). No Content-Length.
//   2. stdout is the protocol channel — never log/print to it.
//   3. stderr is for diagnostics only.
//   4. We do NOT launch the FloatingMacro app. If it is not reachable,
//      tool calls return JSON-RPC errors (-32000).
//   5. Notifications (no `id`) get no response.

import readline from 'node:readline';
import process from 'node:process';

// ─── argv / env ───────────────────────────────────────────────────────
let port = 17430;
let token = process.env.FLOATINGMACRO_TOKEN || '';
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--port' && i + 1 < argv.length) {
        port = parseInt(argv[++i], 10);
    } else if (a === '--token' && i + 1 < argv.length) {
        token = argv[++i];
    } else if (a === '--help' || a === '-h') {
        printUsage();
        process.exit(0);
    } else if (a === '--version') {
        console.log('floatingmacro-mcp 0.1.0');
        process.exit(0);
    }
}

function printUsage() {
    process.stderr.write([
        'floatingmacro-mcp — MCP stdio server for FloatingMacro',
        '',
        'Usage: floatingmacro-mcp [options]',
        '',
        'Options:',
        '  --port N       FloatingMacro HTTP API port (default: 17430)',
        '  --token TOKEN  Bearer token for tool calls (or set FLOATINGMACRO_TOKEN env)',
        '  --help, -h     Show this help',
        '  --version      Show version',
        '',
        'The bearer token is required for /tools/call. If not provided via',
        '--token or FLOATINGMACRO_TOKEN, tool calls will fail with HTTP 401.',
        '',
        'See https://github.com/veltrea/floatingmacro for full documentation.',
        '',
    ].join('\n'));
}

const baseURL = `http://127.0.0.1:${port}`;

// ─── HTTP helpers ─────────────────────────────────────────────────────

async function fetchManifest() {
    const res = await fetch(`${baseURL}/manifest`);
    if (!res.ok) throw new Error(`manifest HTTP ${res.status}`);
    return await res.json();
}

async function callRemoteTool(name, args) {
    const headers = { 'Content-Type': 'application/json' };
    if (token) headers['Authorization'] = `Bearer ${token}`;
    const res = await fetch(`${baseURL}/tools/call`, {
        method: 'POST',
        headers,
        body: JSON.stringify({ name, arguments: args || {} }),
    });
    const body = await res.text();
    if (!res.ok) {
        const err = new Error(`tool ${name} failed: HTTP ${res.status}`);
        err.code = -32000;
        err.data = body;
        throw err;
    }
    try {
        return JSON.parse(body);
    } catch {
        return { ok: true };
    }
}

// ─── JSON-RPC dispatch ────────────────────────────────────────────────

function writeResponse(obj) {
    process.stdout.write(JSON.stringify(obj) + '\n');
}

function rpcError(id, code, message, data) {
    const err = { code, message };
    if (data !== undefined) err.data = data;
    return { jsonrpc: '2.0', id, error: err };
}

function rpcResult(id, result) {
    return { jsonrpc: '2.0', id, result };
}

async function handleRequest(req) {
    // Notifications carry no id and get no response.
    if (req.id === undefined || req.id === null) return null;

    const { id, method, params = {} } = req;

    try {
        switch (method) {
            case 'initialize': {
                let manifest;
                try {
                    manifest = await fetchManifest();
                } catch (e) {
                    return rpcError(id, -32000,
                        'FloatingMacro app not reachable',
                        `${e.message}. Is the FloatingMacro app running on ${baseURL}?`);
                }
                return rpcResult(id, {
                    protocolVersion: manifest.protocolVersion || '2024-11-05',
                    serverInfo: manifest.serverInfo || { name: 'FloatingMacro', version: '0.1' },
                    capabilities: manifest.capabilities || { tools: {} },
                    instructions: manifest.instructions || manifest.systemPrompt || '',
                });
            }

            case 'ping':
                return rpcResult(id, {});

            case 'tools/list': {
                let manifest;
                try {
                    manifest = await fetchManifest();
                } catch (e) {
                    return rpcError(id, -32000,
                        'FloatingMacro app not reachable',
                        `${e.message}. Is the FloatingMacro app running on ${baseURL}?`);
                }
                return rpcResult(id, { tools: manifest.tools || [] });
            }

            case 'tools/call': {
                const name = params.name;
                const args = params.arguments || {};
                if (!name) {
                    return rpcError(id, -32602, 'tools/call requires `name`');
                }
                try {
                    const result = await callRemoteTool(name, args);
                    return rpcResult(id, {
                        content: [{ type: 'text', text: JSON.stringify(result) }],
                        isError: false,
                    });
                } catch (e) {
                    if (e.code === -32000) {
                        return rpcError(id, -32000, e.message, e.data);
                    }
                    return rpcError(id, -32000,
                        'FloatingMacro app not reachable',
                        `${e.message}. Is the FloatingMacro app running on ${baseURL}?`);
                }
            }

            default:
                return rpcError(id, -32601, `Method not found: ${method}`);
        }
    } catch (e) {
        return rpcError(id, -32603, `Internal error: ${e.message}`);
    }
}

// ─── stdin loop ───────────────────────────────────────────────────────
//
// IMPORTANT: we must NOT exit on `close` while async fetches are still in
// flight. Each line spawns an async handler that may take milliseconds to
// hit the local HTTP API. Track them and only exit when:
//   - stdin has closed (no more requests coming), AND
//   - every pending handler has settled.

const rl = readline.createInterface({ input: process.stdin, terminal: false });

let pending = 0;
let closed = false;

function maybeExit() {
    if (closed && pending === 0) process.exit(0);
}

rl.on('line', (line) => {
    const trimmed = line.trim();
    if (!trimmed) return;
    let req;
    try {
        req = JSON.parse(trimmed);
    } catch {
        writeResponse(rpcError(null, -32700, 'Parse error'));
        return;
    }
    pending++;
    handleRequest(req)
        .then((response) => {
            if (response !== null) writeResponse(response);
        })
        .catch((e) => {
            writeResponse(rpcError(req?.id ?? null, -32603,
                `Internal error: ${e?.message ?? String(e)}`));
        })
        .finally(() => {
            pending--;
            maybeExit();
        });
});

rl.on('close', () => {
    closed = true;
    maybeExit();
});

process.on('SIGINT', () => process.exit(0));
process.on('SIGTERM', () => process.exit(0));
