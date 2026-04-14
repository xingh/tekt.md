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
git clone https://github.com/xingh/tekt.md
cd tekt.md
bash install.sh
```

**Supported platforms:** macOS (Intel + Apple Silicon), Ubuntu/Debian, Fedora/RHEL, Arch Linux.

---

## What Gets Installed

| # | Tool | Version | Purpose |
|---|------|---------|---------|
| 1 | [Homebrew](#1-homebrew) | 5.x | Package manager for macOS/Linux |
| 2 | [Go](#2-go) | 1.26.2 | Runtime for Tekt-native agents |
| 3 | [Python](#3-python-via-pyenv) | 3.14.x via pyenv | Scripting, automation, ML tooling |
| 4 | [nvm / Node.js / npm](#4-nvm--nodejs--npm) | Node 24 LTS | JavaScript runtime for Claude Code and web tools |
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

The foundational package manager. On macOS, most tools install via Homebrew casks or formulae. On Linux, Linuxbrew is installed to `/home/linuxbrew/.linuxbrew`.

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

### 2. Go

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

### 3. Python via pyenv

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

### 4. nvm / Node.js / npm

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

### 5. rclone

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

### 6. AWS CLI + s3 utilities

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

### 7. Visual Studio Code

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

### 8. Claude Code

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
python --version
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
GO_VERSION="1.26.2"
PYTHON_VERSION="3.14"
NODE_VERSION="24"          # Active LTS
NVM_VERSION="0.40.4"

OPENCLAW_REPO="https://github.com/anantcorp/openclaw"   # update when repo is public
PICOCLAW_REPO="https://github.com/anantcorp/picoclaw"   # update when repo is public
HERMES_REPO="https://github.com/anantcorp/hermes-agent" # update when repo is public
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

Issues and PRs welcome at [github.com/xingh/tekt.md](https://github.com/xingh/tekt.md).

---

*Maintained by [Anant Corporation](https://anant.us)*
