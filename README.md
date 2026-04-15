---
layout: layout.njk
title: tekt.md — Tekt Bootstrap
permalink: /index.html
---
# Tekt Bootstrap — Installation Guide

Set up a complete Tekt development environment in a single script. Covers every tool in the Tekt stack — from the platform runtime layer up through native AI agents.

---

## Quick Start (Curl)

```bash
curl -fsSL https://tekt.md/install.sh | bash
```

## Quick Start (Git)

```bash
git clone https://github.com/xingh/tekt.md
cd tekt.md
bash install.sh
```

## Quick Start (VirtualBox)

If you would like to download an OEM Linux Mint distribution by Rahul Singh, you can download it here. It will boot up in VirtualBox or any compliant VM system and ask you to set it up as if it was a brand new computer, except that it has most of the prerequisites installed (except Hermes Agent and PicoClaw).

- Install Oracle [VirtualBox](https://virtualbox.org)
- [Download TEKT VM here.](https://drive.google.com/file/d/1LG1PuvDKxfj-RyGCJ_iRCbnOPWe17fOL/view?usp=sharing)
- After initial setup:

```bash
cd ~/Tools/tekt.md
git pull
bash install.sh
```

**Supported platforms:** macOS (Intel + Apple Silicon), Ubuntu/Debian, Fedora/RHEL, Arch Linux.

---

## What Gets Installed

### Tekt.Dev — Development Environment

| # | Tool | Version | Purpose |
|---|------|---------|---------|
| 1 | [Git](#1-git) | latest | Version control — required by nearly every other tool |
| 2 | [Homebrew](#2-homebrew) | 5.x | Package manager for macOS/Linux |
| 3 | [Go](#3-go) | 1.26.2 | Runtime for Tekt-native agents |
| 4 | [Python](#4-python-via-pyenv) | 3.14.x via pyenv | Scripting, automation, ML tooling |
| 5 | [nvm / Node.js / npm](#5-nvm--nodejs--npm) | Node 24 LTS | JavaScript runtime and web tools |
| 6 | [Visual Studio Code](#6-visual-studio-code) | latest | Primary editor |
| 7 | [Docker & Docker Compose](#7-docker--docker-compose) | latest | Container runtime and orchestration |

### Tekt.Base — Communications & Sync

| # | Tool | Version | Purpose |
|---|------|---------|---------|
| 8 | [rclone](#8-rclone) | latest | S3/object storage sync (Tekt workspace layer) |
| 9 | [AWS CLI + s3 utilities](#9-aws-cli--s3-utilities) | v2 | Cloud storage and workspace management |

### Tekt.Iris — Intelligence

| # | Tool | Version | Purpose |
|---|------|---------|---------|
| 10 | [Claude Code](#10-claude-code) | latest | Anthropic agentic coding CLI |
| 11 | [OpenClaw](#11-openclaw) | latest | Personal AI assistant and agent workspace |
| 12 | [PicoClaw](#12-picoclaw) | latest | Lightweight AI agent for edge/low-resource nodes |
| 13 | [Hermes Agent](#13-hermes-agent) | latest | Self-improving AI agent with messaging gateway |

---

## Prerequisites

- **macOS:** Xcode Command Line Tools (`xcode-select --install`)
- **Linux:** `curl`, `sudo` access
- **All:** At least 5 GB free disk space, a reliable internet connection

The script installs Git and all other dependencies automatically.

---

## Tool Details


---

## Tekt.Dev — Development Environment

### 1. Git

Git is the foundational version control system — nearly every other tool in this stack depends on it (Homebrew, pyenv, nvm, OpenClaw, PicoClaw, Hermes Agent, etc.). The script ensures Git is installed before anything else.

**macOS:**

Git ships with Xcode Command Line Tools. If not already installed:
```bash
xcode-select --install
```

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install -y git
```

**Fedora/RHEL:**
```bash
sudo dnf install -y git
```

**Arch:**
```bash
sudo pacman -S --noconfirm git
```

**Configure (first-time setup):**
```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

**Verify:**
```bash
git --version
```

**Docs:** [git-scm.com](https://git-scm.com) · [git-scm.com/book](https://git-scm.com/book/en/v2)

---

### 2. Homebrew

The foundational package manager. On macOS, most tools install via Homebrew casks or formulae. On Linux, Linuxbrew is installed to `/home/linuxbrew/.linuxbrew`. Requires Git.

**Manual install** (from [brew.sh](https://brew.sh)):
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

**Post-install — add Homebrew to PATH:**
```bash
# macOS Apple Silicon (/opt/homebrew)
eval "$(/opt/homebrew/bin/brew shellenv)"

# macOS Intel (/usr/local)
eval "$(/usr/local/bin/brew shellenv)"

# Linux
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
```

Add the appropriate `eval` line to your shell profile (`~/.zshrc` or `~/.bashrc`).

**Verify:**
```bash
brew --version
brew doctor
```

**Docs:** [brew.sh](https://brew.sh) · [docs.brew.sh](https://docs.brew.sh)

---

### 3. Go

Go is the runtime for several Tekt-native tools and agents. The script installs the official binary distribution to `/usr/local/go`.

**Current stable: Go 1.26.2** (released April 2026). Go supports the two most recent major versions (1.26.x and 1.25.x).

**Manual install — macOS:**
```bash
brew install go
```

Or download the `.pkg` installer from [go.dev/dl](https://go.dev/dl/).

**Manual install — Linux (amd64):**
```bash
curl -fsSL https://go.dev/dl/go1.26.2.linux-amd64.tar.gz -o go.tar.gz
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go.tar.gz
rm go.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> ~/.bashrc
source ~/.bashrc
```

**Manual install — Linux (arm64):**
```bash
curl -fsSL https://go.dev/dl/go1.26.2.linux-arm64.tar.gz -o go.tar.gz
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go.tar.gz
rm go.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> ~/.bashrc
source ~/.bashrc
```

**Verify:**
```bash
go version
# → go version go1.26.2 linux/amd64
```

**Docs:** [go.dev/doc/install](https://go.dev/doc/install)

---

### 4. Python via pyenv

The script installs [pyenv](https://github.com/pyenv/pyenv) for isolated Python version management, then builds the current stable Python and sets it as the global default.

**Current stable: Python 3.14.x** (3.12.x is now security-only).

**Manual install — pyenv:**
```bash
curl -fsSL https://pyenv.run | bash
```

Or on macOS: `brew install pyenv`

**Shell configuration — Bash** (add to `~/.bashrc` and `~/.profile`):
```bash
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - bash)"
```

**Shell configuration — Zsh** (add to `~/.zshrc`):
```bash
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - zsh)"
```

**Build dependencies — Ubuntu/Debian:**
```bash
sudo apt update && sudo apt install -y make build-essential libssl-dev zlib1g-dev \
  libbz2-dev libreadline-dev libsqlite3-dev curl git \
  libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev
```

**Build dependencies — Fedora/RHEL:**
```bash
sudo dnf install -y make gcc patch zlib-devel bzip2 bzip2-devel \
  readline-devel sqlite sqlite-devel openssl-devel tk-devel \
  libffi-devel xz-devel libuuid-devel gdbm-libs libnsl2
```

**Install Python:**
```bash
pyenv install 3.14       # auto-resolves to latest 3.14.x patch
pyenv global 3.14
```

**Verify:**
```bash
pyenv --version
python --version
pip --version
```

**Docs:** [github.com/pyenv/pyenv](https://github.com/pyenv/pyenv)

---

### 5. nvm / Node.js / npm

[nvm](https://github.com/nvm-sh/nvm) (Node Version Manager) is installed first, then the current active LTS release of Node.js.

**Current active LTS: Node.js 24 "Krypton"**. Node 22 is in maintenance LTS. Node 20 reached end-of-life in April 2026.

**Manual install — nvm v0.40.4:**
```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
```

Or with wget:
```bash
wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
```

The script automatically adds the following to your shell profile. If needed manually:
```bash
export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
```

**Install Node.js:**
```bash
nvm install --lts          # installs Node 24.x (active LTS)
nvm alias default lts/*    # set as default
```

**Verify:**
```bash
command -v nvm    # outputs: nvm (it's a shell function, not a binary)
nvm --version     # → 0.40.4
node --version    # → v24.x.x
npm --version
```

**Docs:** [github.com/nvm-sh/nvm](https://github.com/nvm-sh/nvm) · [nodejs.org](https://nodejs.org)

---
---

### 6. Visual Studio Code

The primary editor for Tekt development.

**macOS (Homebrew):**
```bash
brew install --cask visual-studio-code
```

Or download from [code.visualstudio.com/download](https://code.visualstudio.com/download).

**Ubuntu/Debian (DEB822 format):**
```bash
# Import GPG key
sudo apt-get install -y wget gpg
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
sudo install -D -o root -g root -m 644 microsoft.gpg /usr/share/keyrings/microsoft.gpg
rm microsoft.gpg

# Create repo file (DEB822 .sources format)
cat << 'EOF' | sudo tee /etc/apt/sources.list.d/vscode.sources
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /usr/share/keyrings/microsoft.gpg
EOF

# Install
sudo apt-get install -y apt-transport-https
sudo apt-get update
sudo apt-get install -y code
```

**Fedora/RHEL:**
```bash
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" \
  | sudo tee /etc/yum.repos.d/vscode.repo > /dev/null
sudo dnf check-update
sudo dnf install -y code
```

**Recommended extensions for Tekt development:**
```bash
code --install-extension ms-python.python
code --install-extension golang.go
code --install-extension anthropics.claude-code
code --install-extension dbaeumer.vscode-eslint
code --install-extension esbenp.prettier-vscode
```

**Verify:**
```bash
code --version
```

**Docs:** [code.visualstudio.com](https://code.visualstudio.com) · [VS Code on Linux](https://code.visualstudio.com/docs/setup/linux)

---

---

### 7. Docker & Docker Compose

Docker is the container runtime used across the Tekt stack for running isolated agent environments, services, and development infrastructure. Docker Compose V2 is included as a plugin (`docker compose`) and handles multi-container orchestration.

**macOS (Docker Desktop via Homebrew):**
```bash
brew install --cask docker
```

Then launch Docker Desktop from Applications to start the daemon.

**Linux — convenience script (recommended for dev environments):**
```bash
curl -fsSL https://get.docker.com | sh
```

This installs Docker Engine, Docker CLI, containerd, Docker Buildx, and Docker Compose plugin in one command.

**Linux — Ubuntu/Debian (official apt repo):**
```bash
# Remove conflicting packages
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  sudo apt-get remove -y $pkg 2>/dev/null || true
done

# Add Docker's official GPG key and repo
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

**Linux — Fedora/RHEL:**
```bash
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl start docker
sudo systemctl enable docker
```

**Post-install — run Docker without sudo (Linux):**
```bash
sudo usermod -aG docker $USER
# Log out and back in for group membership to take effect
```

**Verify:**
```bash
docker --version
docker compose version
sudo docker run hello-world
```

**Docs:** [docs.docker.com/engine/install](https://docs.docker.com/engine/install/) · [docs.docker.com/compose](https://docs.docker.com/compose/)

---

## Tekt.Base — Communications & Sync

### 8. rclone

rclone is the sync backbone for Tekt workspaces — it mirrors the global workspace from S3 to local instances and back. The workspace structure uses `Tekt/Global/Workspaces` for the S3-synced global layer and `Tekt/Instances/` for local git-backed per-installation workspaces.

**Manual install — Linux/macOS (script):**
```bash
sudo -v ; curl https://rclone.org/install.sh | sudo bash
```

**macOS (Homebrew):**
```bash
brew install rclone
```

> **Note:** Homebrew installs do not support FUSE mounting. Use the script install if you need mount support.

**Linux manual (amd64):**
```bash
curl -O https://downloads.rclone.org/rclone-current-linux-amd64.zip
unzip rclone-current-linux-amd64.zip
cd rclone-*-linux-amd64
sudo cp rclone /usr/bin/
sudo chown root:root /usr/bin/rclone
sudo chmod 755 /usr/bin/rclone
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

**Self-update** (for existing installs):
```bash
rclone selfupdate
```

**Verify:**
```bash
rclone version
```

**Docs:** [rclone.org](https://rclone.org) · [rclone.org/install](https://rclone.org/install/)

---
### 9. AWS CLI + s3 utilities

Three tools are installed in this section:

#### AWS CLI v2

The primary interface for AWS services including S3, IAM, and EC2.

**macOS:**
```bash
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /
rm AWSCLIV2.pkg
```

**Linux (x86_64):**
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip
```

**Linux (ARM64):**
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip
```

**Update an existing install:**
```bash
sudo ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update
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

# Linux / any platform with Go
go install github.com/peak/s5cmd/v2@v2.3.0
```

Pre-built binaries and `.deb` packages are also available on the [GitHub releases page](https://github.com/peak/s5cmd/releases).

**Example — sync workspace:**
```bash
s5cmd sync s3://tekt-global/Workspaces/ ~/Tekt/Global/Workspaces/
```

**Docs:** [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) · [s3cmd](https://s3tools.org/s3cmd) · [s5cmd](https://github.com/peak/s5cmd)

---

---

## Tekt.Iris — Intelligence

### 10. Claude Code

Anthropic's agentic coding CLI. Claude Code runs inside your terminal and can read, write, and execute files, run tests, and interact with your codebase using the full Claude API. Open-sourced in March 2026.

**System requirements:** macOS 13.0+, Ubuntu 20.04+/Debian 10+, 4 GB+ RAM, x64 or ARM64. Requires Node.js 18+ (for npm method) or no prerequisites (for native installer).

**Install — native installer (recommended):**
```bash
curl -fsSL https://claude.ai/install.sh | bash
```

**Install — Homebrew:**
```bash
brew install --cask claude-code
```

**Install — npm (deprecated, still functional):**
```bash
npm install -g @anthropic-ai/claude-code
```

> **Note:** Anthropic recommends migrating from npm to the native installer. After installing natively, run `npm uninstall -g @anthropic-ai/claude-code` to remove the npm version.

**First run:**
```bash
claude
# Follow the browser-based authentication prompt (requires Anthropic account)
```

Alternatively, set `ANTHROPIC_API_KEY` for API key authentication. Also supports Amazon Bedrock, Google Vertex AI, and Microsoft Foundry as alternative backends.

**Updates:**
Native installs auto-update. Manual update: `claude update`. Release channels (`stable` or `latest`) are configurable in `~/.claude/settings.json`.

**Useful commands:**
```bash
claude --version               # Check installed version
claude doctor                  # Diagnose configuration issues
claude --model claude-sonnet-4 # Select model
claude --print "explain this"  # Non-interactive mode
claude --help                  # Full command reference
```

**Docs:** [code.claude.com](https://code.claude.com/docs/en/setup) · [github.com/anthropics/claude-code](https://github.com/anthropics/claude-code)

---

### 11. OpenClaw

OpenClaw is the primary agentic workspace runtime in the Tekt stack — an open-source personal AI assistant that orchestrates tool calls, manages MCP server connections, runs multi-step agent workflows, and connects to messaging platforms (Telegram, WhatsApp, Slack, Discord, Signal, iMessage, Matrix, and more).

**Requirements:** Node.js 24 (recommended) or Node 22.16+.

**Install — one-line script (recommended):**
```bash
curl -fsSL https://openclaw.ai/install.sh | bash
```

**Install — npm:**
```bash
npm install -g openclaw@latest
```

**Install — pnpm:**
```bash
pnpm add -g openclaw@latest
```

**Install — from source:**
```bash
git clone https://github.com/openclaw/openclaw.git
cd openclaw
pnpm install && pnpm ui:build && pnpm build
pnpm link --global
```

**Onboard and start:**
```bash
openclaw onboard --install-daemon   # guided setup wizard
openclaw gateway status             # verify Gateway is running
openclaw dashboard                  # open Control UI in browser
```

The onboard wizard walks you through choosing a model provider, setting an API key, and configuring the Gateway daemon (installed as a `launchd` or `systemd` user service).

**Useful commands:**
```bash
openclaw --version                  # check installed version
openclaw doctor                     # diagnose config issues
openclaw agent --message "Hello"    # send a single message
openclaw update                     # update to latest
openclaw update --channel beta      # switch release channel
```

**Verify:**
```bash
openclaw --version
openclaw gateway status
```

**Docs:** [docs.openclaw.ai](https://docs.openclaw.ai) · [github.com/openclaw/openclaw](https://github.com/openclaw/openclaw)

---

### 12. PicoClaw

PicoClaw is an ultra-lightweight AI assistant written in Go — a single self-contained binary that runs on resource-constrained and edge environments. Built by Sipeed, it runs on $10 hardware with <10MB RAM, supports x86_64, ARM64, and RISC-V, and boots in ~1 second. Used in the Tekt stack for background processing nodes, headless machines, and embedded instances.

**Requirements:** An LLM API key (OpenAI, Anthropic, Google, etc.). No runtime dependencies — PicoClaw is a single static binary.

**Install — download from picoclaw.io (auto-detects platform):**
Visit [picoclaw.io](https://picoclaw.io) for one-click download.

**Install — pre-built binary (macOS arm64):**
```bash
curl -L https://github.com/sipeed/picoclaw/releases/latest/download/picoclaw-darwin-arm64 \
  -o /usr/local/bin/picoclaw
chmod +x /usr/local/bin/picoclaw
```

**Install — pre-built binary (Linux amd64):**
```bash
curl -L https://github.com/sipeed/picoclaw/releases/latest/download/picoclaw-linux-amd64 \
  -o picoclaw
chmod +x picoclaw
sudo mv picoclaw /usr/local/bin/
```

**Install — pre-built binary (Linux arm64):**
```bash
curl -L https://github.com/sipeed/picoclaw/releases/latest/download/picoclaw-linux-arm64 \
  -o picoclaw
chmod +x picoclaw
sudo mv picoclaw /usr/local/bin/
```

**Install — build from source:**
```bash
git clone https://github.com/sipeed/picoclaw.git
cd picoclaw
make deps
make build
make install
```

**Onboard and start:**
```bash
picoclaw onboard          # interactive setup — creates ~/.picoclaw/config.json
picoclaw agent            # start interactive chat
picoclaw agent -m "Hello" # single message mode
```

**Run as a headless gateway (background node):**
```bash
picoclaw gateway
```

**Verify:**
```bash
picoclaw --version
```

**Docs:** [picoclaw.io](https://picoclaw.io) · [github.com/sipeed/picoclaw](https://github.com/sipeed/picoclaw)

---

### 13. Hermes Agent

Hermes is a self-improving AI agent built by Nous Research — the coordination and messaging layer in the Tekt stack. It features a built-in learning loop (auto-creates skills from experience), cross-session memory, and a unified messaging gateway (Telegram, Discord, Slack, WhatsApp, Signal, Email, and more). Supports any LLM provider via OpenRouter, Nous Portal, OpenAI, Anthropic, Google, and custom endpoints.

**Requirements:** Python 3.11+. The installer handles all dependencies automatically (Python, Node.js, ripgrep, ffmpeg).

**Install — one-line script (recommended):**
```bash
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
```

Works on Linux, macOS, WSL2, and Android via Termux. The installer clones the repo, creates a virtual environment, installs all dependencies, sets up the global `hermes` command, and launches the setup wizard.

> **Note:** Native Windows is not supported. Use WSL2.

**Install — manual (from source):**
```bash
git clone --recurse-submodules https://github.com/NousResearch/hermes-agent.git
cd hermes-agent

# Install uv (if not already installed)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Create venv with Python 3.11
uv venv venv --python 3.11
export VIRTUAL_ENV="$(pwd)/venv"

# Install with all extras (messaging, cron, voice, etc.)
uv pip install -e ".[all]"

# Make hermes available globally
mkdir -p ~/.local/bin
ln -sf "$(pwd)/venv/bin/hermes" ~/.local/bin/hermes
```

For core agent only (no Telegram/Discord/cron): `uv pip install -e "."`

**First run:**
```bash
hermes setup              # full setup wizard (provider, model, messaging)
hermes                    # start interactive CLI conversation
hermes gateway            # start messaging gateway
```

**Useful commands:**
```bash
hermes model              # choose LLM provider and model
hermes tools              # configure enabled tools
hermes doctor             # diagnose configuration issues
hermes update             # update to latest version
hermes claw migrate       # migrate settings from OpenClaw
```

**Migrating from OpenClaw:**
Hermes auto-detects `~/.openclaw` during setup and offers to import settings, memories, skills, and API keys. Or run manually:
```bash
hermes claw migrate --dry-run   # preview what would be migrated
hermes claw migrate             # interactive migration
```

**Verify:**
```bash
hermes doctor
hermes --version
```

**Docs:** [hermes-agent.nousresearch.com/docs](https://hermes-agent.nousresearch.com/docs) · [github.com/NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent)

---
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
# Tekt.Dev
git --version
brew --version
go version
python --version
node --version && npm --version
code --version
docker --version && docker compose version

# Tekt.Base
rclone version
aws --version

# Tekt.Iris
claude --version
openclaw --version
picoclaw --version
hermes doctor
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
GO_VERSION="1.26.2"
PYTHON_VERSION="3.14"
NODE_VERSION="24"          # Active LTS
NVM_VERSION="0.40.4"

OPENCLAW_REPO="https://github.com/openclaw/openclaw"
PICOCLAW_REPO="https://github.com/sipeed/picoclaw"
HERMES_REPO="https://github.com/NousResearch/hermes-agent"
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
sudo apt install -y make build-essential libssl-dev zlib1g-dev libbz2-dev \
  libreadline-dev libsqlite3-dev libncursesw5-dev xz-utils tk-dev \
  libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev
```

**AWS CLI install fails on ARM Linux**
Ensure you're using the `aarch64` build — the script auto-detects, but verify `uname -m` returns `aarch64`.

**Claude Code authentication issues**
Run `claude doctor` to diagnose. Ensure you have a valid Anthropic account (Pro, Max, Teams, Enterprise, or Console/API plan).

**nvm: `command -v nvm` returns nothing**
nvm is a shell function, not a binary. Make sure your shell profile sources `$NVM_DIR/nvm.sh`:
```bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
```

**OpenClaw `openclaw: command not found` after npm install**
Ensure `$(npm prefix -g)/bin` is in your `$PATH`. Check with `npm prefix -g`, then add to your shell profile:
```bash
export PATH="$(npm prefix -g)/bin:$PATH"
```

**PicoClaw binary not found**
The pre-built binary must be in your `$PATH`. If you downloaded it manually, move it:
```bash
sudo mv picoclaw /usr/local/bin/
sudo chmod +x /usr/local/bin/picoclaw
```

**Hermes Agent installer fails**
The installer requires `curl`, `git`, and Python build tools. On Ubuntu/Debian:
```bash
sudo apt install -y curl git build-essential
```
Then re-run the install script. If `hermes` is not found after install, add `~/.local/bin` to your `$PATH`:
```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc   # or ~/.zshrc
source ~/.bashrc
```

**PicoClaw / Hermes / OpenClaw still not found after install**
The install script adds `~/.local/bin` and the npm global bin directory to your shell profile automatically. If they still aren't found, restart your terminal entirely (not just `source` — some shells cache PATH).

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

Issues and PRs welcome at [github.com/xingh/tekt.md](https://github.com/xingh/tekt.md).

---

*Maintained by [Anant Corporation](https://anant.us)*
