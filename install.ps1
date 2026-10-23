# =============================================================================
# install.ps1
# Tekt Platform - Windows Bootstrap (PowerShell)
# https://tekt.md
#
# Installs (winget): Git, GitHub CLI, Go, Python, Node LTS, VS Code, Docker Desktop,
#                    rclone, AWS CLI, Tailscale, ngrok, Ollama, crush
# Installs (native): Claude Code, Claude Desktop, Zed Agent, OpenClaw, PicoClaw, ZeroClaw, Nanobot,
#                    Codex CLI, opencode, pi, omp (oh-my-pi)
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
#         tekt space invite <name>                    # write an invitation (copied to your clipboard)
#         tekt space open <name>                      # open a Space's folder
#         tekt space gui                              # open your storage in a point-and-click window (RcloneView)
#         tekt space remove <name>                    # disconnect (files are kept)
#         tekt space autosync on|off                  # sync every 10 minutes
#
# Connect - let your AI apps use your Spaces (MCP filesystem server "tekt-spaces"):
#         tekt connect [app]    # all (default), claude-code, claude-desktop, codex, opencode, crush
#
# Shared skills - skills in a Space appear in everyone's Claude Code:
#         tekt skill list                 # skills in your Spaces, and which are linked
#         tekt skill new <space> <name>   # start a skill; everyone gets it after sync
#         tekt skill link                 # re-link shared skills into Claude Code
#         tekt skill shelf                # hand-curated skills you can add in one step
#         tekt skill add <skill> [space]  # add a curated skill to a Space (everyone gets it)
#
# Tool shelf - hand-picked MCP servers for your AI apps:
#         tekt tool shelf                              # the servers you can add
#         tekt tool add <server> [space] [--app <app>] # register one (memory can live in a Space)
#         tekt tool remove <server>                    # take Tekt's entry out of every app
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
$TektAgentSkills  = if ($env:TEKT_AGENT_SKILLS)  { $env:TEKT_AGENT_SKILLS }  else { Join-Path (Join-Path $HOME ".agents") "skills" }   # pi reads skills here
$TektResults   = [System.Collections.Generic.List[object]]::new()   # winget install results for the final summary
$EmDash        = [string][char]0x2014   # built from char codes so the file parses the same under any encoding
$MidDot        = [string][char]0x00B7

