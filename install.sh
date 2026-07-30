#!/usr/bin/env bash
# =============================================================================
# tekt-bootstrap.sh
# Tekt Platform — Full Environment Bootstrap
# https://tekt.md
#
# Installs: Homebrew, Go, Python (pyenv), nvm/Node, rclone, AWS CLI,
#           VSCode, Docker, Tailscale, ngrok, Ollama, Claude Code,
#           Claude Desktop (macOS), Zed (+ Agent mode), OpenClaw,
#           PicoClaw, Hermes Agent, ZeroClaw, Nanobot, NanoClaw
# Stages:   MCPHub (+ curated MCP servers), LibreChat, n8n, Sovrant
#
# Supported: macOS (Intel + Apple Silicon), Ubuntu/Debian, Fedora/RHEL, WSL2
# Usage:     curl -fsSL https://tekt.md/install.sh | bash
#            — or —
#            bash install.sh [status|catalog|mcp|ui|share|help]
# Catalog:   version pins live in tekt.catalog.yaml (same directory)
# =============================================================================

set -euo pipefail

# ── Colour output ─────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

log()     { echo -e "${CYAN}[tekt]${RESET} $*"; }
success() { echo -e "${GREEN}[✓]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $*"; }
error()   { echo -e "${RED}[✗]${RESET} $*" >&2; }
section() { echo -e "\n${BOLD}${BLUE}══ $* ══${RESET}"; }

# ── Version targets (edit here to pin versions) ───────────────────────────────
GO_VERSION="1.26.2"
PYTHON_VERSION="3.14"
NODE_VERSION="24"          # Active LTS (Krypton)
NVM_VERSION="0.40.4"
DOTNET_CHANNEL="10.0"      # .NET SDK channel (Sovrant is .NET 10 / C# 14)

# ── Repo / binary sources for Tekt-native tools ───────────────────────────────
OPENCLAW_REPO="https://github.com/openclaw/openclaw"
PICOCLAW_REPO="https://github.com/sipeed/picoclaw"
HERMES_REPO="https://github.com/NousResearch/hermes-agent"
ZEROCLAW_REPO="https://github.com/zeroclaw-labs/zeroclaw"
NANOBOT_REPO="https://github.com/HKUDS/nanobot"          # PyPI: nanobot-ai
NANOCLAW_REPO="https://github.com/qwibitai/nanoclaw"
LIBRECHAT_REPO="https://github.com/danny-avila/LibreChat"
SOVRANT_REPO="https://github.com/ramseur/sovrant"        # BSL 1.1 — public; .NET 10 source build

# ── Container images (tekt.cloud) ─────────────────────────────────────────────
MCPHUB_IMAGE="samanhappy/mcphub:latest"
N8N_IMAGE="docker.n8n.io/n8nio/n8n:latest"

# ── Tekt instance layout ──────────────────────────────────────────────────────
TEKT_HOME="${TEKT_HOME:-$HOME/Tekt}"
TEKT_HOSTNAME="$(hostname -s 2>/dev/null || echo local)"
TEKT_INSTANCE="${TEKT_INSTANCE:-$TEKT_HOME/Instances/$TEKT_HOSTNAME}"
TEKT_WORKSPACE="$TEKT_INSTANCE/workspace"
TEKT_MCP_DIR="$TEKT_INSTANCE/mcp"
TEKT_CLOUD_DIR="$TEKT_INSTANCE/cloud"
TEKT_AGENTS_DIR="$TEKT_INSTANCE/agents"

# ── Catalog pins (tekt.catalog.yaml overrides the defaults above) ─────────────
load_catalog_pins() {
  # Works when run from a checkout; silently skipped under `curl | bash`.
  local script_dir catalog
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd)" || return 0
  catalog="${TEKT_CATALOG:-$script_dir/tekt.catalog.yaml}"
  [ -f "$catalog" ] || return 0
  local key val
  for key in GO_VERSION PYTHON_VERSION NODE_VERSION NVM_VERSION DOTNET_CHANNEL MCPHUB_IMAGE N8N_IMAGE; do
    val="$(grep -E "^[[:space:]]{2}${key}:" "$catalog" 2>/dev/null | head -1 \
           | sed -E 's/^[^:]+:[[:space:]]*"?([^"#]*[^"# ])"?.*$/\1/')"
    [ -n "$val" ] && eval "${key}=\"\$val\""
  done
  log "Loaded version pins from $(basename "$catalog")"
}
load_catalog_pins || true

# ── Helpers ───────────────────────────────────────────────────────────────────
command_exists() { command -v "$1" &>/dev/null; }

claude_desktop_installed() {
  local os; os="$(os_type)"
  if [ "$os" = "macos" ]; then
    [ -d "/Applications/Claude.app" ] || [ -d "$HOME/Applications/Claude.app" ]
  else
    return 1
  fi
}

os_type() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux)  echo "linux" ;;
    *)      echo "unknown" ;;
  esac
}

linux_distro() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "${ID:-unknown}"
  else
    echo "unknown"
  fi
}

arch_type() {
  case "$(uname -m)" in
    arm64|aarch64) echo "arm64" ;;
    x86_64)        echo "amd64" ;;
    *)             echo "unknown" ;;
  esac
}

require_sudo() {
  if [ "$(os_type)" = "linux" ] && [ "$EUID" -ne 0 ]; then
    if ! command_exists sudo; then
      warn "sudo is required but not available. Skipping this step."
      return 1
    fi
    SUDO="sudo"
  else
    SUDO=""
  fi
}

# ── Environment reload helper ─────────────────────────────────────────────────
reload_path() {
  # Temporarily disable strict mode — sourced profiles often have unset vars and non-zero returns
  set +euo pipefail 2>/dev/null
  for f in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.zshrc" "$HOME/.profile"; do
    [ -f "$f" ] && source "$f" 2>/dev/null
  done
  set -euo pipefail

  export PATH="$HOME/.local/bin:$HOME/go/bin:/usr/local/go/bin:$PATH"
  # Homebrew
  if [ -f "/opt/homebrew/bin/brew" ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
  elif [ -f "/usr/local/bin/brew" ]; then
    eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null || true
  elif [ -f "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" 2>/dev/null || true
  fi
  # pyenv
  export PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
  [[ -d "$PYENV_ROOT/bin" ]] && export PATH="$PYENV_ROOT/bin:$PATH"
  command_exists pyenv && eval "$(pyenv init -)" 2>/dev/null || true
  # nvm
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh" 2>/dev/null || true
  # npm global bin (OpenClaw, other global npm packages)
  if command_exists npm; then
    local npm_bin; npm_bin="$(npm prefix -g 2>/dev/null)/bin"
    [[ -d "$npm_bin" ]] && export PATH="$npm_bin:$PATH"
  fi
}

append_to_shell_profile() {
  local line="$1"
  for f in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.zshrc"; do
    [ -f "$f" ] && grep -qF "$line" "$f" 2>/dev/null || echo "$line" >> "$f"
  done
}

# ── Ensure ~/.local/bin exists and is in PATH ─────────────────────────────────
# Called early in main() — PicoClaw (no-sudo fallback) and Hermes both install here
ensure_local_bin() {
  mkdir -p "$HOME/.local/bin"
  append_to_shell_profile 'export PATH="$HOME/.local/bin:$PATH"'
  export PATH="$HOME/.local/bin:$PATH"
}

# =============================================================================
# 1. Git
# =============================================================================
install_git() {
  section "Git"

  if command_exists git; then
    success "Git already installed — $(git --version)"
    return
  fi

  local os; os="$(os_type)"

  if [ "$os" = "macos" ]; then
    # On macOS, git comes with Xcode Command Line Tools (installed before Homebrew)
    log "Installing Xcode Command Line Tools (includes Git)..."
    xcode-select --install 2>/dev/null || true
    # Wait for xcode-select to finish
    until command_exists git; do
      sleep 5
    done
  else
    require_sudo
    local distro; distro="$(linux_distro)"
    case "$distro" in
      ubuntu|debian|linuxmint|pop)
        $SUDO apt-get update -q
        $SUDO apt-get install -y -q git
        ;;
      fedora|rhel|centos|rocky|alma)
        $SUDO dnf install -y git
        ;;
      arch|manjaro)
        $SUDO pacman -S --noconfirm git
        ;;
      *)
        warn "Unknown distro ($distro) — install git manually."
        return
        ;;
    esac
  fi

  if command_exists git; then
    success "Git $(git --version) installed"
  else
    warn "Git installation failed. Many downstream tools depend on Git."
    warn "Install manually: https://git-scm.com/downloads"
  fi
}

