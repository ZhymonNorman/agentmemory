# Agentmemory Railway Template

Self-hosted persistent memory for AI agents on Railway.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/agentmemory-self-hosted-memory-for-ai-ag?referralCode=1q5cCO&utm_medium=integration&utm_source=template&utm_campaign=generic)

## What is this?

This repository contains a Railway-ready setup for running Agentmemory as a remote memory server for AI coding agents.

It exposes the Agentmemory REST API, stores persistent data on a Railway volume, and can be connected to MCP-compatible tools such as OpenAI Codex CLI, Claude Code, Cursor, Cline, and other agents.

## Railway Template

Deploy it here:

https://railway.com/deploy/agentmemory-self-hosted-memory-for-ai-ag

## Default Setup

- REST API exposed on Railway public networking
- Persistent storage mounted at `/data`
- API protected with `AGENTMEMORY_SECRET`
- Optional viewer support behind a protected proxy
- No LLM provider required by default

## Recommended Variables

```env
NODE_ENV="production"
III_DATA_DIR="/data"
AGENTMEMORY_URL="https://${{RAILWAY_PUBLIC_DOMAIN}}"
AGENTMEMORY_SECRET="${{secret(32)}}"
AGENTMEMORY_DATA_DIR="/data"
AGENTMEMORY_REQUIRE_HTTPS="1"
```

### Ports

agentmemory runs on its canonical port quartet, all derived from the
REST anchor: streams = REST+1, viewer = REST+2, and the iii-engine
bridge = REST+46023.

| Port | Purpose | Exposure |
|---|---|---|
| `3111` | REST API | Railway service domain — **set the domain's target port to 3111** |
| `3112` | Streams | internal |
| `3113` | Viewer (binds `127.0.0.1`) | republished by socat on `8083` |
| `49134` | iii-engine bridge (WebSocket) | container-local only |

Do **not** set `PORT` and re-anchor the REST API onto it. The engine
binary always binds its bridge on the fixed default `49134`, so a REST
anchor of `8080` makes the worker dial `ws://localhost:54103`, where
nothing listens. The worker then never registers its functions and
every `/agentmemory/*` route returns `404` even though the container
looks healthy.

## Test the API

```bash
curl -i \
  -H "Authorization: Bearer $AGENTMEMORY_SECRET" \
  "$AGENTMEMORY_URL/agentmemory/health"
```

A healthy deployment should return HTTP `200`.

## Use with Codex

Install the MCP shim:

```bash
npm install -g @agentmemory/mcp
```

Add this to `~/.codex/config.toml`:

```toml
[mcp_servers.agentmemory]
command = "/opt/homebrew/bin/agentmemory-mcp"
args = []
enabled = true
startup_timeout_sec = 60
tool_timeout_sec = 120

[mcp_servers.agentmemory.env]
AGENTMEMORY_URL = "https://your-railway-domain.up.railway.app"
AGENTMEMORY_SECRET = "your-secret"
AGENTMEMORY_FORCE_PROXY = "1"
AGENTMEMORY_DEBUG = "1"
```

Then run `/mcp` inside Codex and check that `agentmemory` is listed.
