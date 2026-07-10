---
layout: layout.njk
title: 03 — Software
permalink: /03-software/index.html
---

# 03 — Software: Agents, Models & MCP Servers

The `tekt.iris` layer — the intelligence that runs the system — plus the MCP server fabric that gives every agent the same set of local tools. Things you may have used on tekt.cloud happen **here**, on your own `tekt.dev` / `tekt.edge` instance, with your keys, on your hardware.

Everything below is installed by `bash install.sh` (each step is resilient — one failure never kills the run). Per-tool manual commands follow for read-and-paste learners.

---

## Local models

### Ollama

Run open-weight models locally — the sovereignty baseline. Every claw-family agent below can point at Ollama instead of a hosted API.

```bash
# Linux
curl -fsSL https://ollama.com/install.sh | sh
# macOS
brew install ollama            # or the app from ollama.com/download
# Windows
winget install --id Ollama.Ollama -e
```

First model and verify:

```bash
ollama pull llama3.2           # or qwen3, gemma3, deepseek-r1 …
ollama run llama3.2 "hello"
ollama serve                   # OpenAI-compatible API on :11434 (usually auto-started)
```

Upstream: Ollama (MIT). Docs: [ollama.com](https://ollama.com)

---

## The claw family & friends

Seven agent runtimes, one shared philosophy: your machine, your keys, your workspace. Pick per archetype — you don't need all of them on one box (the full install puts them there so you can compare).

### Claude Code — Anthropic

```bash
curl -fsSL https://claude.ai/install.sh | bash     # native installer (recommended)
# Windows PowerShell:  irm https://claude.ai/install.ps1 | iex
claude                                             # browser auth on first run
claude doctor
```

Docs: [code.claude.com](https://code.claude.com/docs/en/setup) · Repo: [anthropics/claude-code](https://github.com/anthropics/claude-code)

### OpenClaw — the full workspace runtime

Node.js 24 required.

```bash
curl -fsSL https://openclaw.ai/install.sh | bash   # or: npm install -g openclaw@latest
openclaw onboard --install-daemon
openclaw dashboard
```

Docs: [docs.openclaw.ai](https://docs.openclaw.ai) · Repo: [openclaw/openclaw](https://github.com/openclaw/openclaw)

### PicoClaw — Go, single binary, $10 hardware

```bash
curl -L https://github.com/sipeed/picoclaw/releases/latest/download/picoclaw-linux-amd64 -o picoclaw
chmod +x picoclaw && sudo mv picoclaw /usr/local/bin/
picoclaw onboard && picoclaw agent
```

Upstream: Sipeed. Repo: [sipeed/picoclaw](https://github.com/sipeed/picoclaw)

### Hermes Agent — Nous Research, self-improving

Linux / macOS / WSL2 / Termux. **No native Windows.**

```bash
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
hermes setup && hermes
```

Repo: [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent)

### ZeroClaw — Rust, <5MB RAM, ~10ms cold start

The edge-node workhorse: single static binary, 20+ providers (including local Ollama), 15+ channels, supervised autonomy by default, one-command migration from OpenClaw.

```bash
curl -fsSL https://raw.githubusercontent.com/zeroclaw-labs/zeroclaw/master/install.sh | bash
# or: brew install zeroclaw
# or from source: git clone https://github.com/zeroclaw-labs/zeroclaw && cd zeroclaw && cargo install --path . --locked
zeroclaw quickstart                 # pick a provider, write a working config
zeroclaw agent                      # interactive chat
zeroclaw service install && zeroclaw service start   # always-on daemon
zeroclaw migrate openclaw --dry-run # coming from OpenClaw? preview the migration
```

Upstream: zeroclaw-labs contributors. Repo: [zeroclaw-labs/zeroclaw](https://github.com/zeroclaw-labs/zeroclaw)

### Nanobot — HKUDS, ultra-light Python agent

Small readable core with WebUI, channels, MCP support, cron, and memory. Python 3.11+.

```bash
pip install nanobot-ai              # or: uv tool install nanobot-ai
nanobot onboard                     # creates ~/.nanobot config + workspace
nanobot agent
```

Point it at Ollama or any OpenAI-compatible endpoint in `~/.nanobot/config.json`.

> **Naming note:** there is a *different* project called Nanobot — [nanobot-ai/nanobot](https://github.com/nanobot-ai/nanobot), a Go MCP **host** for building MCP/MCP-UI agents. Tekt ships the HKUDS agent; if you want the MCP host instead, it's a fine complement to MCPHub.

Upstream: HKUDS — Xubin Ren & contributors (MIT). Repo: [HKUDS/nanobot](https://github.com/HKUDS/nanobot)

### NanoClaw — container-isolated, Claude-Code-native

Agents run in real Linux containers (Docker, or Apple Container on macOS); the codebase is small enough to read, and setup/customization happen *through* Claude Code. Requires Node 20+, a container runtime, and Claude Code.

```bash
git clone https://github.com/qwibitai/nanoclaw.git ~/Tekt/Instances/$(hostname -s)/agents/nanoclaw
cd ~/Tekt/Instances/$(hostname -s)/agents/nanoclaw
claude          # then run /setup inside the Claude session
```

The bootstrap clones this for you and prints the same instruction — the `/setup` flow is interactive by design.

Upstream: qwibitai (MIT). Repo: [qwibitai/nanoclaw](https://github.com/qwibitai/nanoclaw)

---

## MCP servers — one hub, four locals, HTTPS out

Instead of wiring MCP servers into each agent and UI separately, Tekt runs **MCPHub** ([samanhappy/mcphub](https://github.com/samanhappy/mcphub), Apache-2.0) as the single aggregation point. Every client — LibreChat, n8n, Claude Code, OpenClaw, ZeroClaw — connects to one Streamable HTTP endpoint and sees every tool.

### The curated four

Defined in `~/Tekt/Instances/<hostname>/mcp/mcp_settings.json` (created by `bash install.sh` and listed in `tekt.catalog.yaml`). All four run **locally inside the hub**, operating on your machine's Tekt workspace:

| Server | Package | What it gives your agents |
| --- | --- | --- |
| `filesystem` | `@modelcontextprotocol/server-filesystem` | Read/write the instance workspace |
| `fetch` | `mcp-server-fetch` (uvx) | Fetch and convert web content |
| `memory` | `@modelcontextprotocol/server-memory` | Persistent knowledge-graph memory |
| `github` | `@modelcontextprotocol/server-github` | Repos, issues, PRs (needs a PAT) |

Four is the starting count, not a limit — add or swap servers by editing `mcp_settings.json` (or the dashboard); MCPHub hot-reloads without downtime.

### Bring it up

```bash
bash install.sh mcp
```

This scaffolds and starts, equivalent to:

```bash
mkdir -p ~/Tekt/Instances/$(hostname -s)/{mcp,workspace}
cd ~/Tekt/Instances/$(hostname -s)/mcp

cat > mcp_settings.json <<'EOF'
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/workspace"]
    },
    "fetch": {
      "command": "uvx",
      "args": ["mcp-server-fetch"]
    },
    "memory": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-memory"]
    },
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": { "GITHUB_PERSONAL_ACCESS_TOKEN": "set-me" }
    }
  }
}
EOF

cat > docker-compose.yml <<'EOF'
services:
  mcphub:
    image: samanhappy/mcphub:latest
    ports: ["3000:3000"]
    volumes:
      - ./mcp_settings.json:/app/mcp_settings.json
      - ../workspace:/workspace
    restart: unless-stopped
EOF

docker compose up -d
```

Dashboard: `http://localhost:3000` (default `admin` / `admin123` — **change it immediately**). Endpoints your clients will use:

```
http://<host>:3000/mcp              # all servers, one endpoint
http://<host>:3000/mcp/{group}      # a named group
http://<host>:3000/mcp/{server}     # a single server
http://<host>:3000/mcp/$smart       # semantic tool routing (needs Postgres/pgvector)
```

> The hub runs the servers in a container, so "the local machine" = whatever you mount. `../workspace` is mounted by default; add more volumes (e.g. `~/Projects:/projects`) and extend the filesystem server's args to match. MCP endpoints require bearer authentication by default — keep it on for anything shared.

### HTTPS in one command

```bash
bash install.sh share 3000
# → tailscale serve --bg 3000   (if your tailnet is up: private HTTPS URL)
# → ngrok http 3000             (fallback: public HTTPS URL)
```

---

## Sovrant — post-install command center

Sovrant (Anant Corporation, [ramseur/sovrant](https://github.com/ramseur/sovrant)) is a command center for agents and agent activity built on **.NET 10 / C# 14**. It connects to Claws — PicoClaw, Hermes, OpenClaw — via MCP, letting you observe and steer them from one cockpit, and runs as a CLI, an OpenAI-compatible server, a desktop app, a web app, or an MCP server.

**License disclosure:** Sovrant is **BSL 1.1** — source-available, *not* OSI open source; it converts to Apache-2.0 on **2029-05-15**. We label this plainly because honest licensing is a Tekt principle.

### Install

The bootstrap does this for you: it installs the **.NET 10 SDK** (Homebrew cask on macOS, Microsoft's user-local `dotnet-install.sh` on Linux, `winget Microsoft.DotNet.SDK.10` on Windows), clones Sovrant into `~/Tekt/Instances/<host>/sovrant`, and runs `dotnet restore && dotnet build`. Manually:

```bash
git clone https://github.com/ramseur/sovrant.git ~/Tekt/Instances/$(hostname)/sovrant
cd ~/Tekt/Instances/$(hostname)/sovrant
dotnet restore && dotnet build
```

### Run

```bash
# Desktop app (recommended first run — setup wizard for provider/API key)
dotnet run --project src/Sovrant.Desktop &

# Web app — http://localhost:5100
dotnet run --project src/Sovrant.Web

# OpenAI-compatible server — http://localhost:5200 (first registered user becomes admin)
dotnet run --project src/Sovrant.Server

# CLI (stores API keys in an encrypted on-disk credential store)
dotnet run --project src/Sovrant.Cli -- auth set llm
dotnet run --project src/Sovrant.Cli -- --model gpt-4o-mini
```

On Windows, launch the desktop app without a console window: `Start-Process dotnet -ArgumentList "run --project src/Sovrant.Desktop" -WindowStyle Hidden`. Sovrant supports Ollama and LM Studio as providers, so it pairs naturally with the local Ollama install above — AI spend toward zero is one of its stated tenets.

### Sovrant as an MCP server

Sovrant exposes its tools over MCP in two transports:

```bash
# stdio — for IDE embedding (VS Code, Cursor, Claude Code)
dotnet run --project src/Sovrant.Cli -- mcp-server

# HTTP/SSE — reuses the server's bearer-token auth
SOVRANT_MCP_HTTP=true dotnet run --project src/Sovrant.Server
# → MCP endpoint at http://localhost:5200/mcp
```

The HTTP endpoint means you can register Sovrant as a **fifth server in MCPHub** alongside the curated four — add an entry pointing at `http://host.docker.internal:5200/mcp` in `mcp_settings.json` (with the bearer token from your Sovrant registration) and both LibreChat and n8n gain Sovrant's tools through the hub. Share it over HTTPS the usual way: `bash install.sh share 5200`.

---

## Verify the layer

```bash
bash install.sh status      # agents + models rows, plus MCPHub container check
curl -s http://localhost:3000/api/health 2>/dev/null || docker ps | grep mcphub
```

Next: [04 — Interface](/04-interface/) to bring up LibreChat and n8n and connect them to the hub.