# =============================================================================
# 2. Homebrew
# =============================================================================
install_homebrew() {
  section "Homebrew"
  if command_exists brew; then
    success "brew already installed — $(brew --version | head -1)"
    brew update --quiet
    return
  fi

  log "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Add brew to PATH for this session
  if [ "$(os_type)" = "macos" ]; then
    if [ "$(arch_type)" = "arm64" ]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
      append_to_shell_profile 'eval "$(/opt/homebrew/bin/brew shellenv)"'
    else
      eval "$(/usr/local/bin/brew shellenv)"
      append_to_shell_profile 'eval "$(/usr/local/bin/brew shellenv)"'
    fi
  else
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    append_to_shell_profile 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"'
  fi

  success "Homebrew installed"
}

# =============================================================================
# System dependencies (Linux only)
# =============================================================================
install_system_deps() {
  [ "$(os_type)" = "linux" ] || return 0
  section "System Dependencies"
  require_sudo
  local distro; distro="$(linux_distro)"
  log "Detected Linux distro: $distro"

  case "$distro" in
    ubuntu|debian|linuxmint|pop)
      $SUDO apt-get update -q
      $SUDO apt-get install -y -q \
        make build-essential curl wget git unzip zip tar \
        libssl-dev libffi-dev zlib1g-dev libbz2-dev \
        libreadline-dev libsqlite3-dev libncursesw5-dev \
        xz-utils tk-dev libxml2-dev libxmlsec1-dev \
        liblzma-dev ca-certificates gnupg
      ;;
    fedora|rhel|centos|rocky|alma)
      $SUDO dnf groupinstall -y "Development Tools"
      $SUDO dnf install -y \
        make gcc patch curl wget git unzip zip tar \
        openssl-devel libffi-devel zlib-devel bzip2 bzip2-devel \
        readline-devel sqlite sqlite-devel tk-devel \
        xz-devel libuuid-devel gdbm-libs libnsl2 \
        ca-certificates gnupg2
      ;;
    arch|manjaro)
      $SUDO pacman -Syu --noconfirm base-devel curl wget git unzip openssl
      ;;
    *)
      warn "Unknown distro ($distro) — skipping system dep install; install build-essential or equivalent manually."
      ;;
  esac
  success "System dependencies ready"
}

# =============================================================================
# 3. Go
# =============================================================================
install_go() {
  section "Go $GO_VERSION"
  if command_exists go; then
    local installed; installed="$(go version | awk '{print $3}' | tr -d 'go')"
    success "Go already installed — $installed"
    return
  fi

  local os arch tarball dl_url
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(arch_type)"
  [ "$arch" = "amd64" ] || arch="arm64"
  tarball="go${GO_VERSION}.${os}-${arch}.tar.gz"
  dl_url="https://go.dev/dl/${tarball}"

  log "Downloading $tarball from go.dev..."
  curl -fsSL "$dl_url" -o "/tmp/$tarball"
  require_sudo
  $SUDO rm -rf /usr/local/go
  $SUDO tar -C /usr/local -xzf "/tmp/$tarball"
  rm -f "/tmp/$tarball"

  append_to_shell_profile 'export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"'
  export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"
  success "Go $(go version) installed"
}

# =============================================================================
# 4. Python via pyenv
# =============================================================================
install_python() {
  section "Python $PYTHON_VERSION (pyenv)"

  if ! command_exists pyenv; then
    log "Installing pyenv..."
    curl -fsSL https://pyenv.run | bash

    # Shell configuration per official pyenv docs
    append_to_shell_profile 'export PYENV_ROOT="$HOME/.pyenv"'
    append_to_shell_profile '[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"'

    # Detect current shell for correct init command
    local current_shell
    current_shell="$(basename "$SHELL")"
    if [ "$current_shell" = "zsh" ]; then
      append_to_shell_profile 'eval "$(pyenv init - zsh)"'
    else
      append_to_shell_profile 'eval "$(pyenv init - bash)"'
    fi

    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"
  else
    success "pyenv already installed — $(pyenv --version)"
  fi

  # Check if the target major.minor is already installed
  if pyenv versions --bare | grep -q "^${PYTHON_VERSION}"; then
    success "Python $PYTHON_VERSION already available via pyenv"
  else
    log "Building Python $PYTHON_VERSION (this may take a few minutes)..."
    pyenv install "$PYTHON_VERSION"
  fi

  pyenv global "$PYTHON_VERSION"
  success "Python $(python3 --version) set as global"

  log "Upgrading pip..."
  pip install --upgrade pip --quiet
}

# =============================================================================
# 4. nvm + Node.js + npm
# =============================================================================
install_nvm_node() {
  section "nvm $NVM_VERSION + Node.js $NODE_VERSION LTS"

  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

  if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    log "Installing nvm $NVM_VERSION..."
    curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" | bash

    # nvm's install script auto-appends to shell profiles, but ensure the
    # XDG-aware snippet from the official docs is present
    append_to_shell_profile 'export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"'
    append_to_shell_profile '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"'
    append_to_shell_profile '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"'
  else
    success "nvm already installed"
  fi

  source "$NVM_DIR/nvm.sh"

  if nvm ls "$NODE_VERSION" &>/dev/null; then
    success "Node $NODE_VERSION already installed"
  else
    log "Installing Node.js $NODE_VERSION LTS..."
    nvm install "$NODE_VERSION"
  fi

  nvm use "$NODE_VERSION"
  nvm alias default "$NODE_VERSION"
  success "Node $(node --version) / npm $(npm --version)"

  log "Updating npm to latest..."
  npm install -g npm@latest --quiet
}

# =============================================================================
# 7. rclone
# =============================================================================
install_rclone() {
  section "rclone"
  if command_exists rclone; then
    success "rclone already installed — $(rclone version | head -1)"
    return
  fi

  log "Installing rclone from rclone.org..."
  require_sudo
  $SUDO -v
  curl https://rclone.org/install.sh | $SUDO bash

  success "rclone $(rclone version | head -1 | awk '{print $2}') installed"
}

