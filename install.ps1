# =============================================================================
# install.ps1
# Tekt Platform — Windows Bootstrap (PowerShell)
# https://tekt.md
#
# Installs (winget): Git, Go, Python, Node LTS, VS Code, Docker Desktop,
#                    rclone, AWS CLI, Tailscale, ngrok, Ollama
# Installs (native): Claude Code, Claude Desktop, Zed Agent, OpenClaw, PicoClaw, ZeroClaw, Nanobot
# Stages:            NanoClaw (WSL2/Docker), MCPHub, LibreChat, n8n
# Not on Windows:    Hermes Agent (use WSL2 → bash install.sh)
#
# Usage:  .\install.ps1              # full install
#         .\install.ps1 status      # environment check
#         .\install.ps1 mcp         # MCPHub + curated MCP servers (:3000)
#         .\install.ps1 ui          # LibreChat (:3080) + n8n (:5678)
#         .\install.ps1 share 3000  # HTTPS tunnel (Tailscale Serve, else ngrok)
#         .\install.ps1 help
#
# One-liner: irm https://tekt.md/install.ps1 | iex
# Tip: for the full Linux-parity experience, install WSL2 (wsl --install)
#      and run `bash install.sh` inside it.
# =============================================================================

param([string]$Command = "", [string]$Arg = "3000")

$ErrorActionPreference = "Continue"   # resilience over strictness — no single failure kills the run

# ── Output helpers ─────────────────────────────────────────────────────────────
function Log($m)     { Write-Host "[tekt] $m" -ForegroundColor Cyan }
function Success($m) { Write-Host "[OK]  $m" -ForegroundColor Green }
function Warn($m)    { Write-Host "[!]   $m" -ForegroundColor Yellow }
function Section($m) { Write-Host "`n== $m ==" -ForegroundColor Blue }

function Refresh-SessionPath {
    $paths = [System.Collections.Generic.List[string]]::new()
    foreach ($scope in "Machine", "User") {
        $value = [Environment]::GetEnvironmentVariable("Path", $scope)
        if ($value) {
            foreach ($part in ($value -split ";")) {
                if ($part -and -not $paths.Contains($part)) { $paths.Add($part) }
            }
        }
    }
    foreach ($part in @(
        $env:Path -split ";";
        (Join-Path $HOME ".local\bin");
        (Join-Path $HOME "AppData\Roaming\npm");
        (Join-Path $HOME "AppData\Local\Microsoft\WinGet\Links")
    )) {
        if ($part -and -not $paths.Contains($part)) { $paths.Add($part) }
    }
    $env:Path = $paths -join ";"
}

# ── Tekt instance layout ───────────────────────────────────────────────────────
$TektHome      = if ($env:TEKT_HOME) { $env:TEKT_HOME } else { Join-Path $HOME "Tekt" }
$TektInstance  = Join-Path $TektHome "Instances\$env:COMPUTERNAME"
$TektWorkspace = Join-Path $TektInstance "workspace"
$TektMcpDir    = Join-Path $TektInstance "mcp"
$TektCloudDir  = Join-Path $TektInstance "cloud"
$TektAgentsDir = Join-Path $TektInstance "agents"

# ── Catalog pins (tekt.catalog.yaml next to this script, if present) ──────────
$McpHubImage = "samanhappy/mcphub:latest"
$N8nImage    = "docker.n8n.io/n8nio/n8n:latest"
$catalogPath = Join-Path $PSScriptRoot "tekt.catalog.yaml"
if (Test-Path $catalogPath) {
    $cat = Get-Content $catalogPath -Raw
    if ($cat -match 'MCPHUB_IMAGE:\s*"([^"]+)"') { $McpHubImage = $Matches[1] }
    if ($cat -match 'N8N_IMAGE:\s*"([^"]+)"')    { $N8nImage    = $Matches[1] }
    Log "Loaded version pins from tekt.catalog.yaml"
}