# -- Catalog reader (no YAML module, no other prerequisite) --------------------
# tekt.catalog.yaml is the source of truth: it holds the version pins and the
# install/detect data for every tool. Two readers, both plain line parsing so
# `irm | iex` still needs nothing installed first:
#   Get-CatalogPins   - every KEY: value under pins:
#   Get-CatalogInstallEntries  - every tool entry under layers:, as { Key, Name, Layer,
#                       Fields }, following the install schema documented in the
#                       catalog. Flat 8-space scalars only, so nested maps and
#                       folded blocks under an entry are ignored.
function Convert-CatalogScalar($raw) {
    $v = ([string]$raw).Trim()
    if ($v -match '^"(.*)"$') { return $Matches[1].Replace('\"', '"').Replace('\\', '\') }
    $v = ($v -replace '\s+#.*$', '').Trim()
    return $v
}

function Get-CatalogPins($file) {
    $pins = @{}
    $on = $false
    foreach ($line in [IO.File]::ReadAllLines($file)) {
        if (-not $on) { if ($line -match '^pins:\s*$') { $on = $true }; continue }
        if ($line -match '^[^\s#]') { break }
        if ($line -match '^  ([A-Z][A-Z0-9_]*):(.*)$') { $pins[$Matches[1]] = Convert-CatalogScalar $Matches[2] }
    }
    return $pins
}

function Add-CatalogEntry($tools, $cur) {
    if (-not $cur) { return }
    if (-not $cur.Key) { $cur.Key = ($cur.Name.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-') }
    $tools.Add([pscustomobject]$cur)
}

function Get-CatalogInstallEntries($file) {
    $tools = [System.Collections.Generic.List[object]]::new()
    $on = $false; $layer = ""; $cur = $null
    foreach ($line in [IO.File]::ReadAllLines($file)) {
        if (-not $on) { if ($line -match '^layers:\s*$') { $on = $true }; continue }
        if ($line -match '^[^\s#]') { Add-CatalogEntry $tools $cur; $cur = $null; break }
        if ($line -match '^  ([A-Za-z0-9._-]+):\s*$') {
            Add-CatalogEntry $tools $cur; $cur = $null
            $layer = $Matches[1]
            continue
        }
        if ($line -match '^      - name:(.*)$') {
            Add-CatalogEntry $tools $cur
            $cur = @{ Name = (Convert-CatalogScalar $Matches[1]); Key = ""; Layer = $layer; Fields = @{} }
            continue
        }
        if ($cur -and $line -match '^        ([a-z][a-z0-9_]*):(.*)$') {
            $field = $Matches[1]; $value = Convert-CatalogScalar $Matches[2]
            if ($value -eq "" -or $value -eq ">" -or $value -eq "|") { continue }   # nested map or folded block
            if ($field -eq "key") { $cur.Key = $value } else { $cur.Fields[$field] = $value }
        }
    }
    Add-CatalogEntry $tools $cur
    return $tools
}

# -- Catalog pins (tekt.catalog.yaml next to this script, if present) ----------
$McpHubImage = "samanhappy/mcphub:latest"
$N8nImage    = "docker.n8n.io/n8nio/n8n:latest"
$RcloneViewWinVersion = "1.5.32"   # winget's Bdrive.RcloneView is stale, so Tekt pins the official installer
$catalogPath = Join-Path $PSScriptRoot "tekt.catalog.yaml"
if (Test-Path $catalogPath) {
    $pins = Get-CatalogPins $catalogPath
    if ($pins["MCPHUB_IMAGE"])              { $McpHubImage          = $pins["MCPHUB_IMAGE"] }
    if ($pins["N8N_IMAGE"])                 { $N8nImage             = $pins["N8N_IMAGE"] }
    if ($pins["RCLONEVIEW_WINDOWS_VERSION"]){ $RcloneViewWinVersion = $pins["RCLONEVIEW_WINDOWS_VERSION"] }
    Log "Loaded version pins from tekt.catalog.yaml"
}

function Test-Cmd($name) { [bool](Get-Command $name -ErrorAction SilentlyContinue) }
function Test-ClaudeDesktop {
    $candidates = @()
    if ($env:LOCALAPPDATA) {
        $candidates += Join-Path $env:LOCALAPPDATA "AnthropicClaude\claude.exe"     # per-user install
        $candidates += Join-Path $env:LOCALAPPDATA "Programs\Claude\Claude.exe"
    }
    if ($env:ProgramFiles) { $candidates += Join-Path $env:ProgramFiles "Claude\Claude.exe" }
    foreach ($p in $candidates) { if (Test-Path $p) { return $true } }
    return $false
}

# -- winget: preflight and honest results -------------------------------------
# A native command's non-zero exit never throws, so every winget result is judged
# by $LASTEXITCODE (and by the command actually being on PATH), never by try/catch.
$WingetOkCodes = @(0, -1978335135, -1978335189)   # 0x8A150061 already installed, 0x8A15002B no applicable upgrade

function Format-ExitCode($code) { "0x" + ('{0:X8}' -f [int]$code) }

function Add-InstallResult($label, $ok, [switch]$Pending) {
    $TektResults.Add([pscustomobject]@{ Label = [string]$label; Ok = [bool]$ok; Pending = [bool]$Pending })
}

# Elevated session? [Security.Principal.WindowsPrincipal] throws off Windows, so that's "no".
function Test-IsAdmin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        return [bool]([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

# Run once before any installs: a broken source (0x8a15000f "Data required by the
# source is missing") makes every winget install fail.
function Test-WingetSources {
    if (-not (Test-Cmd "winget")) { return }   # Install-Winget explains how to get winget
    Section "winget sources"
    $out  = (& winget source update 2>&1 | Out-String)
    $code = $LASTEXITCODE
    if ($code -eq 0 -and $out -notmatch '0x8a15000f') { Success "winget sources are up to date"; return }
    Warn "winget's package sources are broken (exit code $(Format-ExitCode $code)), so installs would fail."
    if ($out.Trim()) { Write-Host $out.Trim() }
    if (Test-IsAdmin) {
        Log "Resetting winget sources (this window is running as Administrator)..."
        & winget source reset --force 2>&1 | Out-Host
        $out  = (& winget source update 2>&1 | Out-String)
        $code = $LASTEXITCODE
        if ($code -eq 0 -and $out -notmatch '0x8a15000f') { Success "winget sources repaired"; return }
        Warn "winget sources still look broken (exit code $(Format-ExitCode $code)) - installs below may fail."
    } else {
        Warn "Open PowerShell as Administrator and run: winget source reset --force; winget source update"
        Warn "Then run the installer again. Continuing for now - winget installs below may fail."
    }
}

function Install-Winget($label, $id, $cmd) {
    Section $label
    if ($cmd -and (Test-Cmd $cmd)) { Success "$label already installed"; Add-InstallResult $label $true; return }
    if (-not (Test-Cmd "winget")) {
        Warn "winget not found - install 'App Installer' from the Microsoft Store, then re-run."
        Add-InstallResult $label $false
        return
    }
    winget install --id $id -e --source winget --accept-source-agreements --accept-package-agreements
    $code = $LASTEXITCODE
    Refresh-SessionPath
    if ($WingetOkCodes -notcontains $code) {
        Warn "$label didn't install (winget exit code $(Format-ExitCode $code)). Try: winget install --id $id -e"
        Add-InstallResult $label $false
        return
    }
    if ($cmd -and -not (Test-Cmd $cmd)) {
        # winget succeeded; Windows often only exposes the new command in a fresh window
        Warn "$label installed, but '$cmd' isn't available in this window yet. Open a new PowerShell window, then run .\install.ps1 status"
        Add-InstallResult $label $true -Pending
        return
    }
    Success "$label installed ($id)"
    Add-InstallResult $label $true
}

function Write-InstallSummary {
    $ok  = @($TektResults | Where-Object { $_.Ok })
    $bad = @($TektResults | Where-Object { -not $_.Ok })
    $wait = @($TektResults | Where-Object { $_.Pending })
    Section "Summary"
    $line = "{0} installed, {1} failed" -f $ok.Count, $bad.Count
    if ($bad.Count -eq 0) {
        Success $line
    } else {
        Warn "$line - failed: $(($bad | ForEach-Object { $_.Label }) -join ', ')"
        Log "Fix the warnings above, then run .\install.ps1 again (tools already installed are skipped)."
    }
    if ($wait.Count -gt 0) {
        Log "Open a new PowerShell window to start using: $(($wait | ForEach-Object { $_.Label }) -join ', ')"
    }
}

# -- Catalog-driven installs ----------------------------------------------------
# One loop for every entry the catalog marks `managed: catalog`, in catalog
# order, layer by layer. Each entry brings its own detection command and its own
# Windows install command, so adding a tool is a catalog edit, not a new
# function here. Entries left at `managed: script` keep running through their
# Install-* function below, so the migration is per-tool and reversible.
#
# The behaviours the hand-written functions guarantee are kept: the detection
# command is the idempotency check, "winget:<Package.Id>" goes through
# Install-Winget so winget's exit codes are judged the same way, PATH is
# refreshed before verifying, a tool that installed cleanly but isn't visible
# yet is reported as Pending (not failed), and nothing throws - every result
# lands in the summary.
$CatalogFile  = $null
$CatalogTools = @()

function Initialize-Catalog {
    $file = Get-TektCatalogFile
    if (-not $file) { return $false }
    $tools = @(Get-CatalogInstallEntries $file)
    if ($tools.Count -eq 0) { return $false }
    $script:CatalogFile  = $file
    $script:CatalogTools = $tools
    return $true
}

function Get-CatalogEntry($key) {
    return @($CatalogTools | Where-Object { $_.Key -eq $key }) | Select-Object -First 1
}

function Get-CatalogField($tool, $field) {   # Windows override first, then the shared value
    if (-not $tool) { return "" }
    foreach ($name in @("${field}_windows", $field)) {
        if ($tool.Fields.ContainsKey($name) -and $tool.Fields[$name]) { return [string]$tool.Fields[$name] }
    }
    return ""
}

function Test-CatalogManaged($tool) { (Get-CatalogField $tool "managed") -eq "catalog" }

function Test-CatalogPlatform($tool) {
    $plats = Get-CatalogField $tool "platforms"
    if (-not $plats) { return $true }
    return ($plats -replace '[\[\]" ]', '') -split ',' -contains "windows"
}

function Test-CatalogDetect($tool) {
    $detect = Get-CatalogField $tool "detect"
    if (-not $detect) {
        $cmd = Get-CatalogField $tool "cmd"
        if (-not $cmd) { return $false }
        $detect = "cmd:$cmd"
    }
    switch -Regex ($detect) {
        '^cmd:(.+)$'         { return (Test-Cmd $Matches[1]) }
        '^path:(.+)$'        { return (Test-Path -LiteralPath ([Environment]::ExpandEnvironmentVariables(($Matches[1] -replace '^~', $HOME)))) }
        '^app:claude-desktop$' { return (Test-ClaudeDesktop) }
        default              { return $false }
    }
}

# Official installers are written for an interactive window and some of them
# call `exit`, so each one runs in its own PowerShell process (the same trick
# Install-Codex and Install-Omp use) and is judged by its exit code.
function Invoke-CatalogCommand($command) {
    $ps = if (Test-Cmd "pwsh") { "pwsh" } else { "powershell" }
    & $ps -NoProfile -ExecutionPolicy Bypass -Command $command
    return $LASTEXITCODE
}

function Install-CatalogEntry($tool) {
    $label = if ($tool.Name) { $tool.Name } else { $tool.Key }
    $cmd   = Get-CatalogField $tool "cmd"
    $install = Get-CatalogField $tool "install"

    if (-not (Test-CatalogPlatform $tool)) { Section $label; Log "$label has no Windows install - skipping."; return }

    # winget entries go through Install-Winget, which owns the exit-code and Pending reporting
    if ($install -match '^winget:(.+)$') { Install-Winget $label $Matches[1] $cmd; return }

    Section $label
    if (Test-CatalogDetect $tool) { Success "$label already installed"; Add-InstallResult $label $true; return }

    $needs = Get-CatalogField $tool "requires"
    if ($needs -and -not (Test-Cmd $needs)) {
        Warn "$label needs $needs. Install it first, then run .\install.ps1 again."
        Add-InstallResult $label $false
        return
    }
    if (-not $install) {
        Warn "The catalog has no Windows install command for $label."
        Add-InstallResult $label $false
        return
    }

    Log "Installing $label - $install"
    $code = Invoke-CatalogCommand $install
    Refresh-SessionPath

    if (-not (Test-CatalogDetect $tool)) {
        $alt = Get-CatalogField $tool "install_alt"
        if ($alt) {
            Log "Trying the fallback - $alt"
            $code = Invoke-CatalogCommand $alt
            Refresh-SessionPath
        }
    }

    if (Test-CatalogDetect $tool) {
        Success "$label installed"
        $post = Get-CatalogField $tool "post_install"
        if ($post) { Log $post }
        Add-InstallResult $label $true
    } elseif ($code -eq 0) {
        # installed cleanly; Windows often only exposes the new command in a fresh window
        Warn "$label installed, but '$cmd' isn't available in this window yet. Open a new PowerShell window, then run .\install.ps1 status"
        Add-InstallResult $label $true -Pending
    } else {
        Warn "$label didn't install (exit code $code). Try by hand: $install"
        Add-InstallResult $label $false
    }
}

function Install-CatalogLayer($layer) {
    foreach ($tool in @($CatalogTools | Where-Object { $_.Layer -eq $layer -and (Test-CatalogManaged $_) })) {
        Install-CatalogEntry $tool
    }
}

function Show-CatalogPlan {
    Section "Catalog plan - windows"
    if (-not (Initialize-Catalog)) { Err "Couldn't read the catalog. Check your connection and try again."; return }
    Log $CatalogFile
    foreach ($layer in @($CatalogTools | ForEach-Object { $_.Layer } | Select-Object -Unique)) {
        Write-Host "`n  $layer"
        foreach ($tool in @($CatalogTools | Where-Object { $_.Layer -eq $layer })) {
            $managed = Get-CatalogField $tool "managed"
            if (-not $managed) { $managed = "-" }
            $state = if (-not ((Get-CatalogField $tool "detect") -or (Get-CatalogField $tool "cmd"))) { "-" }
                     elseif (-not (Test-CatalogPlatform $tool)) { "n/a here" }
                     elseif (Test-CatalogDetect $tool) { "installed" }
                     else { "missing" }
            $how = Get-CatalogField $tool "install"
            if (-not $how) { $how = Get-CatalogField $tool "install_steps" }
            if ($how.Length -gt 64) { $how = $how.Substring(0, 64) }
            Write-Host ("  {0,-18} {1,-9} {2,-9} {3}" -f $tool.Key, $managed, $state, $how)
        }
    }
    Write-Host ""
    Log "managed=catalog runs from this data; managed=script still runs its Install-* function."
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
    if (Test-ClaudeDesktop) { Success "Claude Desktop already installed"; Add-InstallResult "Claude Desktop" $true; return }
    if (-not (Test-Cmd "winget")) {
        Warn "winget not found. Install Claude Desktop from https://claude.ai/download"
        Add-InstallResult "Claude Desktop" $false
        return
    }
    # Judge by winget's exit code and by the app actually being there, never by try/catch (#25)
    winget install --id Anthropic.Claude -e --source winget --accept-source-agreements --accept-package-agreements
    $code = $LASTEXITCODE
    if ($WingetOkCodes -notcontains $code) {
        Warn "Claude Desktop didn't install (winget exit code $(Format-ExitCode $code)). Get it from https://claude.ai/download"
        Add-InstallResult "Claude Desktop" $false
        return
    }
    if (Test-ClaudeDesktop) {
        Success "Claude Desktop installed - sign in with your claude.ai account"
        Add-InstallResult "Claude Desktop" $true
    } else {
        Warn "winget finished, but Tekt can't find Claude Desktop yet. Open Claude from the Start menu; if it isn't there, get it from https://claude.ai/download"
        Add-InstallResult "Claude Desktop" $true -Pending
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

# -- More AI apps: Codex CLI (OpenAI), opencode, crush (Charm) -----------------
# Each is verified on PATH before [OK]; "installed but not on PATH yet" is Pending.
function Install-Codex {
    Section "Codex CLI (OpenAI)"
    if (Test-Cmd "codex") { Success "Codex CLI already installed"; Add-InstallResult "Codex CLI" $true; return }
    $claimed = $false
    # Run OpenAI's installer in its own PowerShell process (as OpenAI documents it), so an
    # `exit` inside that script can't end this installer.
    $ps = if (Test-Cmd "pwsh") { "pwsh" } else { "powershell" }
    & $ps -NoProfile -ExecutionPolicy Bypass -Command "irm https://chatgpt.com/codex/install.ps1 | iex"
    if ($LASTEXITCODE -eq 0) { $claimed = $true }
    else { Warn "The official Codex installer didn't finish (exit code $LASTEXITCODE)." }
    Refresh-SessionPath
    if (-not (Test-Cmd "codex") -and (Test-Cmd "npm")) {
        Log "Trying npm instead: npm install -g @openai/codex"
        npm install -g @openai/codex
        if ($LASTEXITCODE -eq 0) { $claimed = $true }
        Refresh-SessionPath
    }
    if (Test-Cmd "codex") {
        Success "Codex CLI installed - sign in with: codex login"
        Add-InstallResult "Codex CLI" $true
    } elseif ($claimed) {
        Warn "Codex CLI was installed but isn't on PATH yet. Open a new PowerShell window, then run: codex login"
        Add-InstallResult "Codex CLI" $true -Pending
    } else {
        Warn "Codex CLI didn't install. Try: npm install -g @openai/codex"
        Add-InstallResult "Codex CLI" $false
    }
}

function Install-OpenCode {
    Section "opencode"
    if (Test-Cmd "opencode") { Success "opencode already installed"; Add-InstallResult "opencode" $true; return }
    if (-not (Test-Cmd "npm")) {
        Warn "opencode needs Node.js (npm). Install Node.js LTS first:  winget install OpenJS.NodeJS.LTS"
        Add-InstallResult "opencode" $false
        return
    }
    npm i -g opencode-ai@latest
    $code = $LASTEXITCODE
    Refresh-SessionPath
    if (Test-Cmd "opencode") {
        Success "opencode installed"
        Add-InstallResult "opencode" $true
    } elseif ($code -eq 0) {
        Warn "opencode was installed but isn't on PATH yet. Open a new PowerShell window, then run: opencode"
        Add-InstallResult "opencode" $true -Pending
    } else {
        Warn "opencode didn't install (npm exit code $code). Try: npm i -g opencode-ai@latest"
        Add-InstallResult "opencode" $false
    }
}

function Install-Crush {
    Install-Winget "crush" "charmbracelet.crush" "crush"
}

function Install-Pi {
    Section "pi (coding agent)"
    if (Test-Cmd "pi") { Success "pi already installed"; Add-InstallResult "pi" $true; return }
    if (-not (Test-Cmd "npm")) {
        Warn "pi needs Node.js (npm). Install Node.js LTS first:  winget install OpenJS.NodeJS.LTS"
        Add-InstallResult "pi" $false
        return
    }
    npm install -g --ignore-scripts @earendil-works/pi-coding-agent
    $code = $LASTEXITCODE
    Refresh-SessionPath
    if (Test-Cmd "pi") {
        Success "pi installed"
        Add-InstallResult "pi" $true
    } elseif ($code -eq 0) {
        Warn "pi was installed but isn't on PATH yet. Open a new PowerShell window, then run: pi"
        Add-InstallResult "pi" $true -Pending
    } else {
        Warn "pi didn't install (npm exit code $code). Try: npm install -g --ignore-scripts @earendil-works/pi-coding-agent"
        Add-InstallResult "pi" $false
    }
}

function Install-Omp {
    Section "omp (oh-my-pi)"
    if (Test-Cmd "omp") { Success "omp already installed"; Add-InstallResult "omp" $true; return }
    # Run the official installer in its own PowerShell process (like Install-Codex), so an
    # `exit` inside that script can't end this installer.
    $ps = if (Test-Cmd "pwsh") { "pwsh" } else { "powershell" }
    & $ps -NoProfile -ExecutionPolicy Bypass -Command "irm https://omp.sh/install.ps1 | iex"
    $code = $LASTEXITCODE
    Refresh-SessionPath
    if (Test-Cmd "omp") {
        Success "omp installed"
        Add-InstallResult "omp" $true
    } elseif ($code -eq 0) {
        Warn "omp was installed but isn't on PATH yet. Open a new PowerShell window, then run: omp"
        Add-InstallResult "omp" $true -Pending
    } else {
        Warn "omp didn't install (installer exit code $code). Try: irm https://omp.sh/install.ps1 | iex"
        Add-InstallResult "omp" $false
    }
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

# -- RcloneView: a point-and-click window onto your storage and Spaces ---------
# Freemium and proprietary (Bdrive Inc.): the core features are free; RcloneView
# Plus adds scheduling and filters. winget's Bdrive.RcloneView is stuck at 0.2.x,
# so Tekt downloads the pinned official installer instead.
function Get-RcloneViewUninstallEntries {
    # -ErrorAction Ignore + try: the HKCU:/HKLM: drives don't exist off Windows
    foreach ($root in "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
                      "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
                      "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*") {
        try {
            Get-ItemProperty -Path $root -ErrorAction Ignore |
                Where-Object { $_.PSObject.Properties["DisplayName"] -and ([string]$_.DisplayName -match 'RcloneView') }
        } catch { }
    }
}

function Find-RcloneViewExe {   # full path to RcloneView.exe, or $null
    $candidates = @()
    if ($env:LOCALAPPDATA)   { $candidates += Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA "Programs") "RcloneView") "RcloneView.exe" }
    if (${env:ProgramFiles}) { $candidates += Join-Path (Join-Path ${env:ProgramFiles} "RcloneView") "RcloneView.exe" }
    foreach ($entry in @(Get-RcloneViewUninstallEntries)) {
        if ($entry.PSObject.Properties["InstallLocation"] -and $entry.InstallLocation) {
            $candidates += Join-Path ([string]$entry.InstallLocation) "RcloneView.exe"
        }
        if ($entry.PSObject.Properties["DisplayIcon"] -and $entry.DisplayIcon) {
            $candidates += (([string]$entry.DisplayIcon) -replace ',\s*-?\d+$', '').Trim('"')
        }
    }
    foreach ($c in $candidates) {
        if ($c -and ($c -match '\.exe$') -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

function Test-RcloneViewInstalled {
    [bool](Find-RcloneViewExe) -or (@(Get-RcloneViewUninstallEntries).Count -gt 0)
}

function Install-RcloneView {
    Section "RcloneView"
    if (Test-RcloneViewInstalled) { Success "RcloneView already installed"; Add-InstallResult "RcloneView" $true; return }
    $ver   = $RcloneViewWinVersion
    $url   = "https://downloads.bdrive.com/rclone_view/builds/setup_rclone_view-$ver.exe"
    $tmp   = if ($env:TEMP) { $env:TEMP } else { [IO.Path]::GetTempPath() }
    $setup = Join-Path $tmp "setup_rclone_view-$ver.exe"
    Log "Downloading RcloneView $ver (about 100 MB)..."
    try {
        Invoke-WebRequest -Uri $url -OutFile $setup -UseBasicParsing -ErrorAction Stop
    } catch {
        Warn "Couldn't download RcloneView ($url). Get it from https://rcloneview.com"
        Add-InstallResult "RcloneView" $false
        return
    }
    Log "Starting the RcloneView installer - follow the steps in its window."
    try {
        $proc = Start-Process -FilePath $setup -Wait -PassThru -ErrorAction Stop
    } catch {
        Warn "Couldn't start the RcloneView installer ($setup). Run it yourself, or get RcloneView from https://rcloneview.com"
        Add-InstallResult "RcloneView" $false
        return
    }
    $code = if ($proc -and $proc.PSObject.Properties["ExitCode"]) { $proc.ExitCode } else { 0 }
    if ($code -ne 0) {
        Warn "RcloneView didn't install (installer exit code $code - was the setup cancelled?). Try again: tekt space gui"
        Add-InstallResult "RcloneView" $false
        return
    }
    if (-not (Test-RcloneViewInstalled)) {
        Warn "The RcloneView installer finished, but Tekt can't find RcloneView yet. Look for it in the Start menu."
        Add-InstallResult "RcloneView" $true -Pending
        return
    }
    Success "RcloneView installed. It's freemium: the core features are free; RcloneView Plus adds scheduling and filters."
    Add-InstallResult "RcloneView" $true
}

function Tekt-Gui {   # tekt gui / tekt space gui
    if (-not (Test-RcloneViewInstalled)) {
        Install-RcloneView
        if (-not (Test-RcloneViewInstalled)) { return }   # Install-RcloneView already explained what went wrong
    }
    $exe = Find-RcloneViewExe
    $started = $false
    if ($exe) {
        try { Start-Process -FilePath $exe -ErrorAction Stop | Out-Null; $started = $true } catch { }
    }
    if (-not $started) { Log "Open RcloneView from the Start menu." }
    Success "RcloneView is opening - use it to browse and copy files between your computer and your cloud storage. Your Spaces live in $TektSpaces."
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
    Log "Invite people:                  tekt space invite $name   (writes the invitation for you)"
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
        if (($remote.Length + $folder.Length + $dir.Length) -gt 200) {   # rclone names its lock files after both paths (#58)
            Warn "$name has a very long path, and rclone may not be able to sync it. If it fails, keep Spaces somewhere shorter, e.g.  `$env:TEKT_SPACES = `"$HOME\Spaces`""
        }
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

# Copy text to the clipboard when this computer has one (Set-Clipboard can be missing or
# fail off Windows, e.g. Linux pwsh without xclip).
function Copy-SpaceText($text) {
    try {
        Set-Clipboard -Value ($text -replace "`n", [Environment]::NewLine) -ErrorAction Stop
        return $true
    } catch { return $false }
}

# Resolve a Space name to its folder, or explain and return $null
function Get-ActiveSpaceDir($rawName, $verb) {
    if (-not $rawName) { Err "Which Space?  tekt space $verb <name>"; return $null }
    $name = ConvertTo-SpaceName $rawName
    $dir  = Join-Path $TektSpaces $name
    if (-not $name -or -not (Test-Path -LiteralPath (Join-Path $dir ".tekt-space"))) {
        Err "No Space named '$rawName'. See:  tekt space list"; return $null
    }
    return $dir
}

function Space-Invite($rawName) {   # write the invitation for a Space, and copy it
    $dir = Get-ActiveSpaceDir $rawName "invite"
    if (-not $dir) { return }
    $name     = Split-Path $dir -Leaf
    $provider = Get-SpaceMeta $dir "provider"
    $folder   = Get-SpaceMeta $dir "folder"
    $backend  = Get-SpaceBackend $provider
    if (-not $backend) { $backend = $provider }
    $label    = Get-SpaceLabel $backend
    if (-not $label) { $label = $provider }
    # A folder shared with you lands at the top level under its own name
    $shared = if ($folder) { Split-Path $folder -Leaf } else { $name }
    $join   = 'tekt space add {0} {1} "{2}"' -f $name, $provider, $shared
    switch ($backend) {
        "drive"    { $step1 = 'I''ve shared the folder "{0}" with you on Google Drive. Open "Shared with me", right-click it, choose Organize > Add shortcut, and pick My Drive.' -f $shared }
        "onedrive" { $step1 = 'I''ve shared the folder "{0}" with you on OneDrive. Open the link I sent, then choose "Add shortcut to My files".' -f $shared }
        "dropbox"  { $step1 = 'Accept my invitation to the shared folder "{0}" in {1}.' -f $shared, $label }
        "box"      { $step1 = 'Accept my invitation to the shared folder "{0}" in {1}.' -f $shared, $label }
        "webdav"   { $step1 = 'Accept my invitation to the shared folder "{0}" in {1}.' -f $shared, $label }
        "alias" {
            $remote = Get-SpaceMeta $dir "remote"
            if (-not $remote) { $remote = "tekt-$name" }
            $path = ""
            if (Test-Cmd "rclone") {
                foreach ($line in @(& rclone config show $remote 2>$null)) {
                    if ([string]$line -match '^remote = (.*)$') { $path = $Matches[1].Trim(); break }
                }
            }
            $step1 = 'Make sure you can open {0} on your computer.' -f $(if ($path) { $path } else { "the shared folder" })
            $join  = 'tekt space add {0} folder "{1}"' -f $name, $(if ($path) { $path } else { "<path to the shared folder>" })
        }
        "s3" {
            $step1 = 'Ask me for the S3 endpoint and access keys.'
            $join  = 'tekt space add {0} s3 "{1}"' -f $name, $folder
        }
        default { $step1 = 'Get access to the shared folder "{0}".' -f $shared }
    }
    $msg = @(
        ('Join our "{0}" Space on Tekt: shared documents, knowledge and AI skills.' -f $name),
        "",
        "1. $step1",
        "2. Install Tekt (once):",
        "   macOS / Linux:  curl -fsSL https://tekt.md/install.sh | bash",
        "   Windows:        irm https://tekt.md/install.ps1 | iex",
        "3. Join:                $join",
        "4. Let your AI use it:  tekt connect",
        "Guide: https://tekt.md/spaces/"
    ) -join "`n"
    if ($backend -ne "alias" -and $backend -ne "s3") {
        Log "First share the folder '$folder' in $label with the people you're inviting. Then send them this:"
    }
    Write-Host ""
    Write-Host $msg
    Write-Host ""
    if (Copy-SpaceText $msg) { Success "Copied to your clipboard. Paste it into an email or chat." }
    else                     { Log "Copy the message above and send it to the people you're inviting." }
}

function Space-Open($rawName) {   # open a Space's folder in File Explorer
    $dir = Get-ActiveSpaceDir $rawName "open"
    if (-not $dir) { return }
    try {
        Invoke-Item -LiteralPath $dir -ErrorAction Stop
        Success "Opened $dir"
    } catch {
        Log "Your Space is at: $dir"
    }
}

function Space-Help {
    Write-Host "Usage: tekt space <command>"
    Write-Host "  add <name> [provider] [folder]  Create or join a Space (drive, onedrive, dropbox, box, nextcloud, folder, s3)"
    Write-Host "  list                            Show your Spaces"
    Write-Host "  sync [name]                     Two-way sync now (all Spaces, or just one)"
    Write-Host "  invite <name>                   Write an invitation to a Space (copied to your clipboard)"
    Write-Host "  open <name>                     Open a Space's folder"
    Write-Host "  gui                             Open your storage in a point-and-click window (RcloneView)"
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

# Link one Space's skills (or every Space's) into Claude Code's skills folder, and also into
# pi's (~/.agents/skills) when pi is installed or that folder already exists.
function Link-SpaceSkills($only) {
    $targets = @($TektClaudeSkills)
    if ((Test-Cmd "pi") -or (Test-Path -LiteralPath $TektAgentSkills)) { $targets += $TektAgentSkills }
    foreach ($dir in $targets) { Link-SkillsInto $dir $only }
}

function Link-SkillsInto($skillsDir, $only) {   # link + prune Tekt's <space>--<skill> links in one skills folder
    New-Item -ItemType Directory -Force -Path $skillsDir | Out-Null
    if (-not (Test-Path -LiteralPath $skillsDir)) { Warn "Couldn't create $skillsDir"; return }
    $root = Get-SpacesRootFull

    # Drop Tekt's links whose skill is gone, or whose Space was disconnected.
    foreach ($link in @([IO.Directory]::GetFileSystemEntries($skillsDir, "*--*"))) {
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
            $link = Join-Path $skillsDir "$name--$($skill.Name)"
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

# -- Skill shelf: hand-curated skills from the Tekt catalog (tekt skill shelf | add)
function Get-TektCatalogFile {   # $TEKT_CATALOG, the catalog next to this script, or a fresh copy from tekt.md; $null if none
    if ($env:TEKT_CATALOG -and (Test-Path -LiteralPath $env:TEKT_CATALOG -PathType Leaf)) { return $env:TEKT_CATALOG }
    if ($PSScriptRoot) {
        $here = Join-Path $PSScriptRoot "tekt.catalog.yaml"
        if (Test-Path -LiteralPath $here -PathType Leaf) { return $here }
    }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) "tekt.catalog.$PID.yaml"
    try {
        Invoke-WebRequest -Uri "https://tekt.md/tekt.catalog.yaml" -OutFile $tmp -UseBasicParsing -ErrorAction Stop
        return $tmp
    } catch { return $null }
}

# Entries under skills: as objects { Name, Summary, Source } - plain regex, no YAML module needed.
# The block starts at "skills:" and ends at the next line that starts without a space.
function Get-CatalogSkills($file) {
    $skills = [System.Collections.Generic.List[object]]::new()
    $on = $false; $cur = $null
    foreach ($line in [IO.File]::ReadAllLines($file)) {
        if (-not $on) { if ($line -match '^skills:') { $on = $true }; continue }
        if ($line -match '^[^ #]') { break }
        if ($line -match '^  ([a-z0-9-]+):\s*$') {
            $cur = [pscustomobject]@{ Name = $Matches[1]; Summary = ""; Source = "" }
            $skills.Add($cur)
            continue
        }
        if (-not $cur) { continue }
        if ($line -match '^    summary:\s*"?(.*?)"?\s*$') { $cur.Summary = $Matches[1]; continue }
        if ($line -match '^    source:\s*(\S+)') { $cur.Source = $Matches[1].Trim('"'); continue }
    }
    return $skills.ToArray()
}

function Skill-Shelf {
    Section "The skill shelf - hand-curated skills"
    $cat = Get-TektCatalogFile
    if (-not $cat) { Err "Couldn't read the catalog. Check your connection and try again."; return }
    foreach ($s in @(Get-CatalogSkills $cat)) {
        $inSpace = @(Get-ChildItem -LiteralPath $TektSpaces -Directory -ErrorAction Ignore |
            Where-Object { Test-Path -LiteralPath (Join-Path (Join-Path (Join-Path $_.FullName "skills") $s.Name) "SKILL.md") }).Count -gt 0
        $personal = Test-Path -LiteralPath (Join-Path (Join-Path $TektClaudeSkills $s.Name) "SKILL.md")
        $have = if ($inSpace -or $personal) { "  (you have it)" } else { "" }
        if ($s.Source) { Write-Host "  * " -ForegroundColor Green -NoNewline }
        else           { Write-Host "  o " -ForegroundColor Yellow -NoNewline }
        Write-Host ("{0,-24} {1}{2}" -f $s.Name, $s.Summary, $have)
    }
    Log "* add with:  tekt skill add <skill> [space]    o not a standalone skill yet - see https://tekt.md/catalog/#skill"
}

function Skill-Add($rawName, $rawSpace) {
    if (-not $rawName) { Err "Which skill?  tekt skill add <skill> [space]   (see: tekt skill shelf)"; return }
    $name = ([string]$rawName).Trim().ToLowerInvariant()
    $cat  = Get-TektCatalogFile
    if (-not $cat) { Err "Couldn't read the catalog. Check your connection and try again."; return }
    $entry = @(Get-CatalogSkills $cat | Where-Object { $_.Name -eq $name }) | Select-Object -First 1
    if (-not $entry) { Err "'$name' isn't on the shelf. See:  tekt skill shelf"; return }
    if (-not $entry.Source) {
        Warn "'$name' isn't a standalone skill yet. It comes with the arkitype plugin in Claude Code:"
        Warn "  /plugin marketplace add xingh/arkitype   then   /plugin install arkitype@arkitype"
        return
    }

    $space = ""
    if ($rawSpace) {
        $space = ConvertTo-SpaceName $rawSpace
    } else {
        $dirs = @(Get-SpaceDirs)
        if ($dirs.Count -eq 1) { $space = Split-Path $dirs[0] -Leaf }
        elseif ($dirs.Count -gt 1) { Err "You have several Spaces. Pick one:  tekt skill add $name <space>   (see: tekt space list)"; return }
    }
    if ($space) {
        $sdir = Join-Path $TektSpaces $space
        if (-not (Test-Path -LiteralPath (Join-Path $sdir ".tekt-space"))) { Err "No Space named '$rawSpace'. See:  tekt space list"; return }
        $dest = Join-Path (Join-Path $sdir "skills") $name
    } else {
        $dest = Join-Path $TektClaudeSkills $name   # no Spaces yet: just for you
    }
    $md = Join-Path $dest "SKILL.md"
    if (Test-Path -LiteralPath $md) { Warn "You already have '$name' ($md)."; return }

    $created = -not (Test-Path -LiteralPath $dest)
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    try {
        Invoke-WebRequest -Uri $entry.Source -OutFile $md -UseBasicParsing -ErrorAction Stop
    } catch {
        # Only remove what this command made: never a folder that was already there
        if ($created) { Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction Ignore }
        else          { Remove-Item -LiteralPath $md -Force -ErrorAction Ignore }
        Err "Couldn't download '$name'. Check your connection and try again."
        return
    }
    if ($space) {
        Link-SpaceSkills $space
        Success "Added '$name' to the $space Space and to your Claude Code."
        Log "Run  tekt space sync $space  and everyone in the Space gets it."
    } else {
        Success "Added '$name' to your Claude Code ($dest)."
        Log "Make a Space to share skills with people:  tekt space add team drive"
    }
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
        "shelf" { Skill-Shelf }
        "add"   { Skill-Add $a1 $a2 }
        default { Err "Unknown: skill $sub - use list, new, link, shelf or add" }
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

# The Spaces server (tekt-spaces) is one caller of Register-Mcp: npx -y <pkg> <TektSpaces>
function Get-SpacesMcpArgs { @("-y", $TektMcpPkg, $TektSpaces) }

function Connect-ClaudeCode {
    if (-not (Test-Cmd "claude")) {
        Warn "Claude Code isn't installed - skipping. Install: irm https://claude.ai/install.ps1 | iex"
        return $false
    }
    if (Register-Mcp "claude-code" $TektMcpName "" "npx" (Get-SpacesMcpArgs)) {
        Success "Claude Code can use your Spaces (MCP server '$TektMcpName')"
        return $true
    }
    return $false
}

function Connect-ClaudeDesktop {
    if (-not (Test-McpAppPresent "claude-desktop")) {
        Warn "Claude Desktop isn't installed - skipping. Get it at https://claude.ai/download"
        return $false
    }
    if (Register-Mcp "claude-desktop" $TektMcpName "" "npx" (Get-SpacesMcpArgs)) {
        Success "Claude Desktop can use your Spaces after you restart it ($(Get-ClaudeDesktopConfig))"
        return $true
    }
    return $false
}

function Connect-Codex {
    if (-not (Test-Cmd "codex")) {
        Warn "Codex CLI isn't installed - skipping. Install: npm install -g @openai/codex"
        return $false
    }
    if (Register-Mcp "codex" $TektMcpName "" "npx" (Get-SpacesMcpArgs)) {
        Success "Codex can use your Spaces ($(Get-CodexConfig))"
        return $true
    }
    return $false
}

function Get-XdgConfigHome {
    if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $HOME ".config" }
}
function Get-OpenCodeConfig { Join-Path (Join-Path (Get-XdgConfigHome) "opencode") "opencode.json" }
function Get-CrushConfig    { Join-Path (Join-Path (Get-XdgConfigHome) "crush") "crushrc" }

# $false for JSONC: // or /* comments, or trailing commas, outside strings.
# (PowerShell 7's ConvertFrom-Json accepts comments, and rewriting would drop them.)
function Test-PlainJson($raw) {
    $inStr = $false; $esc = $false; $lastSig = ""
    for ($i = 0; $i -lt $raw.Length; $i++) {
        $c = [string]$raw[$i]
        if ($inStr) {
            if ($esc) { $esc = $false }
            elseif ($c -eq '\') { $esc = $true }
            elseif ($c -eq '"') { $inStr = $false; $lastSig = '"' }
            continue
        }
        if ($c -eq '"') { $inStr = $true; continue }
        if ($c -eq '/' -and ($i + 1) -lt $raw.Length) {
            $next = [string]$raw[$i + 1]
            if ($next -eq '/' -or $next -eq '*') { return $false }
        }
        if (($c -eq '}' -or $c -eq ']') -and $lastSig -eq ',') { return $false }
        if ($c.Trim()) { $lastSig = $c }
    }
    return $true
}

function Connect-OpenCode {
    if (-not (Test-Cmd "opencode")) {
        Warn "opencode isn't installed - skipping. Install: npm i -g opencode-ai@latest"
        return $false
    }
    if (Register-Mcp "opencode" $TektMcpName "" "npx" (Get-SpacesMcpArgs)) {
        Success "opencode can use your Spaces ($(Get-OpenCodeConfig))"
        return $true
    }
    return $false
}

function Connect-Crush {
    if (-not (Test-Cmd "crush")) {
        Warn "crush isn't installed - skipping. Install: winget install charmbracelet.crush"
        return $false
    }
    if (Register-Mcp "crush" $TektMcpName "" "npx" (Get-SpacesMcpArgs)) {
        Success "crush can use your Spaces ($(Get-CrushConfig))"
        return $true
    }
    return $false
}

# -- MCP registration: one writer per AI app, shared by tekt connect and tekt tool --
# Register-Mcp <app> <name> <env "KEY=VALUE" or ""> <command> <args[]>
# On Windows every launch is "cmd /c <command> <args...>". Re-running replaces Tekt's
# entry of that name and leaves everything else in the config alone. Formats stay
# compatible with configs written by v0.3/v0.8 (same Codex header, same crush markers).
$McpApps = @("claude-code", "claude-desktop", "codex", "opencode", "crush")

function Get-McpAppLabel($app) {
    switch ($app) {
        "claude-code"    { return "Claude Code" }
        "claude-desktop" { return "Claude Desktop" }
        "codex"          { return "Codex" }
        "opencode"       { return "opencode" }
        "crush"          { return "crush" }
    }
    return [string]$app
}

function Resolve-McpApp($app) {   # a word the user typed -> app id, or ""
    switch -Regex (([string]$app).Trim().ToLowerInvariant()) {
        '^(claude-code|claude|code)$' { return "claude-code" }
        '^(claude-desktop|desktop)$'  { return "claude-desktop" }
        '^(codex|opencode|crush)$'    { return $Matches[1] }
    }
    return ""
}

function Test-McpAppPresent($app) {
    switch ($app) {
        "claude-code"    { return (Test-Cmd "claude") }
        "claude-desktop" { return ((Test-ClaudeDesktop) -or (Test-Path -LiteralPath (Split-Path (Get-ClaudeDesktopConfig) -Parent))) }
        "codex"          { return (Test-Cmd "codex") }
        "opencode"       { return (Test-Cmd "opencode") }
        "crush"          { return (Test-Cmd "crush") }
    }
    return $false
}

function Split-McpEnv($envKV) {   # "KEY=VALUE" -> @(KEY, VALUE); @() when empty
    if (-not $envKV) { return @() }
    $i = ([string]$envKV).IndexOf("=")
    if ($i -lt 1) { return @() }
    return @($envKV.Substring(0, $i), $envKV.Substring($i + 1))
}

function ConvertTo-TomlString($s) {   # TOML literal '...' (no backslash escaping) unless it contains '
    if ($s.Contains("'")) { return '"' + (($s -replace '\\', '\\') -replace '"', '\"') + '"' }
    return "'" + $s + "'"
}

function ConvertTo-CrushArg($s) {   # crushrc is Bash: a bare word when safe, else "..." with \ " $ ` escaped
    if ($s -cmatch '^(/[A-Za-z]|[A-Za-z0-9@%+=:,._-][A-Za-z0-9@%+=:,./_-]*)$') { return $s }
    return '"' + ($s -replace '([\\"$`])', '\$1') + '"'
}

# Open a JSON config for editing, backing it up first. Returns @{ Ok; Data; Why }.
# JSONC (comments/trailing commas) and invalid JSON are refused, so they're never rewritten.
function Open-McpJson($cfg) {
    if (-not (Test-Path -LiteralPath $cfg)) { return @{ Ok = $true; Data = $null; Why = "" } }
    try { Copy-Item -LiteralPath $cfg -Destination "$cfg.bak-tekt" -Force -ErrorAction Stop }
    catch { return @{ Ok = $false; Data = $null; Why = "backup" } }
    $raw = [IO.File]::ReadAllText($cfg)
    if (-not $raw.Trim()) { return @{ Ok = $true; Data = $null; Why = "" } }
    if (-not (Test-PlainJson $raw)) { return @{ Ok = $false; Data = $null; Why = "jsonc" } }
    try { $data = $raw | ConvertFrom-Json -ErrorAction Stop } catch { return @{ Ok = $false; Data = $null; Why = "invalid" } }
    if ($data -isnot [System.Management.Automation.PSCustomObject]) { return @{ Ok = $false; Data = $null; Why = "invalid" } }
    return @{ Ok = $true; Data = $data; Why = "" }
}

function Get-McpJsonMap($data, $prop) {   # $data.$prop as an object (created if missing); $null if it's something else
    $p = $data.PSObject.Properties[$prop]
    if (-not $p -or $null -eq $p.Value) {
        $data | Add-Member -NotePropertyName $prop -NotePropertyValue ([pscustomobject]@{}) -Force
        return $data.$prop
    }
    if ($p.Value -isnot [System.Management.Automation.PSCustomObject]) { return $null }
    return $p.Value
}

function Save-McpJson($cfg, $data) {
    try {
        [IO.File]::WriteAllText($cfg, ($data | ConvertTo-Json -Depth 20) + "`n", (New-Object System.Text.UTF8Encoding $false))
        return $true
    } catch {
        Warn "Couldn't write $cfg. Your previous version is in $cfg.bak-tekt"
        return $false
    }
}

# Lines of a text config without Tekt's block. $end = "" means TOML: the block runs
# from the $begin header up to the next line starting with "[". Returns @{ Lines; Found }.
function Read-LinesWithoutBlock($cfg, $begin, $end) {
    $kept = [System.Collections.Generic.List[string]]::new()
    $found = $false
    if (Test-Path -LiteralPath $cfg) {
        $skip = $false
        foreach ($line in [IO.File]::ReadAllLines($cfg)) {
            if ($end) {
                if (-not $skip -and $line -eq $begin) { $skip = $true; $found = $true; continue }
                if ($skip) { if ($line -eq $end) { $skip = $false }; continue }
            } else {
                if ($line.Trim() -eq $begin) { $skip = $true; $found = $true; continue }
                if ($line.StartsWith("[")) { $skip = $false }
                if ($skip) { continue }
            }
            $kept.Add($line)
        }
        while ($kept.Count -gt 0 -and -not $kept[$kept.Count - 1].Trim()) { $kept.RemoveAt($kept.Count - 1) }
    }
    return @{ Lines = $kept; Found = $found }
}

function Save-McpLines($cfg, $lines) {
    $text = if ($lines.Count -gt 0) { ($lines -join "`n") + "`n" } else { "" }
    try {
        [IO.File]::WriteAllText($cfg, $text, (New-Object System.Text.UTF8Encoding $false))
        return $true
    } catch {
        Warn "Couldn't write $cfg. Your previous version is in $cfg.bak-tekt"
        return $false
    }
}

function Backup-McpFile($cfg) {   # $true when there's nothing to back up or the copy worked
    if (-not (Test-Path -LiteralPath $cfg)) { return $true }
    try { Copy-Item -LiteralPath $cfg -Destination "$cfg.bak-tekt" -Force -ErrorAction Stop; return $true }
    catch { Warn "Couldn't back up $cfg, so it was left alone."; return $false }
}

function Register-Mcp($app, $name, $envKV, $command, [string[]]$mcpArgs) {
    $mcpArgs = @($mcpArgs | Where-Object { $null -ne $_ -and $_ -ne "" })
    $kv      = @(Split-McpEnv $envKV)
    $launch  = [string[]](@("/c", $command) + $mcpArgs)   # every launch: cmd /c <command> <args...>
    switch ($app) {
        "claude-code" {
            & claude @("mcp", "remove", "--scope", "user", $name) 2>$null | Out-Null
            $cl = @("mcp", "add", "--scope", "user", $name)
            if ($kv.Count -eq 2) { $cl += @("-e", "$($kv[0])=$($kv[1])") }   # after the name: -e takes several values
            $cl += @("--", "cmd") + $launch                                  # '--' as an array element reaches claude untouched
            & claude @cl 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { return $true }
            $envPart = if ($kv.Count -eq 2) { "-e $($kv[0])=`"$($kv[1])`" " } else { "" }
            $shown   = ($launch | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join " "
            Warn "Claude Code didn't accept '$name'. Add it by hand:"
            Warn "  claude mcp add --scope user $name $envPart-- cmd $shown"
            return $false
        }
        "claude-desktop" {
            $cfg = Get-ClaudeDesktopConfig
            New-Item -ItemType Directory -Force -Path (Split-Path $cfg -Parent) | Out-Null
            $untouched = "Couldn't update $cfg (the file must be valid JSON). Your original is untouched."
            $r = Open-McpJson $cfg
            if (-not $r.Ok) {
                if ($r.Why -eq "backup") { Warn "Couldn't back up $cfg, so it was left alone." } else { Warn $untouched }
                return $false
            }
            $data = if ($null -eq $r.Data) { [pscustomobject]@{} } else { $r.Data }
            $map  = Get-McpJsonMap $data "mcpServers"
            if ($null -eq $map) { Warn $untouched; return $false }
            $server = [pscustomobject]@{ command = "cmd"; args = $launch }
            if ($kv.Count -eq 2) { $server | Add-Member -NotePropertyName "env" -NotePropertyValue ([pscustomobject]@{ $kv[0] = $kv[1] }) }
            $map | Add-Member -NotePropertyName $name -NotePropertyValue $server -Force
            return (Save-McpJson $cfg $data)
        }
        "codex" {
            $cfg    = Get-CodexConfig
            $header = "[mcp_servers.$name]"
            New-Item -ItemType Directory -Force -Path (Split-Path $cfg -Parent) | Out-Null
            if (-not (Backup-McpFile $cfg)) { return $false }
            $lines = (Read-LinesWithoutBlock $cfg $header "").Lines
            if ($lines.Count -gt 0) { $lines.Add("") }
            $lines.Add($header)
            $lines.Add('command = "cmd"')
            $lines.Add("args = [" + (($launch | ForEach-Object { ConvertTo-TomlString $_ }) -join ", ") + "]")
            if ($kv.Count -eq 2) { $lines.Add("env = { $($kv[0]) = $(ConvertTo-TomlString $kv[1]) }") }
            return (Save-McpLines $cfg $lines)
        }
        "opencode" {
            $cfg = Get-OpenCodeConfig
            New-Item -ItemType Directory -Force -Path (Split-Path $cfg -Parent) | Out-Null
            $server = [pscustomobject]@{ type = "local"; command = [string[]](@("cmd") + $launch); enabled = $true }
            if ($kv.Count -eq 2) { $server | Add-Member -NotePropertyName "environment" -NotePropertyValue ([pscustomobject]@{ $kv[0] = $kv[1] }) }
            $snippet = "  `"$name`": " + ($server | ConvertTo-Json -Compress -Depth 5)
            $r = Open-McpJson $cfg
            if (-not $r.Ok) {
                if ($r.Why -eq "backup") { Warn "Couldn't back up $cfg, so it was left alone." }
                else { Warn "Couldn't update $cfg by itself (it may contain comments). Add this under `"mcp`":"; Warn $snippet }
                return $false
            }
            $data = if ($null -eq $r.Data) { [pscustomobject]@{ '$schema' = "https://opencode.ai/config.json" } } else { $r.Data }
            $map  = Get-McpJsonMap $data "mcp"
            if ($null -eq $map) {
                Warn "Couldn't update $cfg by itself. Add this under `"mcp`":"; Warn $snippet
                return $false
            }
            $map | Add-Member -NotePropertyName $name -NotePropertyValue $server -Force
            return (Save-McpJson $cfg $data)
        }
        "crush" {
            $cfg   = Get-CrushConfig
            $begin = "# >>> $name (managed by tekt connect) >>>"
            $end   = "# <<< $name <<<"
            New-Item -ItemType Directory -Force -Path (Split-Path $cfg -Parent) | Out-Null
            if (-not (Backup-McpFile $cfg)) { return $false }
            $lines = (Read-LinesWithoutBlock $cfg $begin $end).Lines
            $line  = "mcp add $name --command cmd" + (($launch | ForEach-Object { " --args " + (ConvertTo-CrushArg $_) }) -join "")
            if ($kv.Count -eq 2) { $line += " --env $($kv[0]) " + '"' + ($kv[1] -replace '([\\"$`])', '\$1') + '"' }
            if ($lines.Count -gt 0) { $lines.Add("") }
            $lines.Add($begin)
            $lines.Add($line)
            $lines.Add($end)
            return (Save-McpLines $cfg $lines)
        }
    }
    Err "Unknown AI app '$app'."
    return $false
}

function Remove-McpJsonKey($cfg, $prop, $name) {   # $true if Tekt's entry was there and is gone now
    if (-not (Test-Path -LiteralPath $cfg)) { return $false }
    if (-not (Select-String -LiteralPath $cfg -SimpleMatch "`"$name`"" -Quiet)) { return $false }
    $r = Open-McpJson $cfg
    if (-not $r.Ok) { Warn "Couldn't edit $cfg by itself. Remove the `"$name`" entry under `"$prop`" by hand."; return $false }
    if ($null -eq $r.Data) { return $false }
    $p = $r.Data.PSObject.Properties[$prop]
    if (-not $p -or $p.Value -isnot [System.Management.Automation.PSCustomObject] -or -not $p.Value.PSObject.Properties[$name]) { return $false }
    $p.Value.PSObject.Properties.Remove($name)
    return (Save-McpJson $cfg $r.Data)
}

function Remove-McpLineBlock($cfg, $begin, $end) {   # $true if Tekt's block was there and is gone now
    if (-not (Test-Path -LiteralPath $cfg)) { return $false }
    $r = Read-LinesWithoutBlock $cfg $begin $end
    if (-not $r.Found) { return $false }
    if (-not (Backup-McpFile $cfg)) { return $false }
    return (Save-McpLines $cfg $r.Lines)
}

function Unregister-Mcp($app, $name) {   # $true if Tekt's entry was removed
    switch ($app) {
        "claude-code" {
            if (-not (Test-Cmd "claude")) { return $false }
            # Only claim a removal when Claude Code's config really lists it (don't trust the exit code alone)
            $ccJson = Join-Path $HOME ".claude.json"
            if (-not ((Test-Path -LiteralPath $ccJson) -and (Select-String -LiteralPath $ccJson -SimpleMatch "`"$name`"" -Quiet))) { return $false }
            & claude @("mcp", "remove", "--scope", "user", $name) 2>$null | Out-Null
            return ($LASTEXITCODE -eq 0)
        }
        "claude-desktop" { return (Remove-McpJsonKey (Get-ClaudeDesktopConfig) "mcpServers" $name) }
        "opencode"       { return (Remove-McpJsonKey (Get-OpenCodeConfig) "mcp" $name) }
        "codex"          { return (Remove-McpLineBlock (Get-CodexConfig) "[mcp_servers.$name]" "") }
        "crush"          { return (Remove-McpLineBlock (Get-CrushConfig) "# >>> $name (managed by tekt connect) >>>" "# <<< $name <<<") }
    }
    return $false
}

function Test-McpRegistered($name) {   # is a server of this name in any AI app's config?
    foreach ($f in @((Join-Path $HOME ".claude.json"), (Get-ClaudeDesktopConfig), (Get-OpenCodeConfig))) {
        if ((Test-Path -LiteralPath $f) -and (Select-String -LiteralPath $f -SimpleMatch "`"$name`"" -Quiet)) { return $true }
    }
    $codex = Get-CodexConfig
    if ((Test-Path -LiteralPath $codex) -and (Select-String -LiteralPath $codex -SimpleMatch "[mcp_servers.$name]" -Quiet)) { return $true }
    $crush = Get-CrushConfig
    if ((Test-Path -LiteralPath $crush) -and (Select-String -LiteralPath $crush -SimpleMatch "# >>> $name (managed by tekt connect) >>>" -Quiet)) { return $true }
    return $false
}

# -- Tool shelf: hand-picked MCP servers from the catalog (tekt tool shelf | add | remove)
# Entries under mcp_servers: as { Name, Command, Args, SpaceEnv, Needs, Summary, Status } - plain regex.
function Get-CatalogTools($file) {
    $tools = [System.Collections.Generic.List[object]]::new()
    $on = $false; $cur = $null
    foreach ($line in [IO.File]::ReadAllLines($file)) {
        if (-not $on) { if ($line -match '^mcp_servers:') { $on = $true }; continue }
        if ($line -match '^[^ #]') { break }
        if ($line -match '^  ([a-z0-9-]+):\s*$') {
            $cur = [pscustomobject]@{ Name = $Matches[1]; Command = ""; Args = ""; SpaceEnv = ""; Needs = ""; Summary = ""; Status = "" }
            $tools.Add($cur)
            continue
        }
        if (-not $cur) { continue }
        if ($line -match '^    (command|args|space_env|needs|summary|status):\s*(.*?)\s*$') {
            $field = $Matches[1]; $val = $Matches[2]
            if ($val.Length -ge 2 -and $val.StartsWith('"') -and $val.EndsWith('"')) { $val = $val.Substring(1, $val.Length - 2) }
            switch ($field) {
                "command"   { $cur.Command  = $val }
                "args"      { $cur.Args     = $val }
                "space_env" { $cur.SpaceEnv = $val }
                "needs"     { $cur.Needs    = $val }
                "summary"   { $cur.Summary  = $val }
                "status"    { $cur.Status   = $val }
            }
        }
    }
    return $tools.ToArray()
}

function Tool-Shelf {
    Section "The tool shelf - hand-picked MCP servers for your AI"
    $cat = Get-TektCatalogFile
    if (-not $cat) { Err "Couldn't read the catalog. Check your connection and try again."; return }
    $tools = @(Get-CatalogTools $cat)
    if ($tools.Count -eq 0) { Warn "The catalog doesn't list any tools yet."; return }
    foreach ($t in $tools) {
        $isSpaces = ($t.Name -eq "filesystem")
        $regName  = if ($isSpaces) { $TektMcpName } else { "tekt-$($t.Name)" }
        $ready    = $isSpaces -or ($t.Status -eq "available" -and $t.Command)
        $tag = ""
        if (Test-McpRegistered $regName) { $tag = "  (connected)" }
        elseif ($isSpaces) { $tag = "  (tekt connect)" }
        elseif ($ready -and $t.Needs -and -not (Test-Cmd $t.Needs)) { $tag = "  (needs $($t.Needs))" }
        if ($ready) { Write-Host "  * " -ForegroundColor Green -NoNewline }
        else        { Write-Host "  o " -ForegroundColor Yellow -NoNewline }
        Write-Host ("{0,-22} {1}{2}" -f $t.Name, $t.Summary, $tag)
    }
    Log "* add with:  tekt tool add <server> [space]    o not available yet    filesystem is your Spaces (tekt connect)"
}

function Tool-Add([string[]]$argv) {
    $argv = @($argv)
    $server = ""; $rawSpace = ""; $rawApp = ""
    for ($i = 0; $i -lt $argv.Count; $i++) {
        $a = [string]$argv[$i]
        if ($a -eq "--app" -or $a -eq "-app") { if (($i + 1) -lt $argv.Count) { $rawApp = $argv[$i + 1]; $i++ }; continue }
        if ($a -like "--app=*") { $rawApp = $a.Substring(6); continue }
        if (-not $server) { $server = $a.Trim().ToLowerInvariant() } elseif (-not $rawSpace) { $rawSpace = $a }
    }
    if (-not $server) { Err "Which tool?  tekt tool add <server> [space] [--app <app>]   (see: tekt tool shelf)"; return }
    $cat = Get-TektCatalogFile
    if (-not $cat) { Err "Couldn't read the catalog. Check your connection and try again."; return }
    $t = @(Get-CatalogTools $cat | Where-Object { $_.Name -eq $server }) | Select-Object -First 1
    if (-not $t) { Err "'$server' isn't on the shelf. See:  tekt tool shelf"; return }
    if ($t.Name -eq "filesystem") { Log "'filesystem' is how your AI reaches your Spaces (as '$TektMcpName'). Run:  tekt connect"; return }
    if ($t.Status -ne "available" -or -not $t.Command) {
        Warn "'$server' isn't available yet - it's still being curated. See:  tekt tool shelf"
        return
    }
    if ($t.Needs -and -not (Test-Cmd $t.Needs)) {
        if ($t.Needs -eq "uvx") { Err "'$server' needs uvx - install uv: https://docs.astral.sh/uv/" }
        else                    { Err "'$server' needs $($t.Needs) - install it first, then try again." }
        return
    }

    # Which apps: one (--app) or every app that's present
    $apps = @()
    if ($rawApp) {
        $one = Resolve-McpApp $rawApp
        if (-not $one) { Err "Unknown AI app '$rawApp'. Use: claude-code, claude-desktop, codex, opencode or crush."; return }
        if (-not (Test-McpAppPresent $one)) { Warn "$(Get-McpAppLabel $one) isn't installed on this computer."; return }
        $apps = @($one)
    } else {
        $apps = @($McpApps | Where-Object { Test-McpAppPresent $_ })
        if ($apps.Count -eq 0) { Warn "No AI app found. Tekt adds tools to Claude Code, Claude Desktop, Codex, opencode and crush."; return }
    }

    # Knowledge that lives in a Space: KEY=<TektSpaces>\<space>\<path>
    $envKV = ""; $space = ""; $envPath = ""
    if ($t.SpaceEnv) {
        if ($rawSpace) {
            $space = ConvertTo-SpaceName $rawSpace
        } else {
            $dirs = @(Get-SpaceDirs)
            if ($dirs.Count -eq 1) { $space = Split-Path $dirs[0] -Leaf }
            elseif ($dirs.Count -gt 1) { Err "You have several Spaces. Pick one:  tekt tool add $server <space>   (see: tekt space list)"; return }
        }
        if ($space) {
            $sdir = Join-Path $TektSpaces $space
            if (-not (Test-Path -LiteralPath (Join-Path $sdir ".tekt-space"))) { Err "No Space named '$(if ($rawSpace) { $rawSpace } else { $space })'. See:  tekt space list"; return }
            $kv = @(Split-McpEnv $t.SpaceEnv)
            if ($kv.Count -eq 2) {
                $rel     = $kv[1] -replace '[\\/]', [string][IO.Path]::DirectorySeparatorChar
                $envPath = Join-Path $sdir $rel
                New-Item -ItemType Directory -Force -Path (Split-Path $envPath -Parent) | Out-Null
                $envKV   = "$($kv[0])=$envPath"
            }
        } else {
            Log "No Space yet, so '$server' keeps its data on this computer only. To share it:  tekt space add team drive"
        }
    } elseif ($rawSpace) {
        Log "'$server' doesn't keep anything in a Space, so '$rawSpace' isn't needed."
    }

    Section "Add $server"
    # Registered as tekt-<server>, so Tekt never replaces or removes a server you added yourself
    $regName = "tekt-$server"
    $argList = @(([string]$t.Args) -split '\s+' | Where-Object { $_ })
    $added = 0
    foreach ($app in $apps) {
        if (Register-Mcp $app $regName $envKV $t.Command $argList) {
            Success "$server added to $(Get-McpAppLabel $app)"
            $added++
        }
    }
    if ($added -eq 0) { Warn "'$server' wasn't added to any app - see the messages above."; return }
    Log "Your AI apps list it as '$regName'."
    if ($envPath) { Log "$server keeps its data in $envPath - everyone in the $space Space shares it after  tekt space sync $space" }
    Log "Restart your AI apps to pick it up. Remove it with:  tekt tool remove $server"
}

function Tool-Remove($rawName) {
    if (-not $rawName) { Err "Which tool?  tekt tool remove <server>"; return }
    $server = ([string]$rawName).Trim().ToLowerInvariant()
    $spacesMsg = "'$server' is how your AI reaches your Spaces; tool remove leaves it alone. (It's set up by: tekt connect)"
    if ($server -eq $TektMcpName) { Warn $spacesMsg; return }
    if ($server.StartsWith("tekt-")) { $server = $server.Substring(5) }   # accept memory or tekt-memory
    if ($server -eq "filesystem") { Warn $spacesMsg; return }
    $cat = Get-TektCatalogFile
    if ($cat -and -not (@(Get-CatalogTools $cat | Where-Object { $_.Name -eq $server }).Count)) {
        Err "'$server' isn't on the shelf. See:  tekt tool shelf"; return
    }
    Section "Remove $server"
    $removed = 0
    foreach ($app in $McpApps) {
        if (Unregister-Mcp $app "tekt-$server") { Success "Removed $server from $(Get-McpAppLabel $app)"; $removed++ }
    }
    if ($removed -eq 0) { Log "'$server' wasn't registered with any AI app - nothing to remove." }
}

function Invoke-ToolCmd($argv) {
    $argv = @($argv)
    $sub  = if ($argv.Count -ge 1 -and $argv[0]) { $argv[0] } else { "shelf" }
    $more = @($argv | Select-Object -Skip 1)   # @(): a one-item array must not unroll into a bare string
    switch ($sub) {
        "shelf"  { Tool-Shelf }
        "list"   { Tool-Shelf }
        "ls"     { Tool-Shelf }
        "add"    { Tool-Add $more }
        "remove" { Tool-Remove $(if ($more.Count -ge 1) { $more[0] } else { "" }) }
        "rm"     { Tool-Remove $(if ($more.Count -ge 1) { $more[0] } else { "" }) }
        default  { Err "Unknown: tool $sub - use shelf, add or remove" }
    }
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
        "opencode"       { if (Connect-OpenCode)      { $connected = $true } }
        "crush"          { if (Connect-Crush)         { $connected = $true } }
        "all" {
            if (Test-Cmd "claude") { if (Connect-ClaudeCode) { $connected = $true } }
            if ((Test-ClaudeDesktop) -or (Test-Path -LiteralPath (Split-Path (Get-ClaudeDesktopConfig) -Parent))) {
                if (Connect-ClaudeDesktop) { $connected = $true }
            }
            if (Test-Cmd "codex")    { if (Connect-Codex)    { $connected = $true } }
            if (Test-Cmd "opencode") { if (Connect-OpenCode) { $connected = $true } }
            if (Test-Cmd "crush")    { if (Connect-Crush)    { $connected = $true } }
        }
        default {
            Err "Unknown AI app '$app'. Use: claude-code, claude-desktop, codex, opencode, crush or all."
            return
        }
    }
    # Skills are a Claude Code feature: only (re)link them when connecting Claude Code (or all)
    $forClaudeCode = @("all", "claude-code", "claude", "code") -contains ([string]$app).ToLowerInvariant()
    if ($forClaudeCode -and ((Test-Cmd "claude") -or (Test-Path -LiteralPath (Join-Path $HOME ".claude")))) {
        Link-SpaceSkills
        Success "Shared skills from your Spaces are linked into Claude Code ($TektClaudeSkills)"
    }
    if (-not (Test-Cmd "npx")) {
        Warn "Your AI apps start the Spaces server with npx, which comes with Node.js. Install it first:  winget install OpenJS.NodeJS.LTS"
    }
    Write-Host ""
    if (-not $connected) { Warn "No AI app connected yet. Tekt connects Claude Code, Claude Desktop, Codex, opencode and crush." }
    Log "Other MCP apps: add a server with  command: cmd   args: /c npx -y $TektMcpPkg $TektSpaces"
    Log "Running MCPHub (tekt mcp)? Apps can also use http://localhost:3000/mcp - it serves /spaces too."
    Log "Try it: ask your AI `"What's in my team Space?`""
}

# -- Status ---------------------------------------------------------------------
function Tekt-Status {
    Refresh-SessionPath   # a tool installed moments ago is on PATH in the registry, not yet in this window
    Write-Host "`nTekt Environment Status - https://tekt.md`n" -ForegroundColor Cyan
    $rows = @(
        @("Tekt.Dev",  "Git",         "git"),
        @("Tekt.Dev",  "GitHub CLI",  "gh"),
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
        @("Tekt.Iris", "Nanobot",     "nanobot"),
        @("Tekt.Iris", "Codex CLI",   "codex"),
        @("Tekt.Iris", "opencode",    "opencode"),
        @("Tekt.Iris", "crush",       "crush"),
        @("Tekt.Iris", "pi",          "pi"),
        @("Tekt.Iris", "omp (oh-my-pi)", "omp")
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
    if (Test-RcloneViewInstalled) {   # optional: never counted as missing
        Write-Host ("  [OK]  {0,-16} installed" -f "RcloneView") -ForegroundColor Green
    } else {
        Write-Host ("  [ ?]  {0,-16} optional window onto your Spaces - tekt space gui" -f "RcloneView") -ForegroundColor Yellow
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
    $ocJson  = Get-OpenCodeConfig
    $crushRc = Get-CrushConfig
    if ((Test-Path -LiteralPath $ocJson) -and (Select-String -LiteralPath $ocJson -SimpleMatch "`"$TektMcpName`"" -Quiet)) {
        Write-Host ("  [OK]  {0,-16} uses your Spaces" -f "opencode") -ForegroundColor Green; $capps++
    }
    if ((Test-Path -LiteralPath $crushRc) -and (Select-String -LiteralPath $crushRc -SimpleMatch "mcp add $TektMcpName" -Quiet)) {
        Write-Host ("  [OK]  {0,-16} uses your Spaces" -f "crush") -ForegroundColor Green; $capps++
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
    $TektResults.Clear()
    Test-WingetSources

    # The catalog installs every entry marked `managed: catalog`; the rest still
    # run through their Install-* function below. Under `irm | iex` the catalog
    # comes from tekt.md, and if it can't be read the functions cover everything.
    if (Initialize-Catalog) {
        $fromCatalog = @($CatalogTools | Where-Object { Test-CatalogManaged $_ } | ForEach-Object { $_.Key })
        Log "Catalog: $CatalogFile - $($fromCatalog -join ', ') installed from catalog data"
    } else {
        Warn "Catalog not readable - installing with the built-in steps only."
    }

    # Tekt.Dev
    Install-CatalogLayer "tekt.dev"
    Install-Winget "Git"            "Git.Git"                    "git"
    Install-Winget "GitHub CLI"     "GitHub.cli"                 "gh"
    Install-Winget "Go"             "GoLang.Go"                  "go"
    Install-Winget "Python 3.12"    "Python.Python.3.12"         "python"
    Install-Winget "Node.js LTS"    "OpenJS.NodeJS.LTS"          "node"
    Install-Winget "VS Code"        "Microsoft.VisualStudioCode" "code"
    Install-Winget "Docker Desktop" "Docker.DockerDesktop"       "docker"
    Install-Winget ".NET 10 SDK"    "Microsoft.DotNet.SDK.10"    "dotnet"
    # Tekt.Base
    Install-CatalogLayer "tekt.base"
    Install-Winget "rclone"         "Rclone.Rclone"              "rclone"
    Install-Winget "AWS CLI"        "Amazon.AWSCLI"              "aws"
    Install-TektCli
    Install-RcloneView
    # Tekt.Edge
    Install-CatalogLayer "tekt.edge"
    Install-Winget "Tailscale"      "tailscale.tailscale"        "tailscale"
    Install-Winget "ngrok"          "Ngrok.Ngrok"                "ngrok"
    # Tekt.Iris
    Install-CatalogLayer "tekt.iris"
    Install-Winget "Ollama"         "Ollama.Ollama"              "ollama"
    if (-not (Test-CatalogManaged (Get-CatalogEntry "claude-code"))) { Install-ClaudeCode }
    Install-ClaudeDesktop
    Install-ZedAgent
    Install-OpenClaw
    Install-PicoClaw
    Install-ZeroClaw
    Install-Nanobot
    Install-NanoClaw
    Install-Codex
    if (-not (Test-CatalogManaged (Get-CatalogEntry "opencode"))) { Install-OpenCode }
    if (-not (Test-CatalogManaged (Get-CatalogEntry "crush")))    { Install-Crush }
    if (-not (Test-CatalogManaged (Get-CatalogEntry "pi")))       { Install-Pi }
    if (-not (Test-CatalogManaged (Get-CatalogEntry "omp")))      { Install-Omp }
    Section "Hermes Agent"
    Warn "Hermes has no native Windows build - use WSL2: wsl --install, then bash install.sh"
    # Tekt.Cloud
    Install-CatalogLayer "tekt.cloud"
    Install-Sovrant

    Write-Host ""
    Log "Staged (tekt.cloud): bring up with  .\install.ps1 mcp   and   .\install.ps1 ui"
    Log "Let your AI apps use your Spaces:  tekt connect"
    Log "PATH is refreshed during install. If a new command still isn't found, open a new PowerShell window, then run:  .\install.ps1 status"
    Write-InstallSummary
}

# Dot-sourced (. .\install.ps1)? Define the functions only - handy for tests - and skip the dispatch.
if ($MyInvocation.InvocationName -eq '.') { return }

switch ($Command) {
    "status" { Tekt-Status }
    "mcp"    { Setup-McpHub }
    "ui"     { Setup-Ui }
    "share"  { Tekt-Share $Arg }
    "cli"    { Install-TektCli }
    "gui"    { Tekt-Gui }
    "connect" {
        Refresh-SessionPath
        $app = if ($Rest.Count -ge 1 -and $Rest[0]) { $Rest[0] } else { "all" }
        Tekt-Connect $app
    }
    "tool"   { Refresh-SessionPath; Invoke-ToolCmd $Rest }
    "tools"  { Refresh-SessionPath; Invoke-ToolCmd $Rest }
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
            "invite"   { Space-Invite $a1 }
            "open"     { Space-Open $a1 }
            "gui"      { Tekt-Gui }
            "help"     { Space-Help }
            default    { Err "Unknown: space $sub - use add, list, sync, invite, open, gui, remove or autosync"; Space-Help }
        }
    }
    "help"   {
        Write-Host "Usage: .\install.ps1 [status|catalog|mcp|ui|share <port>|space ...|skill ...|tool ...|connect [app]|gui|cli|help]"
        Write-Host "       (after 'cli' you can type 'tekt' instead of '.\install.ps1')"
        Write-Host "  (none)        Install all Tekt tools"
        Write-Host "  install <tool> Install one tool from the catalog (see: catalog plan)"
        Write-Host "  catalog plan  What the catalog would install on this computer, layer by layer"
        Write-Host "  status        Check which tools are installed"
        Write-Host "  mcp           MCPHub + curated MCP servers (:3000)"
        Write-Host "  ui            LibreChat (:3080) + n8n (:5678)"
        Write-Host "  share <port>  HTTPS tunnel (Tailscale Serve, else ngrok)"
        Write-Host "  cli           Install the 'tekt' command"
        Write-Host "  gui           Same as: space gui"
        Write-Host ""
        Write-Host "Spaces: share docs, knowledge and skills through Google Drive, OneDrive, Dropbox, Box, Nextcloud or a folder"
        Write-Host "  space add <name> [provider] [folder]  Create or join a Space"
        Write-Host "  space list                            Show your Spaces"
        Write-Host "  space sync [name]                     Two-way sync now"
        Write-Host "  space invite <name>                   Write an invitation to a Space (copied to your clipboard)"
        Write-Host "  space open <name>                     Open a Space's folder"
        Write-Host "  space gui                             Open your storage in a point-and-click window (RcloneView)"
        Write-Host "  space remove <name>                   Disconnect a Space (your files are kept)"
        Write-Host "  space autosync on|off                 Sync every 10 minutes in the background"
        Write-Host ""
        Write-Host "  connect [app]  Let your AI apps use your Spaces: all (default), claude-code, claude-desktop, codex, opencode, crush"
        Write-Host ""
        Write-Host "Shared skills: skills in a Space appear in everyone's Claude Code"
        Write-Host "  skill list                            Skills shared in your Spaces, and which are in Claude Code"
        Write-Host "  skill new <space> <name>              Start a skill in a Space; everyone gets it after sync"
        Write-Host "  skill link                            Re-link shared skills into Claude Code (and pi, when installed)"
        Write-Host "  skill shelf                           Hand-curated skills you can add in one step"
        Write-Host "  skill add <skill> [space]             Add a curated skill to a Space (everyone gets it)"
        Write-Host ""
        Write-Host "Tool shelf: hand-picked MCP servers for your AI apps"
        Write-Host "  tool shelf                            The servers you can add, and which are connected"
        Write-Host "  tool add <server> [space] [--app <app>]  Add one to every AI app (or one); memory can live in a Space"
        Write-Host "  tool remove <server>                  Take Tekt's entry out of every AI app"
        Write-Host ""
        Write-Host "Windows note: after installs, restart PowerShell, then run .\install.ps1 status"
    }
    "catalog" {
        if ($Rest.Count -ge 1 -and $Rest[0] -eq "plan") { Show-CatalogPlan }
        elseif (Test-Path $catalogPath) { Get-Content $catalogPath }
        else { irm https://tekt.md/tekt.catalog.yaml }
    }
    "install" {
        # install one tool from the catalog: tekt install <tool>
        $want = if ($Rest.Count -ge 1) { $Rest[0] } else { "" }
        if (-not $want) { Main }
        elseif (-not (Initialize-Catalog)) { Err "Couldn't read the catalog. Check your connection and try again." }
        else {
            $tool = Get-CatalogEntry $want
            if (-not $tool) { Err "'$want' isn't in the catalog. See:  .\install.ps1 catalog plan" }
            elseif (-not (Test-CatalogManaged $tool)) { Err "'$want' is installed by $(Get-CatalogField $tool 'installer_windows'), not from catalog data." }
            else { Refresh-SessionPath; Install-CatalogEntry $tool }
        }
    }
    default  { Main }
}