# =============================================================================
# 8. AWS CLI + s3 utilities
# =============================================================================
install_s3_tools() {
  section "AWS CLI + s3 utilities"
  require_sudo

  # ── AWS CLI v2 ──────────────────────────────────────────────────────────────
  if command_exists aws; then
    success "aws-cli already installed — $(aws --version)"
  else
    log "Installing AWS CLI v2..."
    local os arch tmpdir
    os="$(os_type)"
    arch="$(arch_type)"
    tmpdir="$(mktemp -d)"

    if [ "$os" = "macos" ]; then
      curl -fsSL "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "$tmpdir/AWSCLIV2.pkg"
      $SUDO installer -pkg "$tmpdir/AWSCLIV2.pkg" -target /
    else
      local zip_name
      if [ "$arch" = "arm64" ]; then
        zip_name="awscli-exe-linux-aarch64.zip"
      else
        zip_name="awscli-exe-linux-x86_64.zip"
      fi
      curl -fsSL "https://awscli.amazonaws.com/${zip_name}" -o "$tmpdir/awscliv2.zip"
      unzip -q "$tmpdir/awscliv2.zip" -d "$tmpdir"
      $SUDO "$tmpdir/aws/install" --update
    fi
    rm -rf "$tmpdir"
    success "AWS CLI $(aws --version) installed"
  fi

  # ── s3cmd ──────────────────────────────────────────────────────────────────
  if command_exists s3cmd; then
    success "s3cmd already installed"
  else
    log "Installing s3cmd via pip..."
    pip install s3cmd --quiet
    success "s3cmd installed"
  fi

  # ── s5cmd (fast parallel S3 client) ────────────────────────────────────────
  if command_exists s5cmd; then
    success "s5cmd already installed"
  else
    log "Installing s5cmd..."
    if command_exists brew; then
      brew install peak/tap/s5cmd --quiet
    else
      go install github.com/peak/s5cmd/v2@v2.3.0
    fi
    success "s5cmd installed"
  fi
}

# =============================================================================
# 5. Visual Studio Code
# =============================================================================
install_vscode() {
  section "Visual Studio Code"
  local os; os="$(os_type)"

  if command_exists code; then
    success "VSCode already installed — $(code --version | head -1)"
    return
  fi

  log "Installing VSCode..."

  if [ "$os" = "macos" ]; then
    if command_exists brew; then
      brew install --cask visual-studio-code --quiet
    else
      warn "Install VSCode manually from https://code.visualstudio.com"
      return
    fi
  else
    local distro; distro="$(linux_distro)"
    case "$distro" in
      ubuntu|debian|linuxmint|pop)
        require_sudo
        # Import GPG key (per official VS Code docs)
        $SUDO apt-get install -y -q wget gpg
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
          | gpg --dearmor > /tmp/microsoft.gpg
        $SUDO install -D -o root -g root -m 644 /tmp/microsoft.gpg \
          /usr/share/keyrings/microsoft.gpg
        rm -f /tmp/microsoft.gpg

        # DEB822 .sources format (current method per VS Code docs)
        cat << 'EOF' | $SUDO tee /etc/apt/sources.list.d/vscode.sources > /dev/null
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /usr/share/keyrings/microsoft.gpg
EOF
        $SUDO apt-get install -y -q apt-transport-https
        $SUDO apt-get update -q
        $SUDO apt-get install -y -q code
        ;;
      fedora|rhel|centos|rocky|alma)
        require_sudo
        $SUDO rpm --import https://packages.microsoft.com/keys/microsoft.asc
        echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" \
          | $SUDO tee /etc/yum.repos.d/vscode.repo > /dev/null
        $SUDO dnf check-update || true
        $SUDO dnf install -y code
        ;;
      *)
        warn "Install VSCode manually from https://code.visualstudio.com/download"
        return
        ;;
    esac
  fi

  success "VSCode installed"
}

# =============================================================================
# 6. Docker & Docker Compose
# =============================================================================
install_docker() {
  section "Docker & Docker Compose"

  if command_exists docker; then
    success "Docker already installed — $(docker --version)"
    # Also check for compose
    if docker compose version &>/dev/null; then
      success "Docker Compose already installed — $(docker compose version 2>/dev/null)"
    else
      log "Docker found but Docker Compose plugin missing. Installing..."
    fi
    return
  fi

  local os; os="$(os_type)"

  if [ "$os" = "macos" ]; then
    if command_exists brew; then
      log "Installing Docker Desktop via Homebrew..."
      brew install --cask docker --quiet
      success "Docker Desktop installed — launch from Applications to start the daemon."
    else
      warn "Install Docker Desktop manually from https://docker.com/products/docker-desktop"
    fi
    return
  fi

  # Linux — use the convenience script from get.docker.com
  require_sudo
  log "Installing Docker Engine via get.docker.com..."
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  $SUDO sh /tmp/get-docker.sh
  rm -f /tmp/get-docker.sh

  # Enable and start Docker
  $SUDO systemctl enable docker.service 2>/dev/null || true
  $SUDO systemctl enable containerd.service 2>/dev/null || true
  $SUDO systemctl start docker 2>/dev/null || true

  # Add current user to docker group (takes effect on next login)
  if [ -n "${SUDO_USER:-}" ]; then
    $SUDO usermod -aG docker "$SUDO_USER"
    log "Added $SUDO_USER to docker group (log out and back in to apply)."
  elif [ "$EUID" -ne 0 ]; then
    $SUDO usermod -aG docker "$USER"
    log "Added $USER to docker group (log out and back in to apply)."
  fi

  # Verify
  if command_exists docker; then
    success "Docker $(docker --version) installed"
    if docker compose version &>/dev/null; then
      success "Docker Compose $(docker compose version 2>/dev/null) installed"
    fi
  else
    warn "Docker installed but not in PATH. Restart your shell."
  fi
}

# =============================================================================
# 9. Claude Code
# =============================================================================
install_claude_code() {
  section "Claude Code"

  if command_exists claude; then
    success "Claude Code already installed — $(claude --version 2>/dev/null || echo 'version unknown')"
    return
  fi

  # Prefer native installer (recommended by Anthropic, no Node.js dependency)
  log "Installing Claude Code via native installer..."
  if curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh 2>/dev/null; then
    bash /tmp/claude-install.sh
    rm -f /tmp/claude-install.sh
    success "Claude Code installed (native)"
  else
    # Fallback to npm if native installer unavailable
    warn "Native installer not reachable. Falling back to npm..."
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

    if command_exists npm; then
      npm install -g @anthropic-ai/claude-code
      success "Claude Code installed (npm)"
    else
      error "Neither native installer nor npm available. Install Claude Code manually."
      error "  Native:  curl -fsSL https://claude.ai/install.sh | bash"
      error "  npm:     npm install -g @anthropic-ai/claude-code"
    fi
  fi
}

# =============================================================================
# 9a. Claude Desktop
# =============================================================================
install_claude_desktop() {
  section "Claude Desktop"

  if claude_desktop_installed; then
    success "Claude Desktop already installed"
    return
  fi

  local os; os="$(os_type)"
  if [ "$os" != "macos" ]; then
    warn "Claude Desktop auto-install is currently macOS-only in this bootstrap."
    warn "Install manually from https://claude.ai/download"
    return
  fi

  if command_exists brew; then
    log "Installing Claude Desktop via Homebrew cask..."
    if brew install --cask claude --quiet; then
      success "Claude Desktop installed"
    else
      warn "Claude Desktop cask install failed."
      warn "Install manually from https://claude.ai/download"
    fi
  else
    warn "Homebrew not available. Install Claude Desktop manually: https://claude.ai/download"
  fi
}

# =============================================================================
# 9b. Zed (with Agent mode)
# =============================================================================
install_zed_agent() {
  section "Zed (Agent)"

  if command_exists zed; then
    success "Zed already installed — $(zed --version 2>/dev/null || echo 'version unknown')"
    return
  fi

  local os; os="$(os_type)"
  if [ "$os" = "macos" ]; then
    if command_exists brew; then
      log "Installing Zed via Homebrew cask..."
      brew install --cask zed --quiet \
        && success "Zed installed (open Zed and enable Agent mode in Assistant settings)" \
        || warn "Zed cask install failed. Install manually: https://zed.dev/download"
    else
      warn "Homebrew not available. Install Zed manually: https://zed.dev/download"
    fi
    return
  fi

  if curl -fsSL https://zed.dev/install.sh -o /tmp/zed-install.sh 2>/dev/null; then
    bash /tmp/zed-install.sh
    rm -f /tmp/zed-install.sh
    reload_path
    if command_exists zed; then
      success "Zed installed — $(zed --version 2>/dev/null || echo 'version unknown')"
      log "Open Zed and enable Agent mode in Assistant settings."
    else
      warn "Zed installer finished, but 'zed' is not in PATH yet. Restart your shell and run: zed --version"
    fi
  else
    warn "Zed installer not reachable. Install manually: https://zed.dev/download"
  fi
}