function Test-Cmd($name) { [bool](Get-Command $name -ErrorAction SilentlyContinue) }
function Test-ClaudeDesktop {
    (Test-Path (Join-Path $env:LOCALAPPDATA "Programs\Claude\Claude.exe")) -or
    (Test-Path (Join-Path ${env:ProgramFiles} "Claude\Claude.exe"))
}

function Install-Winget($label, $id, $cmd) {
    Section $label
    if ($cmd -and (Test-Cmd $cmd)) { Success "$label already installed"; return }
    if (-not (Test-Cmd "winget")) {
        Warn "winget not found — install 'App Installer' from the Microsoft Store, then re-run."
        return
    }
    try {
        winget install --id $id -e --accept-source-agreements --accept-package-agreements
        Refresh-SessionPath
        Success "$label installed ($id)"
    } catch {
        Warn "$label install failed. Try:  winget search $label   — or install manually."
    }
}

# ── Native installers ──────────────────────────────────────────────────────────
function Install-ClaudeCode {
    Section "Claude Code"
    if (Test-Cmd "claude") { Success "Claude Code already installed"; return }
    try {
        irm https://claude.ai/install.ps1 | iex
        Refresh-SessionPath
        Success "Claude Code installed (native)"
    }
    catch {
        Warn "Native installer failed — trying npm..."
        if (Test-Cmd "npm") {
            npm install -g @anthropic-ai/claude-code
            Refresh-SessionPath
        }
        else { Warn "Install manually: irm https://claude.ai/install.ps1 | iex" }
    }
}

function Install-ClaudeDesktop {
    Section "Claude Desktop"
    if (Test-ClaudeDesktop) { Success "Claude Desktop already installed"; return }
    if (Test-Cmd "winget") {
        try {
            winget install --id Anthropic.Claude -e --accept-source-agreements --accept-package-agreements
            Success "Claude Desktop installed"
        } catch {
            Warn "Claude Desktop winget install failed. Install manually: https://claude.ai/download"
        }
    } else {
        Warn "winget not found. Install Claude Desktop manually: https://claude.ai/download"
    }
}

function Install-ZedAgent {
    Section "Zed (Agent)"
    if (Test-Cmd "zed") { Success "Zed already installed"; return }
    if (Test-Cmd "winget") {
        try {
            winget install --id ZedIndustries.Zed -e --accept-source-agreements --accept-package-agreements
            Success "Zed installed (open Zed and enable Agent mode in Assistant settings)"
        } catch {
            Warn "Zed winget install failed. Install manually: https://zed.dev/download"
        }
    } else {
        Warn "winget not found. Install Zed manually: https://zed.dev/download"
    }
}

function Install-OpenClaw {
    Section "OpenClaw"
    if (Test-Cmd "openclaw") { Success "OpenClaw already installed"; return }
    if (Test-Cmd "npm") {
        npm install -g openclaw@latest
        Refresh-SessionPath
        Log "Run 'openclaw onboard --install-daemon' to complete setup."
    } else { Warn "npm not found (install Node LTS first): npm install -g openclaw@latest" }
}

function Install-PicoClaw {
    Section "PicoClaw"
    if (Test-Cmd "picoclaw") { Success "PicoClaw already installed"; return }
    $bin = Join-Path $HOME ".local\bin"
    New-Item -ItemType Directory -Force -Path $bin | Out-Null
    $url = "https://github.com/sipeed/picoclaw/releases/latest/download/picoclaw-windows-amd64.exe"
    try {
        Invoke-WebRequest -Uri $url -OutFile (Join-Path $bin "picoclaw.exe")
        Refresh-SessionPath
        Success "PicoClaw installed to $bin (add it to PATH if needed)"
        Log "Run 'picoclaw onboard' to complete setup."
    } catch { Warn "Download failed ($url). See https://github.com/sipeed/picoclaw/releases" }
}

