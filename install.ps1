# =============================================================================
# install.ps1
# Tekt Platform - Windows Bootstrap (PowerShell)
# https://tekt.md
#
# Installs (winget): Git, Go, Python, Node LTS, VS Code, Docker Desktop,
#                    rclone, AWS CLI, Tailscale, ngrok, Ollama
# Installs (native): Claude Code, Claude Desktop, Zed Agent, OpenClaw, PicoClaw, ZeroClaw, Nanobot
# Stages:            NanoClaw (WSL2/Docker), MCPHub, LibreChat, n8n
# Not on Windows:    Hermes Agent (use WSL2 -> bash install.sh)
#
# Usage:  .\install.ps1              # full install
#         .\install.ps1 status      # environment check
#         .\install.ps1 mcp         # MCPHub + curated MCP servers (:3000)
#         .\install.ps1 ui          # LibreChat (:3080) + n8n (:5678)
#         .\install.ps1 share 3000  # HTTPS tunnel (Tailscale Serve, else ngrok)
#         .\install.ps1 cli         # install the `tekt` command (~\.local\bin)
#         .\install.ps1 help
#
# Spaces - share docs, knowledge and skills through the storage you already use
# (Google Drive, OneDrive, Dropbox, Box, Nextcloud, a folder/NAS), synced by rclone:
#         tekt space add <name> [provider] [folder]   # create or join a Space
#         tekt space list                             # show your Spaces
#         tekt space sync [name]                      # two-way sync now
#         tekt space remove <name>                    # disconnect (files are kept)
#         tekt space autosync on|off                  # sync every 10 minutes
#
# Connect - let your AI apps use your Spaces (MCP filesystem server "tekt-spaces"):
#         tekt connect [app]    # all (default), claude-code, claude-desktop, codex
#
# Shared skills - skills in a Space appear in everyone's Claude Code:
#         tekt skill list                 # skills in your Spaces, and which are linked
#         tekt skill new <space> <name>   # start a skill; everyone gets it after sync
#         tekt skill link                 # re-link shared skills into Claude Code
#
# One-liner: irm https://tekt.md/install.ps1 | iex
# Tip: for the full Linux-parity experience, install WSL2 (wsl --install)
#      and run `bash install.sh` inside it.
# =============================================================================

param([Parameter(Position = 0)][string]$Command = "", [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest = @())

$ErrorActionPreference = "Continue"   # resilience over strictness - no single failure kills the run

if ($null -eq $Rest) { $Rest = @() }
$Arg      = if ($Rest.Count -ge 1) { $Rest[0] } else { "3000" }   # share <port>
$TektSelf = $PSCommandPath                                        # empty when run via irm | iex

# -- Output helpers -------------------------------------------------------------
function Log($m)     { Write-Host "[tekt] $m" -ForegroundColor Cyan }
function Success($m) { Write-Host "[OK]  $m" -ForegroundColor Green }
function Warn($m)    { Write-Host "[!]   $m" -ForegroundColor Yellow }
function Err($m)     { Write-Host "[X]   $m" -ForegroundColor Red }
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

# -- Tekt instance layout -------------------------------------------------------
$TektHome      = if ($env:TEKT_HOME) { $env:TEKT_HOME } else { Join-Path $HOME "Tekt" }
$TektInstance  = Join-Path $TektHome "Instances\$env:COMPUTERNAME"
$TektWorkspace = Join-Path $TektInstance "workspace"
$TektMcpDir    = Join-Path $TektInstance "mcp"
$TektCloudDir  = Join-Path $TektInstance "cloud"
$TektAgentsDir = Join-Path $TektInstance "agents"
$TektSpaces    = if ($env:TEKT_SPACES) { $env:TEKT_SPACES } else { Join-Path $TektHome "Spaces" }
$TektBin       = Join-Path $HOME ".local\bin"
$TektCliPs1    = Join-Path $TektBin "tekt.ps1"
$TektMcpName   = "tekt-spaces"
$TektMcpPkg    = "@modelcontextprotocol/server-filesystem"
$TektClaudeSkills = if ($env:TEKT_CLAUDE_SKILLS) { $env:TEKT_CLAUDE_SKILLS } else { Join-Path (Join-Path $HOME ".claude") "skills" }
$EmDash        = [string][char]0x2014   # built from char codes so the file parses the same under any encoding
$MidDot        = [string][char]0x00B7

# -- Catalog pins (tekt.catalog.yaml next to this script, if present) ----------
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
        Warn "winget not found - install 'App Installer' from the Microsoft Store, then re-run."
        return
    }
    try {
        winget install --id $id -e --accept-source-agreements --accept-package-agreements
        Refresh-SessionPath
        Success "$label installed ($id)"
    } catch {
        Warn "$label install failed. Try:  winget search $label   - or install manually."
    }
}

# -- Native installers ----------------------------------------------------------
function Install-ClaudeCode {
    Section "Claude Code"
    if (Test-Cmd "claude") { Success "Claude Code already installed"; return }
    try {
        irm https://claude.ai/install.ps1 | iex
        Refresh-SessionPath
        Success "Claude Code installed (native)"
    }
    catch {
        Warn "Native installer failed - trying npm..."
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
    } else { Warn "pip not found - install Python 3.11+ first, then: pip install nanobot-ai" }
}

function Install-NanoClaw {
    Section "NanoClaw"
    $dest = Join-Path $TektAgentsDir "nanoclaw"
    if (Test-Path (Join-Path $dest ".git")) { Success "NanoClaw already staged at $dest"; return }
    if (-not (Test-Cmd "git")) { Warn "git required to stage NanoClaw"; return }
    New-Item -ItemType Directory -Force -Path $TektAgentsDir | Out-Null
    git clone --depth 1 https://github.com/qwibitai/nanoclaw.git $dest
    Log "NanoClaw setup is Claude-Code-guided: cd $dest ; claude  -> then /setup"
    Log "Requires Docker Desktop. WSL2 is the smoothest path on Windows."
}

function Install-Sovrant {
    Section "Sovrant"
    Log "Sovrant license: BSL 1.1 - source-available, not OSI open source (Apache-2.0 on 2029-05-15)."
    $dest = Join-Path $TektInstance "sovrant"

    if (Test-Path (Join-Path $dest ".git")) {
        Success "Sovrant already staged at $dest"
    } elseif (-not (Test-Cmd "git")) {
        Warn "git required to install Sovrant - skipping."
        return
    } else {
        New-Item -ItemType Directory -Force -Path $TektInstance | Out-Null
        git clone --depth 1 https://github.com/ramseur/sovrant.git $dest
        if (-not (Test-Path (Join-Path $dest ".git"))) { Warn "Sovrant clone failed - continuing."; return }
        Success "Sovrant cloned to $dest"
    }

    if (-not (Test-Cmd "dotnet")) {
        Warn "dotnet not found - skipping build. After installing .NET 10 SDK:"
        Warn "  cd $dest ; dotnet restore ; dotnet build"
        return
    }

    Log "Building Sovrant (dotnet restore; dotnet build) - first build can take a few minutes..."
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
        Warn "Sovrant build failed - see output above; continuing."
    } finally {
        Pop-Location
    }
}