# =============================================================================
# 10. OpenClaw
# =============================================================================
install_openclaw() {
  section "OpenClaw"

  if command_exists openclaw; then
    success "OpenClaw already installed — $(openclaw --version 2>/dev/null || echo 'version unknown')"
    return
  fi

  # Ensure nvm / node is loaded
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

  # Prefer npm for a quiet, non-interactive bootstrap install.
  log "Installing OpenClaw (non-interactive bootstrap mode)..."
  if command_exists npm; then
    npm install -g openclaw@latest
    success "OpenClaw installed (npm)"
  elif curl -fsSL https://openclaw.ai/install.sh -o /tmp/openclaw-install.sh 2>/dev/null; then
    bash /tmp/openclaw-install.sh
    rm -f /tmp/openclaw-install.sh
    success "OpenClaw installed (script)"
  else
    error "Could not install OpenClaw. Install manually:"
    error "  npm install -g openclaw@latest"
    error "  — or —"
    error "  curl -fsSL https://openclaw.ai/install.sh | bash"
    return
  fi

  if command_exists openclaw; then
    log "OpenClaw interactive onboarding is deferred to keep full install non-interruptive."
    log "Next step (manual): openclaw onboard --install-daemon"
  else
    # npm global bin may not be in PATH — add it
    if command_exists npm; then
      local npm_bin; npm_bin="$(npm prefix -g 2>/dev/null)/bin"
      if [[ -d "$npm_bin" ]]; then
        export PATH="$npm_bin:$PATH"
        append_to_shell_profile "export PATH=\"$(npm prefix -g)/bin:\$PATH\""
        log "Added npm global bin ($npm_bin) to shell profile."
      fi
    fi
    if command_exists openclaw; then
      log "OpenClaw interactive onboarding is deferred to keep full install non-interruptive."
      log "Next step (manual): openclaw onboard --install-daemon"
    else
      warn "openclaw not found in PATH after install. Restart your shell or run: source ~/.bashrc"
    fi
  fi
}

# =============================================================================
# 12. PicoClaw
# =============================================================================
install_picoclaw() {
  section "PicoClaw"

  if command_exists picoclaw; then
    success "PicoClaw already installed — $(picoclaw --version 2>/dev/null || echo 'version unknown')"
    return
  fi

  local os arch binary_name dl_url
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(arch_type)"

  # PicoClaw release binaries use: picoclaw-{os}-{arch} (hyphens, lowercase)
  # e.g. picoclaw-linux-amd64, picoclaw-linux-arm64, picoclaw-darwin-arm64
  case "$os" in
    darwin|linux) ;; # valid
    *)
      warn "Unsupported OS for PicoClaw binary download: $os"
      warn "Build from source: git clone ${PICOCLAW_REPO} && cd picoclaw && make deps && make install"
      return
      ;;
  esac

  binary_name="picoclaw-${os}-${arch}"
  dl_url="${PICOCLAW_REPO}/releases/latest/download/${binary_name}"
  log "Downloading PicoClaw (${binary_name})..."

  if curl -fsSL "$dl_url" -o /tmp/picoclaw 2>/dev/null; then
    chmod +x /tmp/picoclaw
    if command_exists sudo; then
      sudo mv /tmp/picoclaw /usr/local/bin/picoclaw
    else
      mv /tmp/picoclaw "$HOME/.local/bin/picoclaw"
    fi
  else
    warn "Binary download failed (${dl_url})."
    warn "Falling back to build from source..."
    if command_exists go; then
      local tmpdir; tmpdir="$(mktemp -d)"
      git clone --depth 1 "${PICOCLAW_REPO}" "$tmpdir/picoclaw" 2>/dev/null
      if [ -d "$tmpdir/picoclaw" ]; then
        cd "$tmpdir/picoclaw"
        make deps 2>/dev/null || true
        make build 2>/dev/null
        if [ -f build/picoclaw ]; then
          cp build/picoclaw "$HOME/.local/bin/picoclaw"
          chmod +x "$HOME/.local/bin/picoclaw"
        fi
        cd - >/dev/null
      fi
      rm -rf "$tmpdir"
    else
      warn "Go not available for source build. Install PicoClaw manually:"
      warn "  git clone ${PICOCLAW_REPO} && cd picoclaw && make deps && make install"
      return
    fi
  fi

  if command_exists picoclaw; then
    success "PicoClaw installed — $(picoclaw --version 2>/dev/null || echo 'version unknown')"
    log "Run 'picoclaw onboard' to complete setup."
  else
    warn "PicoClaw not found in PATH after install. Continuing..."
  fi
}

# =============================================================================
# 12. Hermes Agent
# =============================================================================
install_hermes() {
  section "Hermes Agent"

  if command_exists hermes; then
    success "Hermes already installed — $(hermes --version 2>/dev/null || echo 'version unknown')"
    return
  fi

  log "Installing Hermes Agent from NousResearch..."
  # The official installer handles everything: Python, Node.js, venv, deps, global symlink
  if curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh -o /tmp/hermes-install.sh 2>/dev/null; then
    bash /tmp/hermes-install.sh
    rm -f /tmp/hermes-install.sh

    # Hermes symlinks to ~/.local/bin/hermes — ensure it's in PATH for this session
    export PATH="$HOME/.local/bin:$PATH"

    if command_exists hermes; then
      success "Hermes Agent installed"
      log "Run 'hermes setup' to configure your LLM provider and messaging."
    else
      warn "Hermes installed but 'hermes' not found in PATH."
      warn "The installer may have placed the binary elsewhere. Check with:"
      warn "  find ~ -name hermes -type f -o -name hermes -type l 2>/dev/null | head -5"
      warn "Then symlink it: ln -sf /path/to/hermes ~/.local/bin/hermes"
    fi
  else
    warn "Hermes install script not reachable."
    warn "Install manually:"
    warn "  git clone --recurse-submodules ${HERMES_REPO}"
    warn "  cd hermes-agent"
    warn "  curl -LsSf https://astral.sh/uv/install.sh | sh"
    warn "  uv venv venv --python 3.11"
    warn "  export VIRTUAL_ENV=\"\$(pwd)/venv\""
    warn "  uv pip install -e \".[all]\""
    warn "  mkdir -p ~/.local/bin && ln -sf \"\$(pwd)/venv/bin/hermes\" ~/.local/bin/hermes"
  fi
}

# =============================================================================
# 14. Tailscale (tekt.edge)
# =============================================================================
install_tailscale() {
  section "Tailscale"

  if command_exists tailscale; then
    success "Tailscale already installed — $(tailscale version 2>/dev/null | head -1 || echo 'version unknown')"
    return
  fi

  if [ "$(os_type)" = "macos" ]; then
    if command_exists brew; then
      brew install --cask tailscale 2>/dev/null || brew install tailscale
      success "Tailscale installed (Homebrew)"
    else
      warn "Homebrew not available. Install Tailscale from https://tailscale.com/download"
      return 1
    fi
  else
    log "Installing Tailscale via official script..."
    if curl -fsSL https://tailscale.com/install.sh -o /tmp/tailscale-install.sh 2>/dev/null; then
      sh /tmp/tailscale-install.sh
      rm -f /tmp/tailscale-install.sh
      success "Tailscale installed"
    else
      warn "Tailscale install script not reachable. Install manually: https://tailscale.com/download"
      return 1
    fi
  fi

  log "Join your tailnet with: sudo tailscale up"
}

