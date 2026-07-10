---
layout: layout.njk
title: 01 — Infrastructure
permalink: /01-infrastructure/index.html
---

# 01 — Infrastructure

Everything the rest of the stack stands on: version control, package managers, language runtimes, the editor, the container runtime, and the two network tools (Tailscale, ngrok) that let a home-lab machine safely reach — and be reached by — the outside world.

Run `bash install.sh` to install all of this automatically, or use the sections below to install pieces by hand. `bash install.sh status` shows what's present. Windows users: `.\install.ps1` (PowerShell) or WSL2 + `install.sh`.

---

## 1. Git

Required by nearly everything else (Homebrew, pyenv, nvm, every agent that clones from source). The bootstrap installs Git **first** — Homebrew requires it.

```bash
# macOS
xcode-select --install
# Ubuntu/Debian
sudo apt-get update && sudo apt-get install -y git
# Fedora/RHEL
sudo dnf install -y git
# Arch
sudo pacman -S --noconfirm git
# Windows (PowerShell)
winget install --id Git.Git -e
```

First-time config:

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

Docs: [git-scm.com](https://git-scm.com)

## 2. Homebrew (macOS/Linux)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Add to PATH (`~/.zshrc` or `~/.bashrc`):

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"              # macOS Apple Silicon
eval "$(/usr/local/bin/brew shellenv)"                 # macOS Intel
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" # Linux
```

Docs: [brew.sh](https://brew.sh)

## 3. Go

Runtime for Tekt-native tools (PicoClaw builds, s5cmd, nanobot-ai/nanobot if you choose it).

```bash
# macOS
brew install go
# Linux (amd64 — swap arm64 as needed; pin from tekt.catalog.yaml)
curl -fsSL https://go.dev/dl/go1.26.2.linux-amd64.tar.gz -o go.tar.gz
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go.tar.gz && rm go.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> ~/.bashrc
# Windows
winget install --id GoLang.Go -e
```

Docs: [go.dev/doc/install](https://go.dev/doc/install)

## 4. Python via pyenv

```bash
curl -fsSL https://pyenv.run | bash        # or: brew install pyenv
pyenv install 3.14 && pyenv global 3.14
```

Shell config and Linux build dependencies: see the [pyenv README](https://github.com/pyenv/pyenv). On Windows, install Python directly: `winget install --id Python.Python.3.12 -e` (Hermes needs 3.11+; nanobot needs 3.11+).

## 5. nvm / Node.js

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
nvm install --lts && nvm alias default lts/*    # Node 24 (Krypton)
```

Windows: `winget install --id OpenJS.NodeJS.LTS -e`. Node 24 is required by OpenClaw and used by the npm-installed MCP servers.

Docs: [github.com/nvm-sh/nvm](https://github.com/nvm-sh/nvm)

## 6. Visual Studio Code

```bash
brew install --cask visual-studio-code       # macOS
winget install --id Microsoft.VisualStudioCode -e   # Windows
```

Linux apt/dnf repo setup: [code.visualstudio.com/docs/setup/linux](https://code.visualstudio.com/docs/setup/linux). Recommended extensions: `ms-python.python`, `golang.go`, `anthropics.claude-code`, `dbaeumer.vscode-eslint`, `esbenp.prettier-vscode`.

## 7. Docker & Docker Compose

The container runtime for the entire `tekt.cloud` layer (MCPHub, LibreChat, n8n) plus MinIO/Postgres in `tekt.base`, and NanoClaw's agent sandboxes.

```bash
# macOS
brew install --cask docker
# Linux — convenience script (installs Engine + Compose plugin)
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER    # then log out/in
# Windows
winget install --id Docker.DockerDesktop -e
```

Verify: `docker --version && docker compose version`. Docs: [docs.docker.com/engine/install](https://docs.docker.com/engine/install/)

---

## 8. .NET SDK

Required to build **Sovrant** (the `tekt.cloud` command center, written in C# on .NET 10) from source. The bootstrap installs it user-locally on Linux — no sudo.

```bash
# macOS
brew install --cask dotnet-sdk
# Linux — Microsoft's official install script, user-local to ~/.dotnet
curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 10.0
export DOTNET_ROOT="$HOME/.dotnet" && export PATH="$DOTNET_ROOT:$DOTNET_ROOT/tools:$PATH"
# Windows
winget install --id Microsoft.DotNet.SDK.10 -e
```

Verify: `dotnet --version` (should report a 10.x SDK). Docs: [dotnet.microsoft.com/download](https://dotnet.microsoft.com/download). The channel is pinned as `DOTNET_CHANNEL` in `tekt.catalog.yaml`.

---

## 9. Tailscale — private mesh network

Tailscale puts every Tekt node (workspace, agent nodes, cloud node) on one flat, encrypted WireGuard network. It is also the **preferred way to give your local MCP hub an HTTPS interface** (`tailscale serve`) without opening firewall ports. The client is open source (BSD-3); the coordination service is Tailscale Inc.'s.

```bash
# Linux (all major distros)
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
# macOS
brew install --cask tailscale     # or the App Store app
# Windows
winget install --id tailscale.tailscale -e
```

First run opens a browser login (free personal plan covers a home lab). Then:

```bash
tailscale status                  # see your mesh
tailscale ip -4                   # this node's tailnet IP
tailscale serve --bg 3000         # HTTPS-terminate localhost:3000 inside your tailnet
tailscale funnel --bg 3000        # …or expose it to the public internet (use sparingly)
```

Docs: [tailscale.com/kb](https://tailscale.com/kb)

## 10. ngrok — instant public tunnels

ngrok gives any local port a public HTTPS URL in one command — the fastest way to demo LibreChat or hand an MCP endpoint to a collaborator during a study hall. The agent is proprietary with a generous free tier; you need a free authtoken from [dashboard.ngrok.com](https://dashboard.ngrok.com).

```bash
# macOS
brew install ngrok
# Linux (Debian/Ubuntu — official apt repo)
curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
  | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
echo "deb https://ngrok-agent.s3.amazonaws.com buster main" \
  | sudo tee /etc/apt/sources.list.d/ngrok.list
sudo apt update && sudo apt install -y ngrok
# Windows
winget install --id Ngrok.Ngrok -e
```

Configure once, then tunnel:

```bash
ngrok config add-authtoken <YOUR_TOKEN>
ngrok http 3000        # public HTTPS → local MCPHub
ngrok http 3080        # public HTTPS → local LibreChat
```

Docs: [ngrok.com/docs](https://ngrok.com/docs)

> **Tailscale or ngrok?** Tailscale for anything persistent or private (your own devices, your team's tailnet). ngrok for quick public demos and webhook testing. `bash install.sh share <port>` picks Tailscale Serve if your tailnet is up, otherwise falls back to ngrok.

---

## Verify the layer

```bash
bash install.sh status
```

Next: [02 — Database](/02-database/) for the data & sync layer.
