---
layout: layout.njk
title: 04 — Interface
permalink: /04-interface/index.html
---

# 04 — Interface: UIs, Proxies & Sharing from Your Home Lab

The `tekt.cloud` layer running on *your* hardware: LibreChat for multi-model chat, n8n for workflow automation, both wired to your local MCPHub — then safely shared with the people you choose via Tailscale or ngrok.

Quick path: `bash install.sh mcp` (from [03 — Software](/03-software/)) then `bash install.sh ui`, then `bash install.sh share`.

---

## 1. LibreChat — multi-model chat UI

Upstream: Danny Avila & contributors (MIT). Repo: [danny-avila/LibreChat](https://github.com/danny-avila/LibreChat). The official compose stack bundles its own MongoDB, Meilisearch, and RAG API.

### Bring it up

```bash
# install.sh ui does this for you — manual equivalent:
git clone https://github.com/danny-avila/LibreChat.git \
  ~/Tekt/Instances/$(hostname -s)/cloud/librechat
cd ~/Tekt/Instances/$(hostname -s)/cloud/librechat
cp .env.example .env               # add your API keys here (or none — see Ollama below)
docker compose up -d
```

UI at `http://localhost:3080`. Create the first (admin) account in the browser.

### Connect LibreChat → MCPHub

LibreChat reads MCP servers from `librechat.yaml`. Create it in the LibreChat directory:

```yaml
version: 1.2.1
mcpServers:
  tekt:
    type: streamable-http
    url: http://host.docker.internal:3000/mcp
    # If you enabled bearer auth in MCPHub (recommended):
    # headers:
    #   Authorization: "Bearer ${MCPHUB_BEARER_TOKEN}"
```

Mount it with a `docker-compose.override.yml`:

```yaml
services:
  api:
    volumes:
      - ./librechat.yaml:/app/librechat.yaml
    extra_hosts:
      - "host.docker.internal:host-gateway"   # Linux needs this; Docker Desktop has it built in
```

Then `docker compose up -d --force-recreate api`. Your agents in LibreChat now see every tool the hub aggregates — filesystem, fetch, memory, github, and anything you add later.

### Point LibreChat at local models

In `librechat.yaml`, add Ollama as a custom endpoint:

```yaml
endpoints:
  custom:
    - name: Ollama
      apiKey: ollama
      baseURL: http://host.docker.internal:11434/v1
      models:
        default: ["llama3.2"]
        fetch: true
```

Fully sovereign chat: local UI, local models, local tools.

## 2. n8n — workflow automation

Upstream: n8n GmbH. **License note:** n8n is *fair-code* under the Sustainable Use License — free to self-host and modify, but not OSI open source. Repo: [n8n-io/n8n](https://github.com/n8n-io/n8n).

### Bring it up

```bash
mkdir -p ~/Tekt/Instances/$(hostname -s)/cloud/n8n && cd $_
cat > docker-compose.yml <<'EOF'
services:
  n8n:
    image: docker.n8n.io/n8nio/n8n:latest
    ports: ["5678:5678"]
    environment:
      - GENERIC_TIMEZONE=America/New_York
      - N8N_SECURE_COOKIE=false        # remove once behind HTTPS
    volumes:
      - n8n_data:/home/node/.n8n
    extra_hosts:
      - "host.docker.internal:host-gateway"
    restart: unless-stopped
volumes:
  n8n_data:
EOF
docker compose up -d
```

UI at `http://localhost:5678` — create the owner account on first visit. (`install.sh ui` scaffolds and starts this too.)

### Connect n8n → MCPHub

In the n8n editor:

1. Add an **AI Agent** node (choose your chat model — an Ollama or Anthropic credential)
2. Under **Tools**, add the **MCP Client Tool** node
3. Endpoint: `http://host.docker.internal:3000/mcp` (transport: HTTP Streamable)
4. If MCPHub bearer auth is on, add a Header Auth credential: `Authorization: Bearer <token>`

n8n can also *be* an MCP server (the **MCP Server Trigger** node) — expose a workflow as a tool, register its URL in MCPHub's dashboard, and every other client instantly gets it. That loop — UI → hub → workflow → hub → UI — is the heart of the tekt.cloud layer.

## 3. MCPHub dashboard

`http://localhost:3000` — manage servers, groups, users, and keys. First moves:

1. Change `admin` / `admin123`
2. Create a bearer key for LibreChat and one for n8n (per-client keys make revocation painless)
3. Group servers if you want scoped endpoints (e.g. a `safe` group without filesystem write)

## 4. Reverse proxy (optional): one hostname for everything

If you'd rather serve `chat.`, `flows.`, and `mcp.` paths from one port, put nginx in front (pattern adapted from [hubertusgbecker/chatsuite](https://github.com/hubertusgbecker/chatsuite)):

```bash
mkdir -p ~/Tekt/Instances/$(hostname -s)/cloud/proxy && cd $_
cat > nginx.conf <<'EOF'
events {}
http {
  server {
    listen 8080;
    location /chat/  { proxy_pass http://host.docker.internal:3080/; }
    location /flows/ { proxy_pass http://host.docker.internal:5678/; proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade"; }
    location /mcp/   { proxy_pass http://host.docker.internal:3000/mcp/; proxy_buffering off; }
  }
}
EOF
cat > docker-compose.yml <<'EOF'
services:
  proxy:
    image: nginx:alpine
    ports: ["8080:8080"]
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    extra_hosts:
      - "host.docker.internal:host-gateway"
    restart: unless-stopped
EOF
docker compose up -d
```

Now `tailscale serve --bg 8080` shares the whole suite over one HTTPS URL. (Note: some apps prefer subdomains over subpaths — n8n works best with `N8N_PATH=/flows/` set, or skip the proxy and share ports individually.)

## 5. Sharing from your home lab

Three tiers, in order of preference:

| Tier | Command | Who can reach it |
| --- | --- | --- |
| **Tailnet (private)** | `tailscale serve --bg 3080` | Your devices + people you invite to your tailnet |
| **Funnel (public via Tailscale)** | `tailscale funnel --bg 3080` | Anyone with the URL (HTTPS, Tailscale-terminated) |
| **ngrok (public, ephemeral)** | `ngrok http 3080` | Anyone with the URL, until you Ctrl-C |

Or just: `bash install.sh share <port>` — Tailscale Serve if your tailnet is up, ngrok otherwise.

**Before you share anything:**

- Change every default credential (MCPHub `admin/admin123`, MinIO root, n8n owner is yours already)
- Keep MCPHub bearer auth ON — a filesystem MCP server behind an open endpoint is remote code execution by invitation
- Prefer the tailnet tier; use Funnel/ngrok for demos, then tear them down
- Registration: LibreChat's `.env` lets you disable open signups (`ALLOW_REGISTRATION=false`) once your users are in

## 6. Sovrant UX contract (Claude-like ergonomics, current palette)

Target direction: preserve Sovrant's current color scheme while adopting Claude-style interaction ergonomics.

### Onboarding/login behavior

- If no admin exists yet, show conditional copy: **“First registered account will become admin.”**
- If an admin already exists, do **not** show that message.
- During signup/login provisioning, show a clear progress state (spinner + “Setting up your workspace…” label).

### UI structure goals

- Left navigation: compact, always-visible conversation/workspace rail.
- Main panel: readable message column with stable width and generous vertical rhythm.
- Composer area: fixed bottom input with clear model/tool context and run-state feedback.
- Activity feedback: explicit states for connecting, running, waiting, and completed actions.

### Acceptance checklist

- [ ] Current color tokens remain intact (no palette drift).
- [ ] Information hierarchy mirrors Claude-like flow (nav → conversation → composer).
- [ ] Login/admin state messaging is conditional and accurate.
- [ ] Long-running actions always display visible “something is happening” feedback.

## 7. Study-hall checklist

The self-help path for a fresh AI engineer, start to finish:

```bash
curl -fsSL https://tekt.md/install.sh | bash    # 1. bootstrap everything
bash install.sh status                          # 2. see what landed
bash install.sh mcp                             # 3. hub + curated four MCP servers
bash install.sh ui                              # 4. LibreChat + n8n scaffolds, started
bash install.sh share 3080                      # 5. hand the chat URL to a friend
```

Then open LibreChat, pick a model, and ask it to list the files in your Tekt workspace — if it answers, your whole edge stack is alive.

---

Back to: [00 — Arkitype](/00-arkitype/) · [01 — Infrastructure](/01-infrastructure/) · [02 — Database](/02-database/) · [03 — Software](/03-software/)