# =============================================================================
# 15. ngrok (tekt.edge)
# =============================================================================
install_ngrok() {
  section "ngrok"

  if command_exists ngrok; then
    success "ngrok already installed — $(ngrok version 2>/dev/null || echo 'version unknown')"
    return
  fi

  if [ "$(os_type)" = "macos" ] && command_exists brew; then
    brew install ngrok 2>/dev/null || brew install ngrok/ngrok/ngrok
    success "ngrok installed (Homebrew)"
  elif [ "$(linux_distro)" = "ubuntu" ] || [ "$(linux_distro)" = "debian" ] || [ "$(linux_distro)" = "linuxmint" ]; then
    log "Adding ngrok apt repository..."
    require_sudo || return 1
    curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
      | $SUDO tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
    echo "deb https://ngrok-agent.s3.amazonaws.com buster main" \
      | $SUDO tee /etc/apt/sources.list.d/ngrok.list >/dev/null
    $SUDO apt-get update -qq && $SUDO apt-get install -y ngrok
    success "ngrok installed (apt)"
  else
    # Generic Linux: official tarball
    local arch tgz
    arch="$(arch_type)"
    tgz="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-${arch}.tgz"
    log "Downloading ngrok tarball (${arch})..."
    if curl -fsSL "$tgz" -o /tmp/ngrok.tgz 2>/dev/null; then
      tar -xzf /tmp/ngrok.tgz -C /tmp
      if command_exists sudo; then sudo mv /tmp/ngrok /usr/local/bin/ngrok
      else mv /tmp/ngrok "$HOME/.local/bin/ngrok"; fi
      rm -f /tmp/ngrok.tgz
      success "ngrok installed (binary)"
    else
      warn "ngrok download failed. Install manually: https://ngrok.com/download"
      return 1
    fi
  fi

  log "Connect your account with: ngrok config add-authtoken <token>  (free at dashboard.ngrok.com)"
}

# =============================================================================
# 16. Ollama (tekt.iris — local models)
# =============================================================================
install_ollama() {
  section "Ollama"

  if command_exists ollama; then
    success "Ollama already installed — $(ollama --version 2>/dev/null || echo 'version unknown')"
    return
  fi

  if [ "$(os_type)" = "macos" ]; then
    if command_exists brew; then
      brew install ollama
      success "Ollama installed (Homebrew)"
    else
      warn "Homebrew not available. Download Ollama from https://ollama.com/download"
      return 1
    fi
  else
    log "Installing Ollama via official script..."
    if curl -fsSL https://ollama.com/install.sh -o /tmp/ollama-install.sh 2>/dev/null; then
      sh /tmp/ollama-install.sh
      rm -f /tmp/ollama-install.sh
      success "Ollama installed"
    else
      warn "Ollama install script not reachable. Install manually: https://ollama.com/download"
      return 1
    fi
  fi

  log "Pull a first model with: ollama pull llama3.2"
}

# =============================================================================
# 17. ZeroClaw (tekt.iris — Rust edge agent)
# =============================================================================
install_zeroclaw() {
  section "ZeroClaw"

  if command_exists zeroclaw; then
    success "ZeroClaw already installed — $(zeroclaw --version 2>/dev/null || echo 'version unknown')"
    return
  fi

  log "Installing ZeroClaw (zeroclaw-labs)..."
  if curl -fsSL "https://raw.githubusercontent.com/zeroclaw-labs/zeroclaw/master/install.sh" \
       -o /tmp/zeroclaw-install.sh 2>/dev/null; then
    bash /tmp/zeroclaw-install.sh
    rm -f /tmp/zeroclaw-install.sh
    success "ZeroClaw installed (script)"
  elif command_exists brew; then
    log "Install script not reachable — trying Homebrew..."
    brew install zeroclaw
    success "ZeroClaw installed (Homebrew)"
  else
    warn "Could not install ZeroClaw automatically. Install manually:"
    warn "  brew install zeroclaw"
    warn "  — or —"
    warn "  git clone ${ZEROCLAW_REPO} && cd zeroclaw && cargo install --path . --locked"
    return 1
  fi

  command_exists zeroclaw && log "Run 'zeroclaw quickstart' to configure a provider."
}

# =============================================================================
# 18. Nanobot (tekt.iris — HKUDS lightweight Python agent)
# =============================================================================
install_nanobot() {
  section "Nanobot (HKUDS)"

  if command_exists nanobot; then
    success "Nanobot already installed — $(nanobot --version 2>/dev/null || echo 'version unknown')"
    return
  fi

  reload_path
  if command_exists uv; then
    log "Installing nanobot-ai via uv..."
    uv tool install nanobot-ai && success "Nanobot installed (uv)"
  elif command_exists pip || command_exists pip3; then
    log "Installing nanobot-ai via pip..."
    (pip install --user nanobot-ai 2>/dev/null || pip3 install --user nanobot-ai) \
      && success "Nanobot installed (pip)"
  else
    warn "Neither uv nor pip found (Python 3.11+ required). Install manually:"
    warn "  pip install nanobot-ai   # upstream: ${NANOBOT_REPO}"
    return 1
  fi

  log "Run 'nanobot onboard' to create ~/.nanobot and pick a provider (Ollama works)."
  log "Note: this is HKUDS/nanobot. The Go MCP host at nanobot-ai/nanobot is a different project."
}

# =============================================================================
# 19. NanoClaw (tekt.iris — container-isolated Claude agent; staged, not run)
# =============================================================================
install_nanoclaw() {
  section "NanoClaw"

  local dest="$TEKT_AGENTS_DIR/nanoclaw"
  if [ -d "$dest/.git" ]; then
    success "NanoClaw already staged at $dest"
  else
    mkdir -p "$TEKT_AGENTS_DIR"
    log "Cloning NanoClaw (qwibitai)..."
    if git clone --depth 1 "$NANOCLAW_REPO" "$dest" 2>/dev/null; then
      success "NanoClaw staged at $dest"
    else
      warn "Could not clone ${NANOCLAW_REPO}. Stage manually:"
      warn "  git clone ${NANOCLAW_REPO} $dest"
      return 1
    fi
  fi

  log "NanoClaw setup is Claude-Code-guided (interactive). Finish with:"
  log "  cd $dest && claude    # then run /setup inside the session"
  log "Requires: Node 20+, Docker (or Apple Container on macOS), Claude Code."
}

# =============================================================================
# 20a. .NET SDK (tekt.dev — required to build Sovrant)
# =============================================================================
install_dotnet() {
  section ".NET SDK ${DOTNET_CHANNEL}"

  if command_exists dotnet && dotnet --list-sdks 2>/dev/null | grep -q "^${DOTNET_CHANNEL%%.*}\."; then
    success ".NET SDK $(dotnet --version) already installed"
    return
  fi

  local os; os="$(os_type)"
  if [ "$os" = "macos" ] && command_exists brew; then
    brew install --cask dotnet-sdk 2>/dev/null \
      && success ".NET SDK installed via Homebrew" \
      && return
  fi

  # Microsoft's official install script (user-local, no sudo): https://dot.net
  log "Installing .NET SDK ${DOTNET_CHANNEL} via dotnet-install script (user-local ~/.dotnet)..."
  curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
    && bash /tmp/dotnet-install.sh --channel "$DOTNET_CHANNEL" \
    || { warn ".NET SDK install failed — continuing."; return 0; }

  # Make dotnet resolvable now and in future shells
  export DOTNET_ROOT="$HOME/.dotnet"
  export PATH="$DOTNET_ROOT:$DOTNET_ROOT/tools:$PATH"
  for profile in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$profile" ] && ! grep -q 'DOTNET_ROOT' "$profile" && {
      printf '\nexport DOTNET_ROOT="$HOME/.dotnet"\nexport PATH="$DOTNET_ROOT:$DOTNET_ROOT/tools:$PATH"\n' >> "$profile"
    }
  done

  command_exists dotnet \
    && success ".NET SDK $(dotnet --version) installed" \
    || warn "dotnet not on PATH yet — open a new shell or: export PATH=\"\$HOME/.dotnet:\$PATH\""
}