# -- tekt.cloud scaffolds -------------------------------------------------------
function Setup-McpHub {
    Section "MCPHub + curated MCP servers"
    New-Item -ItemType Directory -Force -Path $TektMcpDir, $TektWorkspace, $TektSpaces | Out-Null

    $settings = Join-Path $TektMcpDir "mcp_settings.json"
    if (-not (Test-Path $settings)) {
@'
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/workspace", "/spaces"]
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
    $spacesPosix = $TektSpaces -replace '\\', '/'   # Docker Desktop accepts C:/Users/... paths
    if (-not (Test-Path $compose)) {
@"
services:
  mcphub:
    image: $McpHubImage
    ports: ["3000:3000"]
    volumes:
      - ./mcp_settings.json:/app/mcp_settings.json
      - ../workspace:/workspace
      - "${spacesPosix}:/spaces"
    restart: unless-stopped
"@ | Set-Content -Path $compose -Encoding UTF8
        Success "Wrote $compose"
    }

    if (Test-Cmd "docker") {
        Push-Location $TektMcpDir; docker compose up -d; Pop-Location
        Success "MCPHub up - http://localhost:3000 (admin/admin123 - CHANGE IT)"
        Log "Clients connect to: http://localhost:3000/mcp"
        Log "HTTPS in one step:  .\install.ps1 share 3000"
    } else {
        Warn "Docker Desktop not running/installed - start later with: cd $TektMcpDir ; docker compose up -d"
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
        Success "LibreChat up - http://localhost:3080"
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
        Success "n8n up - http://localhost:5678 (MCP Client Tool -> http://host.docker.internal:3000/mcp)"
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
        Log "No tailnet - using ngrok (Ctrl-C to stop)..."
        ngrok http $port
    } else {
        Warn "Install Tailscale (winget install tailscale.tailscale) or ngrok (winget install Ngrok.Ngrok) first."
    }
}

# -- tekt command (CLI) ---------------------------------------------------------
function Install-TektCli {
    Section "tekt command"
    New-Item -ItemType Directory -Force -Path $TektBin | Out-Null
    $ok = $false
    if ($TektSelf -and (Test-Path -LiteralPath $TektSelf)) {
        if ([IO.Path]::GetFullPath($TektSelf) -ieq [IO.Path]::GetFullPath($TektCliPs1)) {
            $ok = $true   # already running as the installed tekt command
        } else {
            try { Copy-Item -LiteralPath $TektSelf -Destination $TektCliPs1 -Force -ErrorAction Stop; $ok = $true }
            catch { Warn "Couldn't copy the installer to $TektCliPs1." }
        }
    } else {
        try {
            Invoke-WebRequest -Uri "https://tekt.md/install.ps1" -OutFile $TektCliPs1 -UseBasicParsing -ErrorAction Stop
            $ok = $true
        } catch { Warn "Couldn't download https://tekt.md/install.ps1 $EmDash check your internet connection and try again." }
    }
    if (-not $ok) { return }

    $shim = Join-Path $TektBin "tekt.cmd"
    $shimText = '@powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tekt.ps1" %*' + "`r`n"
    try { [IO.File]::WriteAllText($shim, $shimText, (New-Object System.Text.ASCIIEncoding)) }
    catch { Warn "Couldn't write $shim."; return }

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $parts = @(); if ($userPath) { $parts = @($userPath -split ";") }
    $onPath = @($parts | Where-Object { $_ -and ($_.TrimEnd('\') -ieq $TektBin.TrimEnd('\')) }).Count -gt 0
    if (-not $onPath) {
        $newPath = if ($userPath) { $userPath.TrimEnd(';') + ";" + $TektBin } else { $TektBin }
        try {
            [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
            Log "Added $TektBin to your PATH (new PowerShell windows will pick it up)."
        } catch { Warn "Couldn't add $TektBin to your PATH $EmDash add it in Settings > System > About > Advanced system settings." }
    }
    Refresh-SessionPath
    Success "tekt command ready: $shim  (try: tekt help)"
}

# -- Spaces: shared docs, knowledge and skills over storage you already use -----
function ConvertTo-SpaceName($raw) {
    $n = ([string]$raw).ToLowerInvariant()
    $n = $n -creplace '[^a-z0-9-]+', '-'
    return $n.Trim('-')
}

function Get-SpaceBackend($provider) {
    switch -Regex (([string]$provider).Trim().ToLowerInvariant()) {
        '^(drive|gdrive|google|googledrive|google-drive)$' { return "drive" }
        '^(onedrive|microsoft|sharepoint)$'                { return "onedrive" }
        '^dropbox$'                                        { return "dropbox" }
        '^box$'                                            { return "box" }
        '^(nextcloud|owncloud|webdav)$'                    { return "webdav" }
        '^(folder|local|nas|path)$'                        { return "alias" }
        '^(s3|minio|r2|b2)$'                               { return "s3" }
    }
    return ""
}

function Get-SpaceLabel($backend) {
    switch ($backend) {
        "drive"    { return "Google Drive" }
        "onedrive" { return "OneDrive" }
        "dropbox"  { return "Dropbox" }
        "box"      { return "Box" }
        "webdav"   { return "Nextcloud / WebDAV" }
        "alias"    { return "a folder" }
        "s3"       { return "S3" }
    }
    return ""
}

function Get-UtcNow {
    [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
}

function Get-SpaceMeta($dir, $key) {
    $file = Join-Path $dir ".tekt-space"
    if (-not (Test-Path -LiteralPath $file)) { return "" }
    foreach ($line in [IO.File]::ReadAllLines($file)) {
        if ($line.StartsWith("$key=")) { return $line.Substring($key.Length + 1).Trim() }
    }
    return ""
}

function Set-SpaceMeta($dir, $key, $value) {
    $file  = Join-Path $dir ".tekt-space"
    $lines = [System.Collections.Generic.List[string]]::new()
    $found = $false
    if (Test-Path -LiteralPath $file) {
        foreach ($line in [IO.File]::ReadAllLines($file)) {
            if ($line.StartsWith("$key=")) {
                if (-not $found) { $lines.Add("$key=$value"); $found = $true }
            } elseif ($line -ne "") {
                $lines.Add($line)
            }
        }
    }
    if (-not $found) { $lines.Add("$key=$value") }
    [IO.File]::WriteAllLines($file, $lines.ToArray(), (New-Object System.Text.UTF8Encoding $false))
}

# Full paths of every Space folder (a folder under $TektSpaces with a .tekt-space file)
function Get-SpaceDirs {
    if (-not (Test-Path -LiteralPath $TektSpaces)) { return }
    Get-ChildItem -LiteralPath $TektSpaces -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName ".tekt-space") } |
        ForEach-Object { $_.FullName }
}

function Test-Rclone {
    if (Test-Cmd "rclone") { return $true }
    Install-Winget "rclone" "Rclone.Rclone" "rclone" | Out-Host   # keep winget output out of the return value
    Refresh-SessionPath
    if (Test-Cmd "rclone") { return $true }
    Err "Spaces need rclone, and it isn't installed. Install it with:  winget install Rclone.Rclone"
    return $false
}

function Space-Add($rawName, $provider, $folder) {
    Section "Add a Space"
    if (-not $rawName) { $rawName = Read-Host "Name for this Space (e.g. team, family, research)" }
    $name = ConvertTo-SpaceName $rawName
    if (-not $name) { Err "A Space needs a name made of letters or numbers, e.g.  tekt space add team drive"; return }
    $dir    = Join-Path $TektSpaces $name
    $remote = "tekt-$name"

    if (-not (Test-Rclone)) { return }

    if (Test-Path -LiteralPath (Join-Path $dir ".tekt-space")) {
        Warn "Space '$name' already exists at $dir $EmDash syncing it instead."
        Space-Sync $name
        return
    }

    if (-not $provider) {
        Write-Host ""
        Write-Host "Where should the Space '$name' live?"
        Write-Host "  1) Google Drive  2) OneDrive / SharePoint  3) Dropbox  4) Box  5) Nextcloud"
        Write-Host "  6) A folder on this computer or a network drive  7) S3 (advanced)"
        $choice = ([string](Read-Host "Pick 1-7")).Trim()
        $provider = switch ($choice) {
            "1"     { "drive" }
            "2"     { "onedrive" }
            "3"     { "dropbox" }
            "4"     { "box" }
            "5"     { "nextcloud" }
            "6"     { "folder" }
            "7"     { "s3" }
            default { $choice }
        }
    }
    $provider = ([string]$provider).Trim()
    $backend  = Get-SpaceBackend $provider
    if (-not $backend) {
        Err "Tekt doesn't know '$provider'. Use one of: drive, onedrive, dropbox, box, nextcloud, folder, s3"
        return
    }
    $label = Get-SpaceLabel $backend

    # Connect the storage (an rclone remote named tekt-<name>), unless it already exists
    $remotes = @(& rclone listremotes 2>$null | ForEach-Object { ([string]$_).Trim() })
    if ($remotes -contains "${remote}:") {
        Log "Using your existing connection '$remote'."
    } else {
        switch ($backend) {
            "alias" {
                $path = [string]$folder
                if (-not $path) { $path = Read-Host "Folder to share (e.g. D:\Shared\Tekt or \\nas\team)" }
                $path = ([string]$path).Trim().Trim('"')
                if (-not $path) { Err "No folder given. Try again: tekt space add $name folder `"D:\Shared\Tekt`""; return }
                if ($path -eq "~") { $path = $HOME }
                elseif ($path -match '^~[\\/]') { $path = Join-Path $HOME $path.Substring(2) }
                if (-not (Test-Path -LiteralPath $path)) { New-Item -ItemType Directory -Force -Path $path | Out-Null }
                if (-not (Test-Path -LiteralPath $path)) { Err "Couldn't find or create the folder $path"; return }
                $path = (Resolve-Path -LiteralPath $path).ProviderPath
                & rclone config create $remote alias "remote=$path" | Out-Null
                if ($LASTEXITCODE -ne 0) { Err "Couldn't connect the folder $path. Try again: tekt space add $name $provider"; return }
            }
            "webdav" {
                Log "Use an app password, not your normal password: in Nextcloud open Settings > Security and create a new app password."
                $address = ([string](Read-Host "Nextcloud address (e.g. https://cloud.example.com)")).Trim()
                if (-not $address) { Err "No address given. Try again: tekt space add $name $provider"; return }
                if ($address -notmatch '^https?://') { $address = "https://$address" }
                $ncUser = ([string](Read-Host "Nextcloud username")).Trim()
                $secure = Read-Host "App password" -AsSecureString
                $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
                try { $ncPass = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
                finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
                $url = $address.TrimEnd('/') + "/remote.php/dav/files/" + $ncUser
                & rclone config create $remote webdav "url=$url" "vendor=nextcloud" "user=$ncUser" "pass=$ncPass" --obscure | Out-Null
                $ncPass = $null
                if ($LASTEXITCODE -ne 0) {
                    & rclone config delete $remote 2>$null | Out-Null
                    Err "Couldn't connect to Nextcloud. Check the address, username and app password, then try again: tekt space add $name $provider"
                    return
                }
            }
            "s3" {
                Log "rclone will now ask for your S3 endpoint and access keys."
                & rclone config create $remote s3 --all
                if ($LASTEXITCODE -ne 0) {
                    & rclone config delete $remote 2>$null | Out-Null
                    Err "S3 setup didn't finish. Try again: tekt space add $name $provider"
                    return
                }
            }
            default {
                Log "Your browser will open so you can sign in to $label. Tekt never sees your password."
                & rclone config create $remote $backend
                if ($LASTEXITCODE -ne 0) {
                    & rclone config delete $remote 2>$null | Out-Null
                    Err "Sign-in didn't finish. Try again: tekt space add $name $provider"
                    return
                }
            }
        }
        Success "Connected to $label as '$remote'"
    }

    # Folder inside the storage (the alias already points at the folder itself)
    if ($backend -eq "alias") {
        $folder = ""
    } else {
        if (-not $folder) {
            if ($backend -eq "s3") { $folder = Read-Host "Bucket and folder (e.g. my-bucket/tekt/$name)" }
            else                   { $folder = "Tekt/$name" }
        }
        $folder = (([string]$folder).Trim().Trim('"') -replace '\\', '/').Trim('/')
        if (-not $folder) { Err "No bucket or folder given. Try again: tekt space add $name $provider"; return }
    }

    # Local copy: docs\ knowledge\ skills\ + README.md + .tekt-space
    foreach ($sub in "docs", "knowledge", "skills") {
        New-Item -ItemType Directory -Force -Path (Join-Path $dir $sub) | Out-Null
    }
    # Only write README.md when neither side has one: a joiner's fresh copy would carry a
    # different modtime than the creator's and make the first bisync --resync abort.
    # A failed lsf (remote folder doesn't exist yet) counts as "no README".
    $readme = Join-Path $dir "README.md"
    $needReadme = -not (Test-Path -LiteralPath $readme)
    if ($needReadme) {
        $remoteFiles = @(& rclone lsf "${remote}:$folder" --files-only --max-depth 1 2>$null)
        if (@($remoteFiles | Where-Object { ([string]$_).Trim() -ceq "README.md" }).Count -gt 0) { $needReadme = $false }
    }
    if ($needReadme) {
        $readmeLines = @(
            "# $name $EmDash a Tekt Space",
            "",
            "This folder is shared between people and their AI tools with Tekt (https://tekt.md/spaces/).",
            "Everyone who has it keeps a synced copy on their own computer.",
            "",
            "- docs/       Documents you want your AI and your colleagues to read",
            "- knowledge/  Notes, decisions and reference material worth keeping",
            "- skills/     Skills for AI agents: one folder per skill, each with a SKILL.md",
            "",
            "Join it from your computer:  tekt space add $name <drive|onedrive|dropbox|box|nextcloud|folder>"
        )
        # LF line endings so the synced README is byte-identical to one made by install.sh
        [IO.File]::WriteAllText($readme, (($readmeLines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding $false))
    }
    $meta = @("name=$name", "provider=$provider", "remote=$remote", "folder=$folder", "created=$(Get-UtcNow)", "initialized=0")
    [IO.File]::WriteAllLines((Join-Path $dir ".tekt-space"), [string[]]$meta, (New-Object System.Text.UTF8Encoding $false))

    & rclone mkdir "${remote}:$folder" 2>$null | Out-Null
    Space-Sync $name

    Write-Host ""
    Success "Space '$name' is ready: $dir"
    Log "Put files in docs\, notes in knowledge\, and skill folders in skills\."
    if ($backend -ne "alias") {
        Log "Invite people: in $label, share the folder '$folder' like any other folder."
        Log "They run:  tekt space add $name $provider `"$folder`""
        if ($backend -eq "drive") { Log "  (Folder shared with them? Add a shortcut to it in My Drive first.)" }
    }
    Log "Let your AI apps use it:        tekt connect"
    Log "Keep it in sync automatically:  tekt space autosync on"
}

function Space-Sync($only) {
    $dirs = @(Get-SpaceDirs)
    if ($dirs.Count -eq 0) { Log "No Spaces yet. Add one:  tekt space add team drive"; return }
    if ($only) {
        $want = ConvertTo-SpaceName $only
        $dirs = @($dirs | Where-Object { (Split-Path $_ -Leaf) -eq $want })
        if ($dirs.Count -eq 0) { Err "No Space named '$only'. See: tekt space list"; return }
    }
    if (-not (Test-Cmd "rclone")) {
        Err "Spaces need rclone, and it isn't installed. Install it with:  winget install Rclone.Rclone"
        return
    }

    $flags = @("--create-empty-src-dirs",
               "--exclude", "/.tekt-space",
               "--exclude", ".DS_Store",
               "--exclude", "Thumbs.db",
               "--exclude", '~$*',
               "--exclude", "*.tmp")
    $resyncFlags = @("--resync")
    $bisyncHelp = (& rclone bisync --help 2>&1 | Out-String)
    if ($bisyncHelp.Contains("--conflict-resolve")) {
        $flags += @("--conflict-resolve", "newer", "--conflict-loser", "num", "--resilient", "--recover", "--max-lock", "2m")
    }
    if ($bisyncHelp.Contains("--resync-mode")) {
        $resyncFlags += @("--resync-mode", "newer")   # first sync: the newer copy of a file wins
    }

    foreach ($dir in $dirs) {
        $name   = Split-Path $dir -Leaf
        $remote = Get-SpaceMeta $dir "remote"
        if (-not $remote) { $remote = "tekt-$name" }
        $folder = Get-SpaceMeta $dir "folder"
        $rcArgs = @("bisync", "${remote}:$folder", $dir) + $flags
        if ((Get-SpaceMeta $dir "initialized") -ne "1") { $rcArgs += $resyncFlags }
        $rcArgs += "-q"
        Log "Syncing $name..."
        & rclone @rcArgs
        if ($LASTEXITCODE -eq 0) {
            Set-SpaceMeta $dir "initialized" "1"
            Set-SpaceMeta $dir "last_sync" (Get-UtcNow)
            Success "$name is up to date"
            Link-SpaceSkills $name
        } else {
            Warn "$name didn't sync. If it keeps failing, reset it with: rclone bisync ${remote}:$folder `"$dir`" --resync"
        }
    }
}

function Space-List {
    $dirs = @(Get-SpaceDirs)
    if ($dirs.Count -eq 0) { Log "No Spaces yet. Add one:  tekt space add team drive"; return }
    Write-Host ""
    foreach ($dir in $dirs) {
        $name  = Split-Path $dir -Leaf
        $prov  = Get-SpaceMeta $dir "provider"
        $label = Get-SpaceLabel (Get-SpaceBackend $prov)
        if (-not $label) { $label = $prov }
        $last  = Get-SpaceMeta $dir "last_sync"
        if (-not $last) { $last = "never" }
        $docs   = @(Get-ChildItem -LiteralPath (Join-Path $dir "docs") -File -Recurse -Force -ErrorAction SilentlyContinue).Count
        $skills = @(Get-ChildItem -LiteralPath (Join-Path $dir "skills") -Directory -Force -ErrorAction SilentlyContinue).Count
        Write-Host ("  {0,-16} {1,-20} {2}" -f $name, $label, $dir) -ForegroundColor Green
        Write-Host ("      last sync {0} {1} {2} docs {1} {3} skills" -f $last, $MidDot, $docs, $skills)
    }
    Write-Host ""
}

function Space-Remove($rawName) {
    if (-not $rawName) { $rawName = Read-Host "Which Space should be disconnected?" }
    $name = ConvertTo-SpaceName $rawName
    if (-not $name) { Err "Say which Space, e.g.  tekt space remove team"; return }
    $dir  = Join-Path $TektSpaces $name
    $meta = Join-Path $dir ".tekt-space"
    if (-not (Test-Path -LiteralPath $meta)) { Err "No Space named '$name'. See: tekt space list"; return }
    if (Test-Cmd "rclone") { & rclone config delete "tekt-$name" 2>$null | Out-Null }
    Move-Item -LiteralPath $meta -Destination (Join-Path $dir ".tekt-space.removed") -Force -ErrorAction SilentlyContinue
    Link-SpaceSkills $name   # its skills leave Claude Code
    Success "Disconnected '$name'. Your files stay in $dir and in the cloud folder; nothing was deleted."
}

function Space-Autosync($mode) {
    $taskName = "TektSpacesAutosync"
    if (-not $mode) { $mode = "on" }
    switch (([string]$mode).ToLowerInvariant()) {
        "off" {
            try {
                if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
                    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
                }
                Success "Autosync off."
            } catch {
                Warn "Couldn't turn off autosync. Open Task Scheduler and delete the task '$taskName'."
            }
        }
        "on" {
            Install-TektCli
            if (-not (Test-Path -LiteralPath $TektCliPs1)) {
                Warn "Autosync needs the tekt command. Install it with:  .\install.ps1 cli"
                return
            }
            try {
                $taskArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$TektCliPs1`" space sync"
                $action   = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $taskArgs
                $trigger  = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 10)
                $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
                Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings `
                    -Description "Tekt Spaces: two-way sync every 10 minutes (tekt space sync)" -Force -ErrorAction Stop | Out-Null
                Success "Autosync on: every 10 minutes. Turn off with: tekt space autosync off"
            } catch {
                Warn "Couldn't set up autosync ($($_.Exception.Message))."
                Warn "You can still sync by hand any time:  tekt space sync"
            }
        }
        default { Err "Use:  tekt space autosync on   or   tekt space autosync off" }
    }
}

function Space-Help {
    Write-Host "Usage: tekt space <command>"
    Write-Host "  add <name> [provider] [folder]  Create or join a Space (drive, onedrive, dropbox, box, nextcloud, folder, s3)"
    Write-Host "  list                            Show your Spaces"
    Write-Host "  sync [name]                     Two-way sync now (all Spaces, or just one)"
    Write-Host "  remove <name>                   Disconnect a Space (your files are kept)"
    Write-Host "  autosync on|off                 Sync every 10 minutes in the background"
}

# -- Shared skills: skills in a Space appear in everyone's Claude Code ----------
# (tekt skill list | new <space> <name> | link)
# Links $TektSpaces\<space>\skills\<skill>\ into $TektClaudeSkills\<space>--<skill>
# as a directory junction (no admin rights needed). Tekt only ever touches links
# whose target is inside the Spaces folder - never real folders or other links.

# Target of a junction/symlink as a full path, or $null for anything that isn't a link.
# PowerShell 5.1 returns .Target as an array, 7 as a string; .LinkTarget is .NET 6+.
function Get-SkillLinkTarget($path) {
    try { $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop } catch { return $null }
    if (-not $item.LinkType) { return $null }
    $t = $item.Target
    if (-not $t -and $item.PSObject.Properties["LinkTarget"]) { $t = $item.LinkTarget }
    $t = [string](@($t) | Select-Object -First 1)
    if (-not $t) { return $null }
    $t = $t -replace '^\\\\\?\\', '' -replace '^\\\?\?\\', ''   # strip \\?\ or \??\ prefixes
    if (-not [IO.Path]::IsPathRooted($t)) { $t = Join-Path (Split-Path $path -Parent) $t }
    return [IO.Path]::GetFullPath($t)
}

function Get-SpacesRootFull {
    [IO.Path]::GetFullPath($TektSpaces).TrimEnd('\', '/')
}

function Test-SkillOwnedLink($path) {   # true if $path is a link that points into the Spaces folder
    $t = Get-SkillLinkTarget $path
    if (-not $t) { return $false }
    $root = Get-SpacesRootFull
    return $t.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

# Remove only the link itself - never Remove-Item -Recurse, which would follow it
# and delete the skill it points to.
function Remove-SkillLink($path) {
    try { [IO.Directory]::Delete($path); return } catch { }
    try { [IO.File]::Delete($path) }   # a Unix symlink (the Linux test fallback)
    catch { Warn "Couldn't remove the old link $path" }
}

# Don't trust "no exception" alone: on non-Windows pwsh a piped junction attempt can fail
# silently, so check after each attempt that a link to the target really exists.
function New-SkillLink($link, $target) {
    try { $null = New-Item -ItemType Junction -Path $link -Target $target -ErrorAction Stop } catch { }
    if (Get-SkillLinkTarget $link) { return }
    # A failed junction must not leave an empty real folder in the way (non-recursive: only if empty)
    if (Test-Path -LiteralPath $link) { try { [IO.Directory]::Delete($link) } catch { } }
    # Fallback for testing under PowerShell on Linux/macOS, where junctions don't exist
    $why = ""
    try { $null = New-Item -ItemType SymbolicLink -Path $link -Target $target -ErrorAction Stop }
    catch { $why = " ($($_.Exception.Message))" }
    if (Get-SkillLinkTarget $link) { return }
    Warn "Couldn't link $(Split-Path $link -Leaf) into Claude Code$why"
}

# Skill folders (with a SKILL.md) inside one Space folder
function Get-SpaceSkillDirs($spaceDir) {
    $skillsDir = Join-Path $spaceDir "skills"
    if (-not (Test-Path -LiteralPath $skillsDir)) { return }
    Get-ChildItem -LiteralPath $skillsDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "SKILL.md") }
}

function Link-SpaceSkills($only) {   # link one Space's skills, or every Space's
    New-Item -ItemType Directory -Force -Path $TektClaudeSkills | Out-Null
    if (-not (Test-Path -LiteralPath $TektClaudeSkills)) { Warn "Couldn't create $TektClaudeSkills"; return }
    $root = Get-SpacesRootFull

    # Drop Tekt's links whose skill is gone, or whose Space was disconnected.
    foreach ($link in @([IO.Directory]::GetFileSystemEntries($TektClaudeSkills, "*--*"))) {
        if (-not (Test-SkillOwnedLink $link)) { continue }
        if ($only -and -not (Split-Path $link -Leaf).StartsWith("$only--")) { continue }
        $target = Get-SkillLinkTarget $link
        $tspace = ($target.Substring($root.Length + 1) -split '[\\/]')[0]
        $spaceMeta = Join-Path (Join-Path $TektSpaces $tspace) ".tekt-space"
        if (-not (Test-Path -LiteralPath (Join-Path $target "SKILL.md")) -or -not (Test-Path -LiteralPath $spaceMeta)) {
            Remove-SkillLink $link
        }
    }

    foreach ($sdir in @(Get-SpaceDirs)) {
        $name = Split-Path $sdir -Leaf
        if ($only -and $only -ne $name) { continue }
        foreach ($skill in @(Get-SpaceSkillDirs $sdir)) {
            $link = Join-Path $TektClaudeSkills "$name--$($skill.Name)"
            if (Test-SkillOwnedLink $link) {
                if ((Get-SkillLinkTarget $link) -eq [IO.Path]::GetFullPath($skill.FullName)) { continue }   # already right
                Remove-SkillLink $link
            } elseif ((Test-Path -LiteralPath $link) -or (Get-SkillLinkTarget $link)) {
                Warn "Skipping $name--$($skill.Name): something else already lives at $link"
                continue
            }
            New-SkillLink $link $skill.FullName
        }
    }
}

function Skill-List {
    Section "Shared skills"
    $found = $false
    foreach ($sdir in @(Get-SpaceDirs)) {
        $name = Split-Path $sdir -Leaf
        foreach ($skill in @(Get-SpaceSkillDirs $sdir)) {
            $found = $true
            $md   = Join-Path $skill.FullName "SKILL.md"
            $link = Join-Path $TektClaudeSkills "$name--$($skill.Name)"
            $desc = ""
            foreach ($line in [IO.File]::ReadAllLines($md)) {
                if ($line -match '^description:\s*(.*)$') { $desc = $Matches[1].Trim(); break }
            }
            if (-not $desc) { $desc = "(no description)" }
            if (Test-SkillOwnedLink $link) { Write-Host "  * " -ForegroundColor Green -NoNewline }
            else                           { Write-Host "  o " -ForegroundColor Yellow -NoNewline }
            Write-Host ("{0,-28} {1}" -f "$name/$($skill.Name)", $desc)
        }
    }
    if (-not $found) { Log "No shared skills yet. Make one:  tekt skill new team summarize" }
    else             { Log "* in Claude Code ($TektClaudeSkills)   o not linked yet - run: tekt skill link" }
}

function Skill-New($rawSpace, $rawName) {
    if (-not $rawSpace -or -not $rawName) { Err "Usage:  tekt skill new <space> <skill-name>"; return }
    $space = ConvertTo-SpaceName $rawSpace
    $sdir  = Join-Path $TektSpaces $space
    if (-not $space -or -not (Test-Path -LiteralPath (Join-Path $sdir ".tekt-space"))) {
        Err "No Space named '$rawSpace'. See:  tekt space list"; return
    }
    $name = ConvertTo-SpaceName $rawName
    if (-not $name) { Err "Give the skill a name, e.g.  tekt skill new $space summarize"; return }
    $dir = Join-Path (Join-Path $sdir "skills") $name
    $md  = Join-Path $dir "SKILL.md"
    if (Test-Path -LiteralPath $md) { Warn "Skill '$name' already exists: $md"; return }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $lines = @(
        "---",
        "name: $name",
        "description: One line: what this skill does and when to use it.",
        "---",
        "",
        "# $name",
        "",
        "## When to use",
        "- Describe the situations where an AI should reach for this skill.",
        "",
        "## Steps",
        "1. First step.",
        "2. Next step.",
        "",
        "## Notes",
        "- Anything the AI should know: sources, tone, formats, pitfalls."
    )
    # LF endings so the synced file is byte-identical to one made by install.sh
    [IO.File]::WriteAllText($md, (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding $false))
    Link-SpaceSkills $space
    Success "New skill: $md"
    Log "Edit it, then run  tekt space sync $space  - everyone in the Space gets it."
}

function Invoke-SkillCmd($argv) {
    $argv = @($argv)
    $sub = if ($argv.Count -ge 1 -and $argv[0]) { $argv[0] } else { "list" }
    $a1  = if ($argv.Count -ge 2) { $argv[1] } else { "" }
    $a2  = if ($argv.Count -ge 3) { $argv[2] } else { "" }
    switch ($sub) {
        "list"  { Skill-List }
        "ls"    { Skill-List }
        "new"   { Skill-New $a1 $a2 }
        "link"  { Link-SpaceSkills; Success "Shared skills linked into Claude Code ($TektClaudeSkills)" }
        default { Err "Unknown: skill $sub - use list, new or link" }
    }
}

# -- Connect: let your AI apps use your Spaces (tekt connect [app]) -------------
# Registers the MCP filesystem server, scoped to $TektSpaces, with Claude Code,
# Claude Desktop and Codex. Re-running replaces Tekt's own entry and leaves
# everything else in those configs alone. Native Windows launches npx via cmd.
function Get-ClaudeDesktopConfig {
    $appData = if ($env:APPDATA) { $env:APPDATA } else { Join-Path $HOME "AppData\Roaming" }
    Join-Path (Join-Path $appData "Claude") "claude_desktop_config.json"
}

function Get-CodexConfig {
    $codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" }
    Join-Path $codexHome "config.toml"
}

function Connect-ClaudeCode {
    if (-not (Test-Cmd "claude")) {
        Warn "Claude Code isn't installed - skipping. Install: irm https://claude.ai/install.ps1 | iex"
        return $false
    }
    & claude @("mcp", "remove", "--scope", "user", $TektMcpName) 2>$null | Out-Null
    # '--' is passed as a quoted array element so PowerShell hands it to claude untouched
    & claude @("mcp", "add", "--scope", "user", $TektMcpName, "--", "cmd", "/c", "npx", "-y", $TektMcpPkg, $TektSpaces) 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Success "Claude Code can use your Spaces (MCP server '$TektMcpName')"
        return $true
    }
    Warn "Claude Code didn't accept the server. Add it by hand:"
    Warn "  claude mcp add --scope user $TektMcpName -- cmd /c npx -y $TektMcpPkg `"$TektSpaces`""
    return $false
}

function Connect-ClaudeDesktop {
    $cfg    = Get-ClaudeDesktopConfig
    $cfgDir = Split-Path $cfg -Parent
    if (-not (Test-ClaudeDesktop) -and -not (Test-Path -LiteralPath $cfgDir)) {
        Warn "Claude Desktop isn't installed - skipping. Get it at https://claude.ai/download"
        return $false
    }
    New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
    $untouched = "Couldn't update $cfg (the file must be valid JSON). Your original is untouched."

    $data = $null
    if (Test-Path -LiteralPath $cfg) {
        try { Copy-Item -LiteralPath $cfg -Destination "$cfg.bak-tekt" -Force -ErrorAction Stop }
        catch { Warn "Couldn't back up $cfg, so it was left alone."; return $false }
        $raw = [IO.File]::ReadAllText($cfg)
        if ($raw.Trim()) {
            try { $data = $raw | ConvertFrom-Json -ErrorAction Stop }
            catch { Warn $untouched; return $false }
            if ($data -isnot [System.Management.Automation.PSCustomObject]) { Warn $untouched; return $false }
        }
    }
    if ($null -eq $data) { $data = [pscustomobject]@{} }

    # PowerShell 5.1 gives a PSCustomObject: add/replace properties with Add-Member -Force
    $existing = $data.PSObject.Properties["mcpServers"]
    if (-not $existing -or $null -eq $existing.Value) {
        $data | Add-Member -NotePropertyName "mcpServers" -NotePropertyValue ([pscustomobject]@{}) -Force
    } elseif ($existing.Value -isnot [System.Management.Automation.PSCustomObject]) {
        Warn $untouched
        return $false
    }
    $server = [pscustomobject]@{ command = "cmd"; args = @("/c", "npx", "-y", $TektMcpPkg, $TektSpaces) }
    $data.mcpServers | Add-Member -NotePropertyName $TektMcpName -NotePropertyValue $server -Force

    try {
        $json = $data | ConvertTo-Json -Depth 20
        [IO.File]::WriteAllText($cfg, $json + "`n", (New-Object System.Text.UTF8Encoding $false))
    } catch {
        Warn "Couldn't write $cfg. Your previous version is in $cfg.bak-tekt"
        return $false
    }
    Success "Claude Desktop can use your Spaces after you restart it ($cfg)"
    return $true
}

function Connect-Codex {
    if (-not (Test-Cmd "codex")) {
        Warn "Codex CLI isn't installed - skipping. Install: npm install -g @openai/codex"
        return $false
    }
    $cfg    = Get-CodexConfig
    $header = "[mcp_servers.$TektMcpName]"
    New-Item -ItemType Directory -Force -Path (Split-Path $cfg -Parent) | Out-Null

    $lines = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $cfg) {
        try { Copy-Item -LiteralPath $cfg -Destination "$cfg.bak-tekt" -Force -ErrorAction Stop }
        catch { Warn "Couldn't back up $cfg, so it was left alone."; return $false }
        # drop Tekt's previous block (up to the next [section]), keep everything else
        $skip = $false
        foreach ($line in [IO.File]::ReadAllLines($cfg)) {
            if ($line.Trim() -eq $header) { $skip = $true; continue }
            if ($line.StartsWith("[")) { $skip = $false }
            if (-not $skip) { $lines.Add($line) }
        }
        while ($lines.Count -gt 0 -and -not $lines[$lines.Count - 1].Trim()) { $lines.RemoveAt($lines.Count - 1) }
    }

    # TOML literal strings ('...') need no backslash escaping; a path containing ' needs a basic string
    $spacesToml = if ($TektSpaces.Contains("'")) {
        '"' + (($TektSpaces -replace '\\', '\\') -replace '"', '\"') + '"'
    } else {
        "'" + $TektSpaces + "'"
    }
    if ($lines.Count -gt 0) { $lines.Add("") }
    $lines.Add($header)
    $lines.Add('command = "cmd"')
    $lines.Add("args = ['/c', 'npx', '-y', '$TektMcpPkg', $spacesToml]")

    try {
        [IO.File]::WriteAllText($cfg, (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding $false))
    } catch {
        Warn "Couldn't write $cfg. Your previous version is in $cfg.bak-tekt"
        return $false
    }
    Success "Codex can use your Spaces ($cfg)"
    return $true
}

function Tekt-Connect($app) {
    if (-not $app) { $app = "all" }
    Section "Connect your AI to your Spaces"
    New-Item -ItemType Directory -Force -Path $TektSpaces | Out-Null
    $connected = $false
    switch (([string]$app).ToLowerInvariant()) {
        "claude-code"    { if (Connect-ClaudeCode)    { $connected = $true } }
        "claude"         { if (Connect-ClaudeCode)    { $connected = $true } }
        "code"           { if (Connect-ClaudeCode)    { $connected = $true } }
        "claude-desktop" { if (Connect-ClaudeDesktop) { $connected = $true } }
        "desktop"        { if (Connect-ClaudeDesktop) { $connected = $true } }
        "codex"          { if (Connect-Codex)         { $connected = $true } }
        "all" {
            if (Test-Cmd "claude") { if (Connect-ClaudeCode) { $connected = $true } }
            if ((Test-ClaudeDesktop) -or (Test-Path -LiteralPath (Split-Path (Get-ClaudeDesktopConfig) -Parent))) {
                if (Connect-ClaudeDesktop) { $connected = $true }
            }
            if (Test-Cmd "codex") { if (Connect-Codex) { $connected = $true } }
        }
        default {
            Err "Unknown AI app '$app'. Use: claude-code, claude-desktop, codex or all."
            return
        }
    }
    if ((Test-Cmd "claude") -or (Test-Path -LiteralPath (Join-Path $HOME ".claude"))) {
        Link-SpaceSkills
        Success "Shared skills from your Spaces are linked into Claude Code ($TektClaudeSkills)"
    }
    if (-not (Test-Cmd "npx")) {
        Warn "Your AI apps start the Spaces server with npx, which comes with Node.js. Install it first:  winget install OpenJS.NodeJS.LTS"
    }
    Write-Host ""
    if (-not $connected) { Warn "No AI app connected yet. Tekt connects Claude Code, Claude Desktop and Codex." }
    Log "Other MCP apps: add a server with  command: cmd   args: /c npx -y $TektMcpPkg $TektSpaces"
    Log "Running MCPHub (tekt mcp)? Apps can also use http://localhost:3000/mcp - it serves /spaces too."
    Log "Try it: ask your AI `"What's in my team Space?`""
}

# -- Status ---------------------------------------------------------------------
function Tekt-Status {
    Write-Host "`nTekt Environment Status - https://tekt.md`n" -ForegroundColor Cyan
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
    Write-Host ("  [--]  Tekt.Iris  Hermes Agent - WSL2 only (wsl --install, then bash install.sh)") -ForegroundColor Yellow
    if (Test-Path (Join-Path $TektAgentsDir "nanoclaw\.git")) { Write-Host "  [OK]  Tekt.Iris  NanoClaw (staged)" -ForegroundColor Green }
    if (Test-Path (Join-Path $TektInstance "sovrant\.git")) {
        if (Test-Path (Join-Path $TektInstance "sovrant\src\Sovrant.Web\bin")) {
            Write-Host "  [OK]  Tekt.Cloud Sovrant built (BSL 1.1) - Web :5100, Server :5200" -ForegroundColor Green
        } else {
            Write-Host "  [ ?]  Tekt.Cloud Sovrant cloned, not built - cd $TektInstance\sovrant ; dotnet build" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [ ?]  Tekt.Cloud Sovrant not staged (BSL 1.1) - .\install.ps1 installs it" -ForegroundColor Yellow
    }
    if (Test-Cmd "docker") {
        foreach ($svc in @(@("MCPHub","mcphub","http://localhost:3000"), @("LibreChat","librechat","http://localhost:3080"), @("n8n","n8n","http://localhost:5678"))) {
            $up = docker ps --format "{{.Image}} {{.Names}}" 2>$null | Select-String -Quiet $svc[1]
            if ($up) { Write-Host ("  [OK]  Tekt.Cloud {0} running - {1}" -f $svc[0], $svc[2]) -ForegroundColor Green }
            else     { Write-Host ("  [ ?]  Tekt.Cloud {0} not running" -f $svc[0]) -ForegroundColor Yellow }
        }
    }
    Write-Host "`n  Spaces" -ForegroundColor Cyan
    $spaceDirs = @(Get-SpaceDirs)
    if ($spaceDirs.Count -eq 0) {
        Write-Host "  [ ?]  No Spaces yet $EmDash tekt space add team drive" -ForegroundColor Yellow
    } else {
        foreach ($sd in $spaceDirs) {
            $last = Get-SpaceMeta $sd "last_sync"
            if (-not $last) { $last = "never" }
            Write-Host ("  [OK]  {0,-16} last sync {1}" -f (Split-Path $sd -Leaf), $last) -ForegroundColor Green
        }
    }
    $skTotal = 0; $skLinked = 0
    foreach ($sd in $spaceDirs) { $skTotal += @(Get-SpaceSkillDirs $sd).Count }
    if (Test-Path -LiteralPath $TektClaudeSkills) {
        foreach ($l in @([IO.Directory]::GetFileSystemEntries($TektClaudeSkills, "*--*"))) {
            if (Test-SkillOwnedLink $l) { $skLinked++ }
        }
    }
    if ($skTotal -gt 0) {
        Write-Host ("  [OK]  {0,-16} {1} of {2} linked into Claude Code" -f "Shared skills", $skLinked, $skTotal) -ForegroundColor Green
    }
    Write-Host "`n  AI apps connected to your Spaces" -ForegroundColor Cyan
    $capps     = 0
    $ccJson    = Join-Path $HOME ".claude.json"
    $cdJson    = Get-ClaudeDesktopConfig
    $codexToml = Get-CodexConfig
    if ((Test-Path -LiteralPath $ccJson) -and (Select-String -LiteralPath $ccJson -SimpleMatch "`"$TektMcpName`"" -Quiet)) {
        Write-Host ("  [OK]  {0,-16} uses your Spaces" -f "Claude Code") -ForegroundColor Green; $capps++
    }
    if ((Test-Path -LiteralPath $cdJson) -and (Select-String -LiteralPath $cdJson -SimpleMatch "`"$TektMcpName`"" -Quiet)) {
        Write-Host ("  [OK]  {0,-16} uses your Spaces" -f "Claude Desktop") -ForegroundColor Green; $capps++
    }
    if ((Test-Path -LiteralPath $codexToml) -and (Select-String -LiteralPath $codexToml -Pattern ('^\[mcp_servers\.' + [regex]::Escape($TektMcpName) + '\]') -Quiet)) {
        Write-Host ("  [OK]  {0,-16} uses your Spaces" -f "Codex") -ForegroundColor Green; $capps++
    }
    if ($capps -eq 0) { Write-Host "  [ ?]  None yet - tekt connect" -ForegroundColor Yellow }
    Write-Host "`n  $installed installed / $missing missing`n"
    if ($missing -gt 0) { Log "Run '.\install.ps1' to install everything." }
    Log "If tools were just installed, pause and restart PowerShell, then run '.\install.ps1 status' again."
}

# -- Main -----------------------------------------------------------------------
function Main {
    Write-Host "`nTekt - the utility belt for your AI harness (Windows installer) - https://tekt.md" -ForegroundColor Cyan
    Write-Host "Pre-vetted tools for an AI sandbox. Bring your own intelligence: Ollama, OpenRouter, OpenAI, Anthropic.`n"
    Refresh-SessionPath
    Log "Tip: WSL2 gives full Linux parity - wsl --install, then bash install.sh"

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
    Install-TektCli
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
    Warn "Hermes has no native Windows build - use WSL2: wsl --install, then bash install.sh"
    # Tekt.Cloud
    Install-Sovrant

    Write-Host ""
    Log "Staged (tekt.cloud): bring up with  .\install.ps1 mcp   and   .\install.ps1 ui"
    Log "Let your AI apps use your Spaces:  tekt connect"
    Log "PATH is refreshed during install. If a new command still isn't found, open a new PowerShell window, then run:  .\install.ps1 status"
}

switch ($Command) {
    "status" { Tekt-Status }
    "mcp"    { Setup-McpHub }
    "ui"     { Setup-Ui }
    "share"  { Tekt-Share $Arg }
    "cli"    { Install-TektCli }
    "connect" {
        Refresh-SessionPath
        $app = if ($Rest.Count -ge 1 -and $Rest[0]) { $Rest[0] } else { "all" }
        Tekt-Connect $app
    }
    "skill"  { Invoke-SkillCmd $Rest }
    "skills" { Invoke-SkillCmd $Rest }
    "space"  {
        Refresh-SessionPath
        $sub = if ($Rest.Count -ge 1 -and $Rest[0]) { $Rest[0] } else { "list" }
        $a1  = if ($Rest.Count -ge 2) { $Rest[1] } else { "" }
        $a2  = if ($Rest.Count -ge 3) { $Rest[2] } else { "" }
        $a3  = if ($Rest.Count -ge 4) { $Rest[3] } else { "" }
        switch ($sub) {
            "add"      { Space-Add $a1 $a2 $a3 }
            "sync"     { Space-Sync $a1 }
            "list"     { Space-List }
            "ls"       { Space-List }
            "remove"   { Space-Remove $a1 }
            "rm"       { Space-Remove $a1 }
            "autosync" { Space-Autosync $a1 }
            "help"     { Space-Help }
            default    { Warn "Unknown command: space $sub"; Space-Help }
        }
    }
    "help"   {
        Write-Host "Usage: .\install.ps1 [status|catalog|mcp|ui|share <port>|space ...|skill ...|connect [app]|cli|help]"
        Write-Host "       (after 'cli' you can type 'tekt' instead of '.\install.ps1')"
        Write-Host "  (none)        Install all Tekt tools"
        Write-Host "  status        Check which tools are installed"
        Write-Host "  mcp           MCPHub + curated MCP servers (:3000)"
        Write-Host "  ui            LibreChat (:3080) + n8n (:5678)"
        Write-Host "  share <port>  HTTPS tunnel (Tailscale Serve, else ngrok)"
        Write-Host "  cli           Install the 'tekt' command"
        Write-Host ""
        Write-Host "Spaces: share docs, knowledge and skills through Google Drive, OneDrive, Dropbox, Box, Nextcloud or a folder"
        Write-Host "  space add <name> [provider] [folder]  Create or join a Space"
        Write-Host "  space list                            Show your Spaces"
        Write-Host "  space sync [name]                     Two-way sync now"
        Write-Host "  space remove <name>                   Disconnect a Space (your files are kept)"
        Write-Host "  space autosync on|off                 Sync every 10 minutes in the background"
        Write-Host ""
        Write-Host "  connect [app]  Let your AI apps use your Spaces: all (default), claude-code, claude-desktop, codex"
        Write-Host ""
        Write-Host "Shared skills: skills in a Space appear in everyone's Claude Code"
        Write-Host "  skill list                            Skills shared in your Spaces, and which are in Claude Code"
        Write-Host "  skill new <space> <name>              Start a skill in a Space; everyone gets it after sync"
        Write-Host "  skill link                            Re-link shared skills into Claude Code"
        Write-Host ""
        Write-Host "Windows note: after installs, restart PowerShell, then run .\install.ps1 status"
    }
    "catalog" {
        if (Test-Path $catalogPath) { Get-Content $catalogPath }
        else { irm https://tekt.md/tekt.catalog.yaml }
    }
    default  { Main }
}