function Install-ZeroClaw {
    Section "ZeroClaw"
    if (Test-Cmd "zeroclaw") { Success "ZeroClaw already installed"; return }
    Warn "Grab the Windows x86_64 binary from the releases page:"
    Warn "  https://github.com/zeroclaw-labs/zeroclaw/releases/latest"
    Warn "Or build from source (Rust): cargo install --path . --locked"
    Log  "Then run: zeroclaw quickstart"
}

function Install-Nanobot {
    Section "Nanobot (HKUDS)"
    if (Test-Cmd "nanobot") { Success "Nanobot already installed"; return }
    if (Test-Cmd "pip") {
        pip install nanobot-ai
        Refresh-SessionPath
        Log "Run 'nanobot onboard' to configure. Upstream: github.com/HKUDS/nanobot"
        Log "(The Go MCP host at nanobot-ai/nanobot is a different project.)"
    } else { Warn "pip not found — install Python 3.11+ first, then: pip install nanobot-ai" }
}

function Install-NanoClaw {
    Section "NanoClaw"
    $dest = Join-Path $TektAgentsDir "nanoclaw"
    if (Test-Path (Join-Path $dest ".git")) { Success "NanoClaw already staged at $dest"; return }
    if (-not (Test-Cmd "git")) { Warn "git required to stage NanoClaw"; return }
    New-Item -ItemType Directory -Force -Path $TektAgentsDir | Out-Null
    git clone --depth 1 https://github.com/qwibitai/nanoclaw.git $dest
    Log "NanoClaw setup is Claude-Code-guided: cd $dest ; claude  → then /setup"
    Log "Requires Docker Desktop. WSL2 is the smoothest path on Windows."
}

function Install-Sovrant {
    Section "Sovrant"
    Log "Sovrant license: BSL 1.1 — source-available, not OSI open source (Apache-2.0 on 2029-05-15)."
    $dest = Join-Path $TektInstance "sovrant"

    if (Test-Path (Join-Path $dest ".git")) {
        Success "Sovrant already staged at $dest"
    } elseif (-not (Test-Cmd "git")) {
        Warn "git required to install Sovrant — skipping."
        return
    } else {
        New-Item -ItemType Directory -Force -Path $TektInstance | Out-Null
        git clone --depth 1 https://github.com/ramseur/sovrant.git $dest
        if (-not (Test-Path (Join-Path $dest ".git"))) { Warn "Sovrant clone failed — continuing."; return }
        Success "Sovrant cloned to $dest"
    }

    if (-not (Test-Cmd "dotnet")) {
        Warn "dotnet not found — skipping build. After installing .NET 10 SDK:"
        Warn "  cd $dest ; dotnet restore ; dotnet build"
        return
    }

    Log "Building Sovrant (dotnet restore; dotnet build) — first build can take a few minutes..."
    Push-Location $dest
    try {
        dotnet restore
        dotnet build
        Success "Sovrant built"
        Log "Run from ${dest}:"
        Log '  Desktop:  Start-Process dotnet -ArgumentList "run --project src/Sovrant.Desktop" -WindowStyle Hidden'
        Log "  Web UI:   dotnet run --project src/Sovrant.Web        # http://localhost:5100"
        Log "  Server:   dotnet run --project src/Sovrant.Server     # http://localhost:5200 (OpenAI-compatible)"
        Log '  MCP/HTTP: $env:SOVRANT_MCP_HTTP="true"; dotnet run --project src/Sovrant.Server   # MCP at :5200/mcp'
    } catch {
        Warn "Sovrant build failed — see output above; continuing."
    } finally {
        Pop-Location
    }
}