# =============================================================================
# 20. Sovrant (tekt.cloud — command center; BSL 1.1 source build on .NET 10)
# =============================================================================
install_sovrant() {
  section "Sovrant"

  local dest="$TEKT_INSTANCE/sovrant"
  log "Sovrant license: BSL 1.1 — source-available, not OSI open source (Apache-2.0 on 2029-05-15)."

  if [ -d "$dest/.git" ]; then
    success "Sovrant already staged at $dest"
  elif git ls-remote "$SOVRANT_REPO" &>/dev/null; then
    git clone --depth 1 "$SOVRANT_REPO" "$dest" 2>/dev/null \
      && success "Sovrant cloned to $dest" \
      || { warn "Sovrant clone failed — continuing."; return 0; }
  else
    warn "Sovrant repo not reachable (network?): ${SOVRANT_REPO} — continuing."
    return 0
  fi

  if ! command_exists dotnet; then
    warn "dotnet not found — skipping build. Run 'bash install.sh' again or install .NET ${DOTNET_CHANNEL} SDK, then:"
    warn "  cd $dest && dotnet restore && dotnet build"
    return 0
  fi

  log "Building Sovrant (dotnet restore && dotnet build) — first build can take a few minutes..."
  ( cd "$dest" && dotnet restore && dotnet build ) \
    && success "Sovrant built" \
    || { warn "Sovrant build failed — see output above; continuing."; return 0; }

  log "Run Sovrant from $dest:"
  log "  Desktop:  dotnet run --project src/Sovrant.Desktop &"
  log "  Web UI:   dotnet run --project src/Sovrant.Web        # http://localhost:5100"
  log "  Server:   dotnet run --project src/Sovrant.Server     # http://localhost:5200 (OpenAI-compatible)"
  log "  MCP/HTTP: SOVRANT_MCP_HTTP=true dotnet run --project src/Sovrant.Server   # MCP at :5200/mcp"
  log "  CLI:      dotnet run --project src/Sovrant.Cli -- --model <model>"
}

# =============================================================================
# MCPHub + curated MCP servers (bash install.sh mcp)
# =============================================================================
setup_mcphub() {
  section "MCPHub + curated MCP servers"

  mkdir -p "$TEKT_MCP_DIR" "$TEKT_WORKSPACE"

  if [ ! -f "$TEKT_MCP_DIR/mcp_settings.json" ]; then
    cat > "$TEKT_MCP_DIR/mcp_settings.json" <<'JSON'
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
JSON
    success "Wrote curated MCP config → $TEKT_MCP_DIR/mcp_settings.json"
    log "Swap or add servers by editing that file — MCPHub hot-reloads."
  else
    success "MCP config exists — leaving your edits alone."
  fi

  if [ ! -f "$TEKT_MCP_DIR/docker-compose.yml" ]; then
    cat > "$TEKT_MCP_DIR/docker-compose.yml" <<EOF
services:
  mcphub:
    image: ${MCPHUB_IMAGE}
    ports: ["3000:3000"]
    volumes:
      - ./mcp_settings.json:/app/mcp_settings.json
      - ../workspace:/workspace
    restart: unless-stopped
EOF
    success "Wrote $TEKT_MCP_DIR/docker-compose.yml"
  fi

  if command_exists docker && docker compose version &>/dev/null; then
    log "Starting MCPHub..."
    (cd "$TEKT_MCP_DIR" && docker compose up -d) \
      && success "MCPHub up — dashboard http://localhost:3000 (admin/admin123 — CHANGE IT)" \
      || warn "MCPHub failed to start. Try: cd $TEKT_MCP_DIR && docker compose up"
    log "Clients connect to: http://localhost:3000/mcp   (all servers, streamable HTTP)"
    log "HTTPS in one step:  bash install.sh share 3000"
  else
    warn "Docker not available — scaffolding written; start later with:"
    warn "  cd $TEKT_MCP_DIR && docker compose up -d"
  fi
}

# =============================================================================
# LibreChat + n8n scaffolds (bash install.sh ui)
# =============================================================================
setup_librechat() {
  section "LibreChat"

  local dest="$TEKT_CLOUD_DIR/librechat"
  mkdir -p "$TEKT_CLOUD_DIR"

  if [ ! -d "$dest/.git" ]; then
    log "Cloning LibreChat (danny-avila)..."
    git clone --depth 1 "$LIBRECHAT_REPO" "$dest" 2>/dev/null \
      || { warn "LibreChat clone failed."; return 1; }
  fi
  [ -f "$dest/.env" ] || cp "$dest/.env.example" "$dest/.env" 2>/dev/null || true

  # librechat.yaml → point LibreChat at the local MCPHub
  if [ ! -f "$dest/librechat.yaml" ]; then
    cat > "$dest/librechat.yaml" <<'YAML'
version: 1.2.1
mcpServers:
  tekt:
    type: streamable-http
    url: http://host.docker.internal:3000/mcp
YAML
    cat > "$dest/docker-compose.override.yml" <<'YAML'
services:
  api:
    volumes:
      - ./librechat.yaml:/app/librechat.yaml
    extra_hosts:
      - "host.docker.internal:host-gateway"
YAML
    success "Wired LibreChat → MCPHub (librechat.yaml + compose override)"
  fi

  if command_exists docker && docker compose version &>/dev/null; then
    log "Starting LibreChat stack (Mongo + Meilisearch included)..."
    (cd "$dest" && docker compose up -d) \
      && success "LibreChat up — http://localhost:3080 (create the first account in-browser)" \
      || warn "LibreChat failed to start. Add API keys to $dest/.env, then: cd $dest && docker compose up -d"
  else
    warn "Docker not available — start later with: cd $dest && docker compose up -d"
  fi
}

setup_n8n() {
  section "n8n"

  local dest="$TEKT_CLOUD_DIR/n8n"
  mkdir -p "$dest"

  if [ ! -f "$dest/docker-compose.yml" ]; then
    cat > "$dest/docker-compose.yml" <<EOF
services:
  n8n:
    image: ${N8N_IMAGE}
    ports: ["5678:5678"]
    environment:
      - N8N_SECURE_COOKIE=false
    volumes:
      - n8n_data:/home/node/.n8n
    extra_hosts:
      - "host.docker.internal:host-gateway"
    restart: unless-stopped
volumes:
  n8n_data:
EOF
    success "Wrote $dest/docker-compose.yml"
  fi

  if command_exists docker && docker compose version &>/dev/null; then
    (cd "$dest" && docker compose up -d) \
      && success "n8n up — http://localhost:5678 (MCP Client Tool → http://host.docker.internal:3000/mcp)" \
      || warn "n8n failed to start. Try: cd $dest && docker compose up"
  else
    warn "Docker not available — start later with: cd $dest && docker compose up -d"
  fi
  log "n8n license: Sustainable Use License (fair-code, not OSI open source)."
}

# =============================================================================
# Share a local port over HTTPS (bash install.sh share [port])
# =============================================================================
tekt_share() {
  local port="${1:-3000}"
  section "Share localhost:${port} over HTTPS"

  if command_exists tailscale && tailscale status &>/dev/null; then
    log "Tailnet detected — using Tailscale Serve (private HTTPS)..."
    tailscale serve --bg "$port" \
      && success "Serving :${port} inside your tailnet. Public instead? tailscale funnel --bg ${port}" \
      || warn "tailscale serve failed — try: sudo tailscale up && tailscale serve --bg ${port}"
  elif command_exists ngrok; then
    log "No tailnet — falling back to ngrok (public HTTPS, runs in foreground; Ctrl-C to stop)..."
    ngrok http "$port"
  else
    warn "Neither Tailscale nor ngrok is available. Install one:"
    warn "  curl -fsSL https://tailscale.com/install.sh | sh"
    warn "  — or — https://ngrok.com/download"
    return 1
  fi
}

