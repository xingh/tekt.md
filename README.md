---
layout: layout.njk
title: tekt.md — Tekt Bootstrap
permalink: /index.html
---

# Tekt Bootstrap — Installation Guide

Set up a complete Tekt development environment in a single script. Covers every tool in the Tekt stack — from the platform runtime layer up through native AI agents.

---

## Quick Start

```bash
git clone https://github.com/xingh/tektmd
cd tektmd
bash install.sh
```

**Supported platforms:** macOS (Intel + Apple Silicon), Ubuntu/Debian, Fedora/RHEL, Arch Linux.

---

## What Gets Installed

| # | Tool | Version | Purpose |
|---|------|---------|---------|
| 1 | [Homebrew](#1-homebrew) | latest | Package manager for macOS/Linux |
| 2 | [Go](#2-go) | 1.22.4 | Runtime for Tekt-native agents |
| 3 | [Python](#3-python-via-pyenv) | 3.12.4 via pyenv | Scripting, automation, ML tooling |
| 4 | [nvm / Node.js / npm](#4-nvm--nodejs--npm) | Node 20 LTS | JavaScript runtime for Claude Code and web tools |
| 5 | [rclone](#5-rclone) | latest | S3/object storage sync (Tekt workspace layer) |
| 6 | [AWS CLI + s3 utilities](#6-aws-cli--s3-utilities) | v2 | Cloud storage and workspace management |
| 7 | [Visual Studio Code](#7-visual-studio-code) | latest | Primary editor |
| 8 | [Claude Code](#8-claude-code) | latest | Anthropic CLI agent for agentic coding |
| 9 | [OpenClaw](#9-openclaw) | latest | Tekt full-featured agent workspace |
| 10 | [PicoClaw](#10-picoclaw) | latest | Lightweight Claw runtime for edge/low-resource nodes |
| 11 | [Hermes Agent](#11-hermes-agent) | latest | Tekt messaging and coordination agent |

---

## Prerequisites

- **macOS:** Xcode Command Line Tools (`xcode-select --install`)
- **Linux:** `curl`, `git`, `sudo` access
- **All:** At least 5 GB free disk space, a reliable internet connection

The script installs all other dependencies automatically.

---

## Tool Details

### 1. Homebrew

The foundational package manager. On macOS, most tools install via Homebrew casks or formulae. On Linux, Linuxbrew is installed to `~/.linuxbrew`.

**Manual install:**
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

**Docs:** [brew.sh](https://brew.sh)

---

### 2. Go

Go is the runtime for several Tekt-native tools and agents. The script installs the official binary distribution to `/usr/local/go`.

**Manual install:**
```bash
# macOS
brew install go

# Linux (amd64)
curl -fsSL https://go.dev/dl/go1.22.4.linux-amd64.tar.gz | sudo tar -C /usr/local -xz
echo 'export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"' >> ~/.bashrc
```

**Verify:**
```bash
go version
```

**Docs:** [go.dev](https://go.dev)

---

### 3. Python via pyenv

The script installs [pyenv](https://github.com/pyenv/pyenv) for isolated Python version management, then builds Python 3.12.4 and sets it as the global default.

**Manual install:**
```bash
curl -fsSL https://pyenv.run | bash
pyenv install 3.12.4
pyenv global 3.12.4
```

**Add to shell profile (`~/.zshrc` or `~/.bashrc`):**
```bash
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
```

**Verify:**
```bash
python3 --version
pip --version
```

**Docs:** [github.com/pyenv/pyenv](https://github.com/pyenv/pyenv)

---

### 4. nvm / Node.js / npm

[nvm](https://github.com/nvm-sh/nvm) (Node Version Manager) is installed first, then Node.js 20 LTS and the latest npm. Node 20 is set as the default.

**Manual install:**
```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
source ~/.nvm/nvm.sh

nvm install 20
nvm use 20
nvm alias default 20
```

**Verify:**
```bash
node --version
npm --version
```

**Docs:** [github.com/nvm-sh/nvm](https://github.com/nvm-sh/nvm)

---

### 5. rclone

rclone is the sync backbone for Tekt workspaces — it mirrors the global workspace from S3 to local instances and back. The workspace structure uses `Tekt/Global/Workspaces` for the S3-synced global layer and `Tekt/Instances/` for local git-backed per-installation workspaces.

**Manual install:**
```bash
curl -fsSL https://rclone.org/install.sh | sudo bash
```

**Configure an S3-compatible remote:**
```bash
rclone config
# Choose: n (new remote) → s3 → AWS or Backblaze/Cloudflare R2 → follow prompts
```

**Sync a Tekt workspace:**
```bash
rclone sync s3:tekt-global/Workspaces ~/Tekt/Global/Workspaces --progress
```

**Docs:** [rclone.org](https://rclone.org)

---

### 6. AWS CLI + s3 utilities

Three tools are installed in this section:

#### AWS CLI v2

The primary interface for AWS services including S3, IAM, and EC2.

```bash
# macOS
brew install awscli

# Linux (amd64)
curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip
unzip awscliv2.zip
sudo ./aws/install
```

**Configure:**
```bash
aws configure
# AWS Access Key ID, Secret Key, Default Region, Output format
```

#### s3cmd

Flexible command-line S3 client, useful for batch operations and alternate-provider compatibility (Backblaze B2, Cloudflare R2, MinIO).

```bash
pip install s3cmd
s3cmd --configure
```

#### s5cmd

Extremely fast parallel S3 transfer tool, ideal for large workspace syncs.

```bash
# macOS
brew install peak/tap/s5cmd

# Linux (via Go)
go install github.com/peak/s5cmd/v2@latest
```

**Example — sync workspace:**
```bash
s5cmd sync s3://tekt-global/Workspaces/ ~/Tekt/Global/Workspaces/
```

**Docs:** [AWS CLI](https://docs.aws.amazon.com/cli/) · [s3cmd](https://s3tools.org/s3cmd) · [s5cmd](https://github.com/peak/s5cmd)

---

### 7. Visual Studio Code

The primary editor for Tekt development. The script installs via Homebrew Cask on macOS and via the Microsoft apt/dnf repo on Linux.

**Manual install:**
Download from [code.visualstudio.com/download](https://code.visualstudio.com/download) or:

```bash
# macOS
brew install --cask visual-studio-code

# Ubuntu/Debian
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /usr/share/keyrings/packages.microsoft.gpg > /dev/null
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list
sudo apt update && sudo apt install code
```

**Recommended extensions for Tekt development:**
```bash
code --install-extension ms-python.python
code --install-extension golang.go
code --install-extension anthropics.claude-code
code --install-extension dbaeumer.vscode-eslint
code --install-extension esbenp.prettier-vscode
```

**Docs:** [code.visualstudio.com](https://code.visualstudio.com)

---

### 8. Claude Code

Anthropic's agentic coding CLI. Claude Code runs inside your terminal and can read, write, and execute files, run tests, and interact with your codebase using the full Claude API.

**Install:**
```bash
npm install -g @anthropic-ai/claude-code
```

**First run:**
```bash
claude
# Follow the authentication prompt (requires Anthropic account)
```

**Useful flags:**
```bash
claude --help                  # Full command reference
claude --model claude-sonnet-4 # Select model
claude --print "explain this"  # Non-interactive mode
```

**Docs:** [docs.anthropic.com/claude-code](https://docs.anthropic.com/claude-code)

---

### 9. OpenClaw

OpenClaw is Tekt's primary agentic workspace runtime — a full-featured agent environment built on top of the Claw architecture. It orchestrates tool calls, manages MCP server connections, and runs multi-step agent workflows.

**Install (once published):**
```bash
npm install -g @anantcorp/openclaw
```

**Initialize a workspace:**
```bash
openclaw init --workspace ~/Tekt/Instances/myworkspace
openclaw start
```

> **Note:** OpenClaw is under active development. The install script and public repo will be linked here on release.

---

### 10. PicoClaw

PicoClaw is the lightweight Claw runtime for resource-constrained or edge environments — background processing nodes, headless machines, and embedded Tekt instances. Functionally equivalent to OpenClaw but with a minimal footprint.

**Install (once published):**
```bash
npm install -g @anantcorp/picoclaw
```

**Typical use case (background node):**
```bash
picoclaw start --mode headless --sync-remote s3://tekt-global
```

> **Note:** PicoClaw is under active development. The install script and public repo will be linked here on release.

---

### 11. Hermes Agent

Hermes is Tekt's coordination and messaging agent — responsible for routing tasks, managing inter-agent communication, and handling async workflows across the Tekt instance graph.

**Install (once published):**
```bash
# Install script and repo will be available at release
```

**Or build from source (internal):**
```bash
git clone https://github.com/xingh/hermes-agent
cd hermes-agent
go build -o hermes .
sudo mv hermes /usr/local/bin/
```

**Start the agent:**
```bash
hermes start --config ~/.tekt/hermes.yaml
```

> **Note:** Hermes Agent is under active development. The public release and install script will be linked here on release.

---

## Post-Installation

### Reload your shell

After the script completes, restart your terminal or reload your profile:

```bash
# zsh (macOS default)
source ~/.zshrc

# bash
source ~/.bashrc
```

### Verify everything is running

```bash
brew --version
go version
python3 --version
node --version && npm --version
rclone version
aws --version
code --version
claude --version
openclaw --version
picoclaw --version
hermes --version
```

### Configure your Tekt workspace

```bash
# Initialize the global workspace sync
rclone config      # set up your S3 remote (name it: tekt-s3)
openclaw init
```

---

## Customizing the Script

The top of `install.sh` exposes version pins and repo URLs as variables. Edit these before running to lock specific versions:

```bash
GO_VERSION="1.22.4"
PYTHON_VERSION="3.12.4"
NODE_VERSION="20"
NVM_VERSION="0.40.1"

OPENCLAW_REPO="https://github.com/xingh/openclaw"   # update when repo is public
PICOCLAW_REPO="https://github.com/xingh/picoclaw"   # update when repo is public
HERMES_REPO="https://github.com/xingh/hermes-agent" # update when repo is public
```

To skip a specific tool, comment out its call in the `main()` function at the bottom of the script.

---

## Troubleshooting

**`command not found` after install**
The new binary is not yet in your `$PATH`. Reload your shell profile:
```bash
source ~/.zshrc   # or ~/.bashrc
```

**`brew: command not found` on Linux**
Linuxbrew installs to `/home/linuxbrew/.linuxbrew`. Add to PATH:
```bash
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
```

**Python build fails on Linux**
Install build dependencies first:
```bash
sudo apt install build-essential libssl-dev zlib1g-dev libbz2-dev \
  libreadline-dev libsqlite3-dev liblzma-dev
```

**AWS CLI install fails on ARM Linux**
Ensure you're using the `aarch64` build — the script auto-detects, but verify `uname -m` returns `aarch64`.

**OpenClaw / PicoClaw / Hermes not yet available**
These tools are under active development and not yet publicly released. Internal builds can be obtained directly from Anant Corporation.

---

## Architecture Reference

```
Tekt/
├── Global/
│   └── Workspaces/          ← synced from S3 via rclone / s5cmd
└── Instances/
    ├── dev-main/            ← local git-backed workspace (OpenClaw)
    ├── edge-node-01/        ← lightweight instance (PicoClaw)
    └── hermes/              ← coordination layer (Hermes Agent)
```

See the [Tekt Workspace Architecture](#architecture-reference) section above for a full diagram of the cloud-to-edge sync model.

---

## Contributing

Issues and PRs welcome at [github.com/xingh/tektmd](https://github.com/xingh/tektmd).

---

*Maintained by [Anant Corporation](https://anant.us)*