# ── tekt.cloud scaffolds ───────────────────────────────────────────────────────
function Setup-McpHub {
    Section "MCPHub + curated MCP servers"
    New-Item -ItemType Directory -Force -Path $TektMcpDir, $TektWorkspace | Out-Null

    $settings = Join-Path $TektMcpDir "mcp_settings.json"
    if (-not (Test-Path $settings)) {
@'
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/workspace"]
    },
    "fetch": { "command": "uvx", "args": ["mcp-server-fetch"] },
    "memory": { "command": "npx", "args": ["-y", "@modelcontextprotocol/server-memory"] },
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": { "GITHUB_PERSONAL_ACCESS_TOKEN": "set-me" }
    }
  }
}
'@ | Set-Content -Path $settings -Encoding UTF8
        Success "Wrote curated MCP config -> $settings"
    }

    $compose = Join-Path $TektMcpDir "docker-compose.yml"
    if (-not (Test-Path $compose)) {
@"
services:
  mcphub:
    image: $McpHubImage
    ports: ["3000:3000"]
    volumes:
      - ./mcp_settings.json:/app/mcp_settings.json
      - ../workspace:/workspace
    restart: unless-stopped
"@ | Set-Content -Path $compose -Encoding UTF8
        Success "Wrote $compose"
    }

    if (Test-Cmd "docker") {
        Push-Location $TektMcpDir; docker compose up -d; Pop-Location
        Success "MCPHub up — http://localhost:3000 (admin/admin123 — CHANGE IT)"
        Log "Clients connect to: http://localhost:3000/mcp"
        Log "HTTPS in one step:  .\install.ps1 share 3000"
    } else {
        Warn "Docker Desktop not running/installed — start later with: cd $TektMcpDir ; docker compose up -d"
    }
}

function Setup-Ui {
    Section "LibreChat"
    $lc = Join-Path $TektCloudDir "librechat"
    New-Item -ItemType Directory -Force -Path $TektCloudDir | Out-Null
    if (-not (Test-Path (Join-Path $lc ".git"))) {
        git clone --depth 1 https://github.com/danny-avila/LibreChat.git $lc
    }
    if ((Test-Path (Join-Path $lc ".env.example")) -and -not (Test-Path (Join-Path $lc ".env"))) {
        Copy-Item (Join-Path $lc ".env.example") (Join-Path $lc ".env")
    }
    $lcy = Join-Path $lc "librechat.yaml"
    if (-not (Test-Path $lcy)) {
@'
version: 1.2.1
mcpServers:
  tekt:
    type: streamable-http
    url: http://host.docker.internal:3000/mcp
'@ | Set-Content -Path $lcy -Encoding UTF8
@'
services:
  api:
    volumes:
      - ./librechat.yaml:/app/librechat.yaml
'@ | Set-Content -Path (Join-Path $lc "docker-compose.override.yml") -Encoding UTF8
        Success "Wired LibreChat -> MCPHub"
    }
    if (Test-Cmd "docker") {
        Push-Location $lc; docker compose up -d; Pop-Location
        Success "LibreChat up — http://localhost:3080"
    } else { Warn "Start later: cd $lc ; docker compose up -d" }

    Section "n8n"
    $n8n = Join-Path $TektCloudDir "n8n"
    New-Item -ItemType Directory -Force -Path $n8n | Out-Null
    $nc = Join-Path $n8n "docker-compose.yml"
    if (-not (Test-Path $nc)) {
@"
services:
  n8n:
    image: $N8nImage
    ports: ["5678:5678"]
    environment:
      - N8N_SECURE_COOKIE=false
    volumes:
      - n8n_data:/home/node/.n8n
    restart: unless-stopped
volumes:
  n8n_data:
"@ | Set-Content -Path $nc -Encoding UTF8
    }
    if (Test-Cmd "docker") {
        Push-Location $n8n; docker compose up -d; Pop-Location
        Success "n8n up — http://localhost:5678 (MCP Client Tool -> http://host.docker.internal:3000/mcp)"
    } else { Warn "Start later: cd $n8n ; docker compose up -d" }
    Log "n8n license: Sustainable Use License (fair-code, not OSI open source)."
    Log "Wire-up guide: https://tekt.md/04-interface/"
}