# =============================================================================
# Summary
# =============================================================================
print_summary() {
  reload_path

  section "Installation Summary"
  echo ""

  check() {
    local label="$1" cmd="$2"
    local installed=1
    if [ "$cmd" = "__claude_desktop__" ]; then
      claude_desktop_installed || installed=0
    elif ! command_exists "$cmd"; then
      installed=0
    fi
    if [ "$installed" -eq 1 ]; then
      local ver
      case "$cmd" in
        __claude_desktop__) ver="installed (app bundle)" ;;
        brew)    ver="$(brew --version | head -1)" ;;
        git)     ver="$(git --version)" ;;
        go)      ver="$(go version | awk '{print $3}')" ;;
        python3) ver="$(python3 --version)" ;;
        node)    ver="$(node --version)" ;;
        npm)     ver="$(npm --version)" ;;
        rclone)  ver="$(rclone version | head -1 | awk '{print $2}')" ;;
        aws)     ver="$(aws --version | awk '{print $1}')" ;;
        code)    ver="$(code --version | head -1)" ;;
        docker)  ver="$(docker --version 2>/dev/null)$(docker compose version 2>/dev/null && echo ' + Compose')" ;;
        claude)  ver="$(claude --version 2>/dev/null || echo 'installed')" ;;
        *)       ver="installed" ;;
      esac
      printf "  ${GREEN}✓${RESET}  %-18s %s\n" "$label" "$ver"
    else
      printf "  ${YELLOW}?${RESET}  %-18s %s\n" "$label" "(not in PATH — may need shell reload)"
    fi
  }

  # ── Tekt.Dev ──
  check "Git"             git
  check "Homebrew"        brew
  check "Go"              go
  check "Python"          python3
  check "Node.js"         node
  check "npm"             npm
  check "VSCode"          code
  check "Docker"          docker
  check ".NET SDK"        dotnet
  # ── Tekt.Base ──
  check "rclone"          rclone
  check "aws-cli"         aws
  check "s3cmd"           s3cmd
  check "s5cmd"           s5cmd
  # ── Tekt.Edge ──
  check "Tailscale"       tailscale
  check "ngrok"           ngrok
  # ── Tekt.Iris ──
  check "Ollama"          ollama
  check "Claude Code"     claude
  check "Claude Desktop"  __claude_desktop__
  check "Zed (Agent)"     zed
  check "OpenClaw"        openclaw
  check "PicoClaw"        picoclaw
  check "Hermes Agent"    hermes
  check "ZeroClaw"        zeroclaw
  check "Nanobot"         nanobot

  echo ""
  log "Staged (tekt.cloud): MCPHub/LibreChat/n8n/Sovrant — bring up with:"
  log "  bash install.sh mcp     # MCPHub + curated MCP servers on :3000"
  log "  bash install.sh ui      # LibreChat :3080 and n8n :5678"
  log "  Sovrant Web :5100       # cd \$TEKT_INSTANCE/sovrant && dotnet run --project src/Sovrant.Web"
  log "Restart your terminal/session to reload PATH (required after some installs)."
  log "OpenClaw onboarding is intentionally deferred: run 'openclaw onboard --install-daemon' when ready."
  log "Docs: https://tekt.md"
  echo ""
}

# =============================================================================
# Status — standalone environment check (bash install.sh status / tekt status)
# =============================================================================
tekt_status() {
  reload_path

  echo ""
  echo -e "${BOLD}${CYAN}"
  echo "  ████████╗███████╗██╗  ██╗████████╗"
  echo "     ██╔══╝██╔════╝██║ ██╔╝╚══██╔══╝"
  echo "     ██║   █████╗  █████╔╝    ██║   "
  echo "     ██║   ██╔══╝  ██╔═██╗    ██║   "
  echo "     ██║   ███████╗██║  ██╗   ██║   "
  echo "     ╚═╝   ╚══════╝╚═╝  ╚═╝   ╚═╝   "
  echo -e "${RESET}"
  echo -e "  ${BOLD}Tekt Environment Status${RESET}  —  https://tekt.md"
  echo ""
  log "OS: $(uname -s) / Arch: $(arch_type)"
  echo ""

  local installed=0 missing=0
  local missing_list=""

  check_tool() {
    local label="$1" cmd="$2" category="$3"
    local installed=1
    if [ "$cmd" = "__claude_desktop__" ]; then
      claude_desktop_installed || installed=0
    elif ! command_exists "$cmd"; then
      installed=0
    fi
    if [ "$installed" -eq 1 ]; then
      local ver
      case "$cmd" in
        __claude_desktop__) ver="installed (app bundle)" ;;
        brew)    ver="$(brew --version | head -1)" ;;
        git)     ver="$(git --version)" ;;
        go)      ver="$(go version | awk '{print $3}')" ;;
        python3) ver="$(python3 --version)" ;;
        node)    ver="$(node --version)" ;;
        npm)     ver="$(npm --version)" ;;
        rclone)  ver="$(rclone version | head -1 | awk '{print $2}')" ;;
        aws)     ver="$(aws --version | awk '{print $1}')" ;;
        code)    ver="$(code --version | head -1)" ;;
        docker)  ver="$(docker --version 2>/dev/null)" ;;
        claude)  ver="$(claude --version 2>/dev/null || echo 'installed')" ;;
        *)       ver="$(${cmd} --version 2>/dev/null || echo 'installed')" ;;
      esac
      printf "  ${GREEN}✓${RESET}  %-18s %s\n" "$label" "$ver"
      installed=$((installed + 1))
    else
      printf "  ${RED}✗${RESET}  %-18s %s\n" "$label" "not installed"
      missing=$((missing + 1))
      missing_list="${missing_list}  • ${label}\n"
    fi
  }

  echo -e "${BOLD}Tekt.Dev — Development Environment${RESET}"
  check_tool "Git"             git       dev
  check_tool "Homebrew"        brew      dev
  check_tool "Go"              go        dev
  check_tool "Python"          python3   dev
  check_tool "Node.js"         node      dev
  check_tool "npm"             npm       dev
  check_tool "VSCode"          code      dev
  check_tool "Docker"          docker    dev
  if command_exists docker && docker compose version &>/dev/null; then
    printf "  ${GREEN}✓${RESET}  %-18s %s\n" "Docker Compose" "$(docker compose version 2>/dev/null)"
  elif command_exists docker; then
    printf "  ${YELLOW}?${RESET}  %-18s %s\n" "Docker Compose" "plugin not found"
  fi

  echo ""
  echo -e "${BOLD}Tekt.Base — Communications & Sync${RESET}"
  check_tool "rclone"          rclone    base
  check_tool "aws-cli"         aws       base
  check_tool "s3cmd"           s3cmd     base
  check_tool "s5cmd"           s5cmd     base

  echo ""
  echo -e "${BOLD}Tekt.Edge — Network & Exposure${RESET}"
  check_tool "Tailscale"       tailscale edge
  check_tool "ngrok"           ngrok     edge

  echo ""
  echo -e "${BOLD}Tekt.Iris — Intelligence${RESET}"
  check_tool "Ollama"          ollama    iris
  check_tool "Claude Code"     claude    iris
  check_tool "Claude Desktop"  __claude_desktop__ iris
  check_tool "Zed (Agent)"     zed       iris
  check_tool "OpenClaw"        openclaw  iris
  check_tool "PicoClaw"        picoclaw  iris
  check_tool "Hermes Agent"    hermes    iris
  check_tool "ZeroClaw"        zeroclaw  iris
  check_tool "Nanobot"         nanobot   iris
  if [ -d "$TEKT_AGENTS_DIR/nanoclaw/.git" ]; then
    printf "  ${GREEN}✓${RESET}  %-18s %s\n" "NanoClaw" "staged at $TEKT_AGENTS_DIR/nanoclaw"
  else
    printf "  ${YELLOW}?${RESET}  %-18s %s\n" "NanoClaw" "not staged (run full install)"
  fi

  echo ""
  echo -e "${BOLD}Tekt.Cloud — Chat, Workflows & Command Center${RESET}"
  check_service() {
    local label="$1" match="$2" url="$3"
    if command_exists docker && docker ps --format '{{.Image}} {{.Names}}' 2>/dev/null | grep -qi "$match"; then
      printf "  ${GREEN}✓${RESET}  %-18s running — %s\n" "$label" "$url"
    else
      printf "  ${YELLOW}?${RESET}  %-18s %s\n" "$label" "not running"
    fi
  }
  check_service "MCPHub"    "mcphub"    "http://localhost:3000"
  check_service "LibreChat" "librechat" "http://localhost:3080"
  check_service "n8n"       "n8n"       "http://localhost:5678"
  if [ -d "$TEKT_INSTANCE/sovrant/.git" ]; then
    if compgen -G "$TEKT_INSTANCE/sovrant/src/Sovrant.Web/bin/*" >/dev/null 2>&1; then
      printf "  ${GREEN}✓${RESET}  %-18s %s\n" "Sovrant" "built (BSL 1.1) at $TEKT_INSTANCE/sovrant — Web :5100, Server :5200"
    else
      printf "  ${YELLOW}?${RESET}  %-18s %s\n" "Sovrant" "cloned, not built — cd $TEKT_INSTANCE/sovrant && dotnet build"
    fi
  else
    printf "  ${YELLOW}?${RESET}  %-18s %s\n" "Sovrant" "not staged (BSL 1.1) — bash install.sh installs it"
  fi

  # ── Totals ──
  local total=$((installed + missing))
  echo ""
  echo -e "  ─────────────────────────────────"
  printf "  ${GREEN}${BOLD}%d${RESET} installed  /  " "$installed"
  if [ "$missing" -gt 0 ]; then
    printf "${RED}${BOLD}%d${RESET} missing  /  %d total\n" "$missing" "$total"
  else
    printf "${GREEN}${BOLD}0${RESET} missing  /  %d total\n" "$total"
  fi

  if [ "$missing" -gt 0 ]; then
    echo ""
    echo -e "  ${YELLOW}Missing:${RESET}"
    echo -e "$missing_list"
    log "Run 'bash install.sh' to install everything, or install individually."
  else
    echo ""
    success "All Tekt tools are installed."
  fi
  echo ""
}

