---
layout: layout.njk
title: 02 — Database
permalink: /02-database/index.html
---

# 02 — Database & Data Layer

The `tekt.base` layer: how bytes move and persist. Object-storage sync keeps every node's workspace consistent; the databases here back the `tekt.cloud` services (LibreChat, n8n, MCPHub) when you bring those up.

---

## Workspace layout

```
Tekt/
├── Global/
│   └── Workspaces/          ← synced from S3 via rclone / s5cmd
└── Instances/
    └── <hostname>/
        ├── workspace/       ← what your local agents & MCP servers see
        ├── mcp/             ← MCPHub config + compose (see 03/04)
        └── cloud/           ← LibreChat / n8n stacks (see 04)
```

`bash install.sh` creates `~/Tekt/Instances/<hostname>/` automatically.

## 1. rclone — the sync backbone

Mirrors the global workspace between S3-compatible storage and every instance. Also mounts consumer clouds (Google Drive, OneDrive, Dropbox, iCloud Drive via WebDAV) so you can sync people up without giving them AWS credentials.

```bash
# Linux/macOS (script — supports FUSE mounts)
sudo -v ; curl https://rclone.org/install.sh | sudo bash
# macOS Homebrew (no FUSE mount support)
brew install rclone
# Windows
winget install --id Rclone.Rclone -e
```

Configure a remote and sync:

```bash
rclone config                       # n → name it tekt-s3 → s3 → your provider
rclone sync tekt-s3:tekt-global/Workspaces ~/Tekt/Global/Workspaces --progress
```

Consumer-cloud examples (each is a guided `rclone config` flow):

```bash
rclone config    # → drive (Google Drive) | onedrive | dropbox | webdav (iCloud)
rclone sync gdrive:TektShared ~/Tekt/Global/Workspaces/shared --progress
```

Docs: [rclone.org](https://rclone.org)

## 2. AWS CLI v2 + s3cmd + s5cmd

```bash
# AWS CLI — Linux x86_64 (see docs for macOS .pkg / ARM)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip awscliv2.zip && sudo ./aws/install && rm -rf aws awscliv2.zip
aws configure

# s3cmd — batch ops, alt-provider friendly (B2, R2, MinIO)
pip install s3cmd && s3cmd --configure

# s5cmd — very fast parallel transfers, ideal for big workspace syncs
brew install peak/tap/s5cmd                      # macOS
go install github.com/peak/s5cmd/v2@v2.3.0       # anywhere with Go
s5cmd sync s3://tekt-global/Workspaces/ ~/Tekt/Global/Workspaces/
```

Docs: [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) · [s3cmd](https://s3tools.org/s3cmd) · [s5cmd](https://github.com/peak/s5cmd)

## 3. MinIO — your own S3 (optional but sovereign)

If AI sovereignty is the point, host the bucket yourself. MinIO speaks the S3 API, so rclone/s5cmd/AWS CLI all point at it unchanged.

```bash
mkdir -p ~/Tekt/Instances/$(hostname -s)/cloud/minio && cd $_
cat > docker-compose.yml <<'EOF'
services:
  minio:
    image: minio/minio
    command: server /data --console-address ":9001"
    ports: ["9000:9000", "9001:9001"]
    environment:
      MINIO_ROOT_USER: tekt
      MINIO_ROOT_PASSWORD: change-me-now
    volumes:
      - minio_data:/data
volumes:
  minio_data:
EOF
docker compose up -d
```

Console at `http://localhost:9001`. Point rclone at it: endpoint `http://localhost:9000`, provider `Minio`. Upstream: MinIO, Inc. (AGPL v3). Docs: [min.io/docs](https://min.io/docs)

## 4. PostgreSQL + pgvector (optional)

Two `tekt.cloud` features want Postgres:

- **MCPHub database mode / Smart Routing** — vector semantic search over tools requires Postgres with pgvector
- **n8n production deployments** — n8n defaults to SQLite, but Postgres is recommended once workflows matter

```bash
mkdir -p ~/Tekt/Instances/$(hostname -s)/cloud/postgres && cd $_
cat > docker-compose.yml <<'EOF'
services:
  postgres:
    image: pgvector/pgvector:pg17
    ports: ["5432:5432"]
    environment:
      POSTGRES_USER: tekt
      POSTGRES_PASSWORD: change-me-now
      POSTGRES_DB: tekt
    volumes:
      - pg_data:/var/lib/postgresql/data
volumes:
  pg_data:
EOF
docker compose up -d
```

Upstream: PostgreSQL Global Development Group; pgvector by Andrew Kane.

## 5. MongoDB + Meilisearch (bundled with LibreChat)

You do **not** install these by hand — LibreChat's official `docker compose` stack brings its own MongoDB (chat storage) and Meilisearch (message search) containers, wired and networked. They're listed here so you know what's running and where the data lives (Docker volumes in the LibreChat project directory). Details in [04 — Interface](/04-interface/).

## 6. SQLite — the quiet default

Several agents keep local state in SQLite with zero setup: ZeroClaw's memory engine (vector + FTS5 hybrid search), NanoClaw's session databases, n8n's default store. Nothing to install — just know your agent state lives under each tool's home directory, and back it up with your workspace sync if you care about it.

## 7. Archetype schema contract: Memory Engine vs Knowledge Engine

Tekt formalizes two storage archetypes so architecture decisions stay consistent across tools:

| Archetype | Purpose | Typical stores | Data pattern |
| --- | --- | --- | --- |
| **Memory Engine** | Local runtime memory for active agent/session behavior | SQLite, vector sidecar, FTS indexes | High-churn append/update, short-to-medium retention |
| **Knowledge Engine** | Durable, shared knowledge for teams/workspaces | Postgres (+pgvector), document stores, graph-shaped models | Curated ingest, versioned updates, long-lived retention |

Rule of thumb: keep fast conversational/working state in Memory Engine schemas; promote validated, reusable knowledge artifacts to Knowledge Engine schemas.

## 8. Spaces: share with the storage people already use

Most people will never touch git or an S3 bucket, but they all have Google Drive, OneDrive, Dropbox, Box, Nextcloud or a NAS. **Spaces** put rclone's sync engine behind one command, so a group can share documents, knowledge and skills through what they already have:

```bash
tekt space add team drive        # or onedrive, dropbox, box, nextcloud, folder, s3
tekt space autosync on           # rclone bisync every 10 minutes (cron / Scheduled Task)
tekt space list                  # what's shared, and when it last synced
```

- **On disk:** `~/Tekt/Spaces/<name>/{docs,knowledge,skills}` plus a local-only `.tekt-space` settings file. The same format is used by `install.sh` and `install.ps1`.
- **Connection:** each Space gets its own rclone remote named `tekt-<name>`. Sign-in is OAuth in the browser (Drive, OneDrive, Dropbox, Box) or an app password (Nextcloud). Tokens stay in rclone's config on your machine.
- **Sync:** `rclone bisync`. The first run merges both sides with `--resync`. After that, on rclone ≥ 1.66, the newest change wins and the other copy is kept.
- **Knowledge Engine tie-in:** `knowledge/` is the human-curated layer that feeds the Knowledge Engine (§7). `docs/` is raw material, and `skills/` is picked up by agents (v0.4).

The plain-language guide is at [tekt.md/spaces](/spaces/).

---

## Verify the layer

```bash
bash install.sh status         # rclone / aws / s3cmd / s5cmd rows
docker ps                      # minio / postgres if you started them
```

Next: [03 — Software](/03-software/) for agents, models, and MCP servers.