function Tekt-Share($port) {
    Section "Share localhost:$port over HTTPS"
    if ((Test-Cmd "tailscale") -and (& tailscale status 2>$null)) {
        tailscale serve --bg $port
        Success "Serving :$port inside your tailnet. Public instead? tailscale funnel --bg $port"
    } elseif (Test-Cmd "ngrok") {
        Log "No tailnet — using ngrok (Ctrl-C to stop)..."
        ngrok http $port
    } else {
        Warn "Install Tailscale (winget install tailscale.tailscale) or ngrok (winget install Ngrok.Ngrok) first."
    }
}

# ── Status ─────────────────────────────────────────────────────────────────────
function Tekt-Status {
    Write-Host "`nTekt Environment Status — https://tekt.md`n" -ForegroundColor Cyan
    $rows = @(
        @("Tekt.Dev",  "Git",         "git"),
        @("Tekt.Dev",  "Go",          "go"),
        @("Tekt.Dev",  "Python",      "python"),
        @("Tekt.Dev",  "Node.js",     "node"),
        @("Tekt.Dev",  "VS Code",     "code"),
        @("Tekt.Dev",  "Docker",      "docker"),
        @("Tekt.Dev",  ".NET SDK",    "dotnet"),
        @("Tekt.Base", "rclone",      "rclone"),
        @("Tekt.Base", "AWS CLI",     "aws"),
        @("Tekt.Edge", "Tailscale",   "tailscale"),
        @("Tekt.Edge", "ngrok",       "ngrok"),
        @("Tekt.Iris", "Ollama",      "ollama"),
        @("Tekt.Iris", "Claude Code", "claude"),
        @("Tekt.Iris", "Zed (Agent)", "zed"),
        @("Tekt.Iris", "OpenClaw",    "openclaw"),
        @("Tekt.Iris", "PicoClaw",    "picoclaw"),
        @("Tekt.Iris", "ZeroClaw",    "zeroclaw"),
        @("Tekt.Iris", "Nanobot",     "nanobot")
    )
    $installed = 0; $missing = 0
    foreach ($r in $rows) {
        if (Test-Cmd $r[2]) { Write-Host ("  [OK]  {0,-10} {1}" -f $r[0], $r[1]) -ForegroundColor Green; $installed++ }
        else                { Write-Host ("  [ X]  {0,-10} {1}" -f $r[0], $r[1]) -ForegroundColor Red;   $missing++ }
    }
    if (Test-ClaudeDesktop) { Write-Host "  [OK]  Tekt.Iris  Claude Desktop" -ForegroundColor Green; $installed++ }
    else { Write-Host "  [ X]  Tekt.Iris  Claude Desktop" -ForegroundColor Red; $missing++ }
    Write-Host ("  [--]  Tekt.Iris  Hermes Agent — WSL2 only (wsl --install, then bash install.sh)") -ForegroundColor Yellow
    if (Test-Path (Join-Path $TektAgentsDir "nanoclaw\.git")) { Write-Host "  [OK]  Tekt.Iris  NanoClaw (staged)" -ForegroundColor Green }
    if (Test-Path (Join-Path $TektInstance "sovrant\.git")) {
        if (Test-Path (Join-Path $TektInstance "sovrant\src\Sovrant.Web\bin")) {
            Write-Host "  [OK]  Tekt.Cloud Sovrant built (BSL 1.1) — Web :5100, Server :5200" -ForegroundColor Green
        } else {
            Write-Host "  [ ?]  Tekt.Cloud Sovrant cloned, not built — cd $TektInstance\sovrant ; dotnet build" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [ ?]  Tekt.Cloud Sovrant not staged (BSL 1.1) — .\install.ps1 installs it" -ForegroundColor Yellow
    }
    if (Test-Cmd "docker") {
        foreach ($svc in @(@("MCPHub","mcphub","http://localhost:3000"), @("LibreChat","librechat","http://localhost:3080"), @("n8n","n8n","http://localhost:5678"))) {
            $up = docker ps --format "{{.Image}} {{.Names}}" 2>$null | Select-String -Quiet $svc[1]
            if ($up) { Write-Host ("  [OK]  Tekt.Cloud {0} running — {1}" -f $svc[0], $svc[2]) -ForegroundColor Green }
            else     { Write-Host ("  [ ?]  Tekt.Cloud {0} not running" -f $svc[0]) -ForegroundColor Yellow }
        }
    }
    Write-Host "`n  $installed installed / $missing missing`n"
    if ($missing -gt 0) { Log "Run '.\install.ps1' to install everything." }
    Log "If tools were just installed, pause and restart PowerShell, then run '.\install.ps1 status' again."
}

# ── Main ───────────────────────────────────────────────────────────────────────
function Main {
    Write-Host "`nTekt Bootstrap Installer (Windows) — https://tekt.md`n" -ForegroundColor Cyan
    Refresh-SessionPath
    Log "Tip: WSL2 gives full Linux parity — wsl --install, then bash install.sh"

    # Tekt.Dev
    Install-Winget "Git"            "Git.Git"                    "git"
    Install-Winget "Go"             "GoLang.Go"                  "go"
    Install-Winget "Python 3.12"    "Python.Python.3.12"         "python"
    Install-Winget "Node.js LTS"    "OpenJS.NodeJS.LTS"          "node"
    Install-Winget "VS Code"        "Microsoft.VisualStudioCode" "code"
    Install-Winget "Docker Desktop" "Docker.DockerDesktop"       "docker"
    Install-Winget ".NET 10 SDK"    "Microsoft.DotNet.SDK.10"    "dotnet"
    # Tekt.Base
    Install-Winget "rclone"         "Rclone.Rclone"              "rclone"
    Install-Winget "AWS CLI"        "Amazon.AWSCLI"              "aws"
    # Tekt.Edge
    Install-Winget "Tailscale"      "tailscale.tailscale"        "tailscale"
    Install-Winget "ngrok"          "Ngrok.Ngrok"                "ngrok"
    # Tekt.Iris
    Install-Winget "Ollama"         "Ollama.Ollama"              "ollama"
    Install-ClaudeCode
    Install-ClaudeDesktop
    Install-ZedAgent
    Install-OpenClaw
    Install-PicoClaw
    Install-ZeroClaw
    Install-Nanobot
    Install-NanoClaw
    Section "Hermes Agent"
    Warn "Hermes has no native Windows build — use WSL2: wsl --install, then bash install.sh"
    # Tekt.Cloud
    Install-Sovrant

    Write-Host ""
    Log "Staged (tekt.cloud): bring up with  .\install.ps1 mcp   and   .\install.ps1 ui"
    Log "PATH is refreshed during install. If a new command still isn't found, open a new PowerShell window, then run:  .\install.ps1 status"
}

switch ($Command) {
    "status" { Tekt-Status }
    "mcp"    { Setup-McpHub }
    "ui"     { Setup-Ui }
    "share"  { Tekt-Share $Arg }
    "help"   {
        Write-Host "Usage: .\install.ps1 [status|catalog|mcp|ui|share <port>|help]"
        Write-Host "  (none)        Install all Tekt tools"
        Write-Host "  status        Check which tools are installed"
        Write-Host "  mcp           MCPHub + curated MCP servers (:3000)"
        Write-Host "  ui            LibreChat (:3080) + n8n (:5678)"
        Write-Host "  share <port>  HTTPS tunnel (Tailscale Serve, else ngrok)"
        Write-Host ""
        Write-Host "Windows note: after installs, restart PowerShell, then run .\install.ps1 status"
    }
    "catalog" {
        if (Test-Path $catalogPath) { Get-Content $catalogPath }
        else { irm https://tekt.md/tekt.catalog.yaml }
    }
    default  { Main }
}