# =============================================================================
# Main — full install
# =============================================================================
main() {
  echo ""
  echo -e "${BOLD}${CYAN}"
  echo "  ████████╗███████╗██╗  ██╗████████╗"
  echo "     ██╔══╝██╔════╝██║ ██╔╝╚══██╔══╝"
  echo "     ██║   █████╗  █████╔╝    ██║   "
  echo "     ██║   ██╔══╝  ██╔═██╗    ██║   "
  echo "     ██║   ███████╗██║  ██╗   ██║   "
  echo "     ╚═╝   ╚══════╝╚═╝  ╚═╝   ╚═╝   "
  echo -e "${RESET}"
  echo -e "  ${BOLD}Tekt Bootstrap Installer${RESET}  —  https://tekt.md"
  echo ""
  log "OS: $(uname -s) / Arch: $(arch_type)"
  echo ""

  # Ensure ~/.local/bin exists and is in PATH early — PicoClaw and Hermes install here
  ensure_local_bin

  # Each install is wrapped with || true so a single failure doesn't kill the script.
  # The summary at the end shows what succeeded and what didn't.

  # ── Tekt.Dev ──
  install_git           || warn "Git install failed — continuing..."
  install_homebrew      || warn "Homebrew install failed — continuing..."
  install_system_deps   || warn "System deps install failed — continuing..."
  install_go            || warn "Go install failed — continuing..."
  install_python        || warn "Python install failed — continuing..."
  install_nvm_node      || warn "nvm/Node install failed — continuing..."
  install_vscode        || warn "VSCode install failed — continuing..."
  install_docker        || warn "Docker install failed — continuing..."

  # ── Tekt.Base ──
  install_rclone        || warn "rclone install failed — continuing..."
  install_s3_tools      || warn "S3 tools install failed — continuing..."

  # ── Tekt.Edge ──
  install_tailscale     || warn "Tailscale install failed — continuing..."
  install_ngrok         || warn "ngrok install failed — continuing..."

  # ── Tekt.Iris ──
  install_ollama        || warn "Ollama install failed — continuing..."
  install_claude_code   || warn "Claude Code install failed — continuing..."
  install_claude_desktop || warn "Claude Desktop install skipped — continuing..."
  install_zed_agent     || warn "Zed install failed — continuing..."
  install_openclaw      || warn "OpenClaw install failed — continuing..."
  install_picoclaw      || warn "PicoClaw install failed — continuing..."
  install_hermes        || warn "Hermes Agent install failed — continuing..."
  install_zeroclaw      || warn "ZeroClaw install failed — continuing..."
  install_nanobot       || warn "Nanobot install failed — continuing..."
  install_nanoclaw      || warn "NanoClaw staging failed — continuing..."

  # ── Tekt.Cloud (staged — start with `install.sh mcp` / `install.sh ui`) ──
  install_dotnet        || warn ".NET SDK install skipped — continuing..."
  install_sovrant       || warn "Sovrant install skipped — continuing..."

  print_summary
}

# =============================================================================
# Entry point — subcommand dispatch
# =============================================================================
case "${1:-}" in
  status)
    tekt_status
    ;;
  catalog)
    # Print the tool catalog (local checkout first, then tekt.md)
    _cat="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd)/tekt.catalog.yaml"
    if [ -f "$_cat" ]; then
      cat "$_cat"
    else
      curl -fsSL https://tekt.md/tekt.catalog.yaml 2>/dev/null \
        || error "Catalog not found locally or at https://tekt.md/tekt.catalog.yaml"
    fi
    ;;
  mcp)
    setup_mcphub
    ;;
  ui)
    setup_librechat || warn "LibreChat setup incomplete — continuing..."
    setup_n8n       || warn "n8n setup incomplete — continuing..."
    echo ""
    log "Wire-up guide: https://tekt.md/04-interface/"
    ;;
  share)
    tekt_share "${2:-3000}"
    ;;
  help|--help|-h)
    echo "Usage: $(basename "$0") [command]"
    echo ""
    echo "Commands:"
    echo "  (none)        Install all Tekt tools"
    echo "  status        Check which tools are installed"
    echo "  catalog       Print the tool catalog (tekt.catalog.yaml)"
    echo "  mcp           Bring up MCPHub + the curated MCP servers (:3000)"
    echo "  ui            Bring up LibreChat (:3080) and n8n (:5678)"
    echo "  share [port]  HTTPS-expose a local port (Tailscale Serve, else ngrok)"
    echo "  help          Show this help"
    echo ""
    echo "When this becomes the tekt CLI, the same commands read as:"
    echo "  tekt status · tekt catalog · tekt mcp · tekt ui · tekt share"
    echo ""
    ;;
  "")
    main
    ;;
  *)
    error "Unknown command: $1"
    echo "Run '$(basename "$0") help' for usage."
    ;;
esac
