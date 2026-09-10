#!/usr/bin/env bash
# =============================================================================
# tekt-bootstrap.sh
# Tekt Platform — Full Environment Bootstrap
# https://tekt.md
#
# Installs: Homebrew, GitHub CLI, Go, Python (pyenv), nvm/Node, rclone, AWS CLI,
#           VSCode, Docker, Tailscale, ngrok, Ollama, Claude Code,
#           Claude Desktop (macOS), Zed (+ Agent mode), OpenClaw,
#           PicoClaw, Hermes Agent, ZeroClaw, Nanobot, NanoClaw
# Stages:   MCPHub (+ curated MCP servers), LibreChat, n8n, Sovrant
#
# Supported: macOS (Intel + Apple Silicon), Ubuntu/Debian, Fedora/RHEL, WSL2
# Usage:     curl -fsSL https://tekt.md/install.sh | bash
#            — or —
#            bash install.sh [status|catalog|mcp|ui|share|space|cli|help]
# Spaces:    tekt space add team drive   — share a folder with your AI and your
#            people through Google Drive, OneDrive, Dropbox, Box, Nextcloud or a NAS
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
RCLONEVIEW_LINUX_VERSION="1.5.12"   # RcloneView AppImage (tekt space gui)

# ── Tekt instance layout ──────────────────────────────────────────────────────
TEKT_HOME="${TEKT_HOME:-$HOME/Tekt}"
TEKT_HOSTNAME="$(hostname -s 2>/dev/null || echo local)"
TEKT_INSTANCE="${TEKT_INSTANCE:-$TEKT_HOME/Instances/$TEKT_HOSTNAME}"
TEKT_WORKSPACE="$TEKT_INSTANCE/workspace"
TEKT_MCP_DIR="$TEKT_INSTANCE/mcp"
TEKT_CLOUD_DIR="$TEKT_INSTANCE/cloud"
TEKT_AGENTS_DIR="$TEKT_INSTANCE/agents"
TEKT_SPACES="${TEKT_SPACES:-$TEKT_HOME/Spaces}"   # shared folders (tekt space …)
TEKT_BIN="${TEKT_BIN:-$HOME/.local/bin/tekt}"     # the tekt command

# ── Catalog pins (tekt.catalog.yaml overrides the defaults above) ─────────────
load_catalog_pins() {
  # Works when run from a checkout; silently skipped under `curl | bash`.
  local script_dir catalog
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd)" || return 0
  catalog="${TEKT_CATALOG:-$script_dir/tekt.catalog.yaml}"
  [ -f "$catalog" ] || return 0
  local key val
  for key in GO_VERSION PYTHON_VERSION NODE_VERSION NVM_VERSION DOTNET_CHANNEL MCPHUB_IMAGE N8N_IMAGE RCLONEVIEW_LINUX_VERSION; do
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
# 1b. GitHub CLI (gh) — issues, pull requests and releases from the terminal
# =============================================================================
install_gh() {
  section "GitHub CLI (gh)"
  if command_exists gh; then
    success "gh already installed — $(gh --version | head -1)"
    return
  fi

  if command_exists brew; then
    brew install gh --quiet || true
  elif [ "$(os_type)" = "linux" ]; then
    require_sudo || return 1
    local distro; distro="$(linux_distro)"
    case "$distro" in
      ubuntu|debian|linuxmint|pop)
        $SUDO mkdir -p -m 755 /etc/apt/keyrings
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
          | $SUDO tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
        $SUDO chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
          | $SUDO tee /etc/apt/sources.list.d/github-cli.list >/dev/null
        $SUDO apt-get update -q && $SUDO apt-get install -y -q gh
        ;;
      fedora)
        $SUDO dnf install -y gh
        ;;
      rhel|centos|rocky|alma)
        $SUDO curl -fsSL -o /etc/yum.repos.d/gh-cli.repo https://cli.github.com/packages/rpm/gh-cli.repo
        $SUDO dnf install -y gh
        ;;
      arch|manjaro)
        $SUDO pacman -S --noconfirm github-cli
        ;;
      *)
        warn "Unknown distro ($distro) — install gh by hand: https://github.com/cli/cli#installation"
        return 1
        ;;
    esac
  fi

  if command_exists gh; then
    success "gh $(gh --version | head -1 | awk '{print $3}') installed — sign in once with: gh auth login"
  else
    warn "gh didn't install. See https://github.com/cli/cli#installation"
    return 1
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

  mkdir -p "$TEKT_MCP_DIR" "$TEKT_WORKSPACE" "$TEKT_SPACES"

  if [ ! -f "$TEKT_MCP_DIR/mcp_settings.json" ]; then
    cat > "$TEKT_MCP_DIR/mcp_settings.json" <<'JSON'
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/workspace", "/spaces"]
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
      - ${TEKT_SPACES}:/spaces
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
# Spaces — share documents, knowledge and skills with your AI and your people
# (tekt space add | list | sync | remove | autosync)
#
# A Space is a folder that stays in sync with storage people already use —
# Google Drive, OneDrive, Dropbox, Box, Nextcloud, or a folder on a NAS — via
# rclone bisync. Every Space has the same layout: docs/ knowledge/ skills/.
# Metadata lives in <space>/.tekt-space (key=value); install.ps1 reads the same.
# =============================================================================
space_backend() {    # friendly storage word → rclone backend
  case "$1" in
    drive|gdrive|google|googledrive|google-drive) echo drive ;;
    onedrive|microsoft|sharepoint)                echo onedrive ;;
    dropbox)                                      echo dropbox ;;
    box)                                          echo box ;;
    nextcloud|owncloud|webdav)                    echo webdav ;;
    folder|local|nas|path)                        echo alias ;;
    s3|minio|r2|b2)                               echo s3 ;;
    *) return 1 ;;
  esac
}

space_label() {
  case "$1" in
    drive)    echo "Google Drive" ;;
    onedrive) echo "OneDrive" ;;
    dropbox)  echo "Dropbox" ;;
    box)      echo "Box" ;;
    webdav)   echo "Nextcloud / WebDAV" ;;
    alias)    echo "a folder" ;;
    s3)       echo "S3" ;;
    *)        echo "$1" ;;
  esac
}

space_now()  { date -u +%Y-%m-%dT%H:%M:%SZ; }

space_meta() {       # space_meta <dir> <key>
  { grep -E "^$2=" "$1/.tekt-space" 2>/dev/null || true; } | head -1 | cut -d= -f2-
}

space_set_meta() {   # space_set_meta <dir> <key> <value>
  local f="$1/.tekt-space" tmp
  tmp="$(mktemp)"
  { grep -vE "^$2=" "$f" 2>/dev/null || true; printf '%s=%s\n' "$2" "$3"; } > "$tmp"
  mv "$tmp" "$f"
}

space_ask() {        # read from the terminal, even under curl | bash
  local answer=""
  read -rp "  $1" answer </dev/tty || true
  printf '%s' "$answer"
}

space_flags() {
  SPACE_FLAGS=(--create-empty-src-dirs
    --exclude "/.tekt-space*" --exclude ".DS_Store" --exclude "Thumbs.db"
    --exclude '~$*' --exclude "*.tmp")
  local help
  help="$(rclone bisync --help 2>/dev/null || true)"
  case "$help" in
    *--conflict-resolve*)   # rclone ≥ 1.66: newest wins, the other copy is kept
      SPACE_FLAGS+=(--conflict-resolve newer --conflict-loser num --resilient --recover --max-lock 2m) ;;
  esac
  SPACE_RESYNC=(--resync)
  case "$help" in
    *--resync-mode*) SPACE_RESYNC+=(--resync-mode newer) ;;   # first sync: the newer copy of a file wins
  esac
}

space_readme() {
  cat <<EOF
# $1 — a Tekt Space

This folder is shared between people and their AI tools with Tekt (https://tekt.md/spaces/).
Everyone who has it keeps a synced copy on their own computer.

- docs/       Documents you want your AI and your colleagues to read
- knowledge/  Notes, decisions and reference material worth keeping
- skills/     Skills for AI agents: one folder per skill, each with a SKILL.md

Join it from your computer:  tekt space add $1 <drive|onedrive|dropbox|box|nextcloud|folder>
EOF
}

space_add() {
  local name="${1:-}" provider="${2:-}" folder="${3:-}"
  section "Add a Space"
  [ -n "$name" ] || name="$(space_ask "Name this Space (e.g. team, family, research): ")"
  name="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9-' '-' | sed 's/^-*//; s/-*$//')"
  if [ -z "$name" ]; then error "A Space needs a name, e.g.  tekt space add team drive"; return 1; fi

  if [ -z "$provider" ]; then
    echo "  Where should it live? Pick what your people already use:"
    echo "    1) Google Drive   2) OneDrive / SharePoint   3) Dropbox   4) Box"
    echo "    5) Nextcloud      6) A folder on this computer or a network drive"
    echo "    7) S3 (advanced)"
    case "$(space_ask "Choose 1-7: ")" in
      1) provider=drive ;;     2) provider=onedrive ;; 3) provider=dropbox ;; 4) provider=box ;;
      5) provider=nextcloud ;; 6) provider=folder ;;   7) provider=s3 ;;
      *) error "Pick a number from 1 to 7."; return 1 ;;
    esac
  fi
  local backend
  if ! backend="$(space_backend "$provider")"; then
    error "Unknown storage '$provider'. Use: drive, onedrive, dropbox, box, nextcloud, folder or s3."
    return 1
  fi

  if ! command_exists rclone; then
    install_rclone || true
    if ! command_exists rclone; then error "Spaces need rclone — install it from https://rclone.org/install/ and try again."; return 1; fi
  fi

  local remote="tekt-$name" dir="$TEKT_SPACES/$name"
  if [ -f "$dir/.tekt-space" ]; then
    warn "Space '$name' already exists at $dir — syncing it instead."
    space_sync "$name"
    return
  fi

  if rclone listremotes 2>/dev/null | grep -x "$remote:" >/dev/null; then
    success "Reusing your existing connection '$remote'"
    if [ "$backend" = alias ]; then folder=""; fi
  else
    case "$backend" in
      alias)
        [ -n "$folder" ] || folder="$(space_ask "Path to the shared folder (e.g. /mnt/nas/team or ~/Dropbox/Team): ")"
        folder="${folder/#\~/$HOME}"
        if [ -z "$folder" ] || ! mkdir -p "$folder"; then error "Can't reach that folder: ${folder:-<empty>}"; return 1; fi
        rclone config create "$remote" alias remote="$folder" >/dev/null
        folder=""   # the connection itself points at the folder
        ;;
      webdav)
        local url user pass=""
        url="$(space_ask "Nextcloud address (e.g. https://cloud.example.com): ")"
        user="$(space_ask "Nextcloud username: ")"
        log "Use an app password (Nextcloud → Settings → Security). rclone stores it obscured on this computer."
        read -rsp "  App password: " pass </dev/tty || true; echo
        rclone config create "$remote" webdav url="${url%/}/remote.php/dav/files/$user" vendor=nextcloud \
          user="$user" pass="$pass" --obscure >/dev/null \
          || { error "Couldn't connect to Nextcloud. Check the address and the app password."; return 1; }
        ;;
      s3)
        log "rclone will ask for the endpoint, access key and secret."
        rclone config create "$remote" s3 --all </dev/tty || { error "S3 setup didn't finish."; return 1; }
        ;;
      *)
        log "Your browser will open so you can sign in to $(space_label "$backend"). Tekt never sees your password."
        rclone config create "$remote" "$backend" </dev/tty \
          || { error "Sign-in didn't finish. Try again:  tekt space add $name $provider"; return 1; }
        ;;
    esac
    success "Connected to $(space_label "$backend") as '$remote'"
  fi

  if [ -z "$folder" ] && [ "$backend" != alias ]; then
    if [ "$backend" = s3 ]; then
      folder="$(space_ask "Bucket and folder (e.g. my-bucket/tekt/$name): ")"
    else
      folder="Tekt/$name"
    fi
  fi

  mkdir -p "$dir/docs" "$dir/knowledge" "$dir/skills"
  # Joining an existing Space? Its README arrives with the first sync — writing our own
  # copy first makes the two sides disagree and the first sync fail.
  if [ ! -f "$dir/README.md" ] && ! rclone lsf "$remote:$folder" --files-only --max-depth 1 2>/dev/null | grep -x "README.md" >/dev/null; then
    space_readme "$name" > "$dir/README.md"
  fi
  : > "$dir/.tekt-space"
  space_set_meta "$dir" name "$name"
  space_set_meta "$dir" provider "$provider"
  space_set_meta "$dir" remote "$remote"
  space_set_meta "$dir" folder "$folder"
  space_set_meta "$dir" created "$(space_now)"
  space_set_meta "$dir" initialized 0

  rclone mkdir "$remote:$folder" 2>/dev/null || true
  space_sync "$name" || return 1

  echo ""
  success "Space '$name' is ready: $dir"
  log "Put files in docs/, notes in knowledge/, and skill folders in skills/."
  log "Invite people:                  tekt space invite $name   (writes the invitation for you)"
  log "Let your AI apps use it:        tekt connect"
  log "Keep it in sync automatically:  tekt space autosync on"
}

space_sync() {
  local only="${1:-}" dir name remote folder rc=0 any=0
  if ! command_exists rclone; then error "rclone isn't installed. Run the Tekt installer first."; return 1; fi
  space_flags
  for dir in "$TEKT_SPACES"/*/; do
    dir="${dir%/}"
    [ -f "$dir/.tekt-space" ] || continue
    name="$(space_meta "$dir" name)"; name="${name:-$(basename "$dir")}"
    if [ -n "$only" ] && [ "$only" != "$name" ]; then continue; fi
    any=1
    remote="$(space_meta "$dir" remote)"; folder="$(space_meta "$dir" folder)"
    local extra=()
    if [ "$(space_meta "$dir" initialized)" != 1 ]; then extra=("${SPACE_RESYNC[@]}"); fi   # first sync merges both sides
    if [ $(( ${#remote} + ${#folder} + ${#dir} )) -gt 200 ]; then   # rclone names its lock files after both paths (#58)
      warn "$name has a very long path, and rclone may not be able to sync it. If it fails, keep Spaces somewhere shorter, e.g.  export TEKT_SPACES=~/Spaces"
    fi
    log "Syncing $name ↔ $remote:$folder"
    if rclone bisync "$remote:$folder" "$dir" ${extra[@]+"${extra[@]}"} "${SPACE_FLAGS[@]}" -q; then
      space_set_meta "$dir" initialized 1
      space_set_meta "$dir" last_sync "$(space_now)"
      success "$name is up to date"
      space_link_skills "$name"
    else
      rc=1
      warn "$name didn't sync. If it keeps failing, reset it with:  rclone bisync $remote:$folder $dir --resync"
    fi
  done
  if [ "$any" -eq 0 ]; then
    if [ -n "$only" ]; then error "No Space named '$only'. See:  tekt space list"; return 1; fi
    log "No Spaces yet. Add one:  tekt space add team drive"
  fi
  return "$rc"
}

space_list() {
  section "Spaces"
  local dir found=0 provider backend last docs skills
  for dir in "$TEKT_SPACES"/*/; do
    dir="${dir%/}"
    [ -f "$dir/.tekt-space" ] || continue
    found=1
    provider="$(space_meta "$dir" provider)"
    backend="$(space_backend "$provider" 2>/dev/null || printf '%s' "$provider")"
    last="$(space_meta "$dir" last_sync)"
    docs="$(find "$dir/docs" -type f 2>/dev/null | wc -l | tr -d ' ')"
    skills="$(find "$dir/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
    printf "  ${GREEN}●${RESET} %-14s %-20s %s\n" "$(basename "$dir")" "$(space_label "$backend")" "$dir"
    printf "    %-14s last sync %s · %s docs · %s skills\n" "" "${last:-never}" "$docs" "$skills"
  done
  if [ "$found" -eq 0 ]; then log "No Spaces yet. Add one:  tekt space add team drive"; fi
}

space_remove() {
  local name="${1:-}" dir remote
  if [ -z "$name" ]; then error "Which Space?  tekt space remove <name>"; return 1; fi
  dir="$TEKT_SPACES/$name"
  if [ ! -f "$dir/.tekt-space" ]; then error "No Space named '$name'. See:  tekt space list"; return 1; fi
  remote="$(space_meta "$dir" remote)"
  rclone config delete "$remote" 2>/dev/null || true
  mv "$dir/.tekt-space" "$dir/.tekt-space.removed"
  space_link_skills "$name"   # its skills leave Claude Code
  success "Disconnected '$name'. Your files stay in $dir and in the cloud folder; nothing was deleted."
}

space_copy() {       # copy stdin to the clipboard when this computer has one
  local text; text="$(cat)"
  if command_exists pbcopy; then printf '%s' "$text" | pbcopy
  elif command_exists wl-copy && [ -n "${WAYLAND_DISPLAY:-}" ]; then printf '%s' "$text" | wl-copy
  elif command_exists xclip && [ -n "${DISPLAY:-}" ]; then printf '%s' "$text" | xclip -selection clipboard
  elif command_exists clip.exe; then printf '%s' "$text" | clip.exe
  else return 1
  fi
}

space_invite() {     # write the invitation for a Space, and copy it
  local name="${1:-}" dir provider backend folder shared step1 join path msg
  if [ -z "$name" ]; then error "Which Space?  tekt space invite <name>"; return 1; fi
  dir="$TEKT_SPACES/$name"
  if [ ! -f "$dir/.tekt-space" ]; then error "No Space named '$name'. See:  tekt space list"; return 1; fi
  provider="$(space_meta "$dir" provider)"; folder="$(space_meta "$dir" folder)"
  backend="$(space_backend "$provider" 2>/dev/null || printf '%s' "$provider")"
  shared="$(basename "${folder:-$name}")"   # a folder shared with you lands at the top level under its own name
  join="tekt space add $name $provider \"$shared\""
  case "$backend" in
    drive)    step1="I've shared the folder \"$shared\" with you on Google Drive. Open \"Shared with me\", right-click it, choose Organize > Add shortcut, and pick My Drive." ;;
    onedrive) step1="I've shared the folder \"$shared\" with you on OneDrive. Open the link I sent, then choose \"Add shortcut to My files\"." ;;
    dropbox|box|webdav) step1="Accept my invitation to the shared folder \"$shared\" in $(space_label "$backend")." ;;
    alias)
      path="$(rclone config show "$(space_meta "$dir" remote)" 2>/dev/null | sed -n 's/^remote = //p')"
      step1="Make sure you can open ${path:-the shared folder} on your computer."
      join="tekt space add $name folder \"${path:-<path to the shared folder>}\"" ;;
    s3)       step1="Ask me for the S3 endpoint and access keys."; join="tekt space add $name s3 \"$folder\"" ;;
    *)        step1="Get access to the shared folder \"$shared\"." ;;
  esac
  msg="$(cat <<EOF
Join our "$name" Space on Tekt: shared documents, knowledge and AI skills.

1. $step1
2. Install Tekt (once):
   macOS / Linux:  curl -fsSL https://tekt.md/install.sh | bash
   Windows:        irm https://tekt.md/install.ps1 | iex
3. Join:                $join
4. Let your AI use it:  tekt connect
Guide: https://tekt.md/spaces/
EOF
)"
  if [ "$backend" != alias ] && [ "$backend" != s3 ]; then
    log "First share the folder '$folder' in $(space_label "$backend") with the people you're inviting. Then send them this:"
  fi
  echo ""
  printf '%s\n' "$msg"
  echo ""
  if printf '%s\n' "$msg" | space_copy 2>/dev/null; then
    success "Copied to your clipboard. Paste it into an email or chat."
  else
    log "Copy the message above and send it to the people you're inviting."
  fi
}

space_open() {       # open a Space's folder in the file manager
  local name="${1:-}" dir
  if [ -z "$name" ]; then error "Which Space?  tekt space open <name>"; return 1; fi
  dir="$TEKT_SPACES/$name"
  if [ ! -f "$dir/.tekt-space" ]; then error "No Space named '$name'. See:  tekt space list"; return 1; fi
  if [ "$(os_type)" = macos ]; then
    open "$dir"
  elif command_exists explorer.exe; then
    explorer.exe "$(wslpath -w "$dir" 2>/dev/null || printf '%s' "$dir")" || true   # explorer exits 1 even on success
  elif command_exists xdg-open; then
    xdg-open "$dir" >/dev/null 2>&1 || true
  else
    log "Your Space is at: $dir"
    return 0
  fi
  success "Opened $dir"
}

space_autosync() {
  local mode="${1:-on}" current line
  if ! command_exists crontab; then error "Background sync needs cron. Sync by hand instead:  tekt space sync"; return 1; fi
  current="$(crontab -l 2>/dev/null | grep -v '# tekt-autosync' || true)"
  if [ "$mode" = off ]; then
    printf '%s\n' "$current" | crontab -
    success "Autosync off. Sync by hand any time:  tekt space sync"
    return
  fi
  install_tekt_cli >/dev/null || true
  line="*/10 * * * * TEKT_HOME=\"$TEKT_HOME\" PATH=\"${PATH//%/\\%}\" \"$TEKT_BIN\" space sync >/dev/null 2>&1 # tekt-autosync"
  { if [ -n "$current" ]; then printf '%s\n' "$current"; fi; printf '%s\n' "$line"; } | crontab -
  success "Autosync on: your Spaces sync every 10 minutes. Turn it off with:  tekt space autosync off"
}

# =============================================================================
# More AI apps — Codex CLI (OpenAI), opencode, crush (Charm)
# =============================================================================
install_codex() {
  section "Codex CLI (OpenAI)"
  if command_exists codex; then success "Codex CLI already installed — $(codex --version 2>/dev/null | head -1)"; return 0; fi
  if [ "$(os_type)" = macos ] && command_exists brew; then
    brew install --cask codex --quiet || true
  elif command_exists npm; then
    npm install -g @openai/codex --silent || true
  else
    curl -fsSL https://chatgpt.com/codex/install.sh | sh || true
  fi
  reload_path
  if command_exists codex; then
    success "Codex CLI installed — sign in with: codex login"
  else
    warn "Codex CLI didn't install. Try: npm install -g @openai/codex"
    return 1
  fi
}

install_opencode() {
  section "opencode"
  if command_exists opencode; then success "opencode already installed"; return 0; fi
  if [ "$(os_type)" = macos ] && command_exists brew; then
    brew install anomalyco/tap/opencode --quiet || true
  elif command_exists npm; then
    npm install -g opencode-ai@latest --silent || true
  else
    warn "opencode needs Node.js (npm). Install it first:  tekt install"
    return 1
  fi
  reload_path
  if command_exists opencode; then
    success "opencode installed"
  else
    warn "opencode didn't install. Try: npm i -g opencode-ai@latest"
    return 1
  fi
}

install_crush() {
  section "crush (Charm)"
  if command_exists crush; then success "crush already installed"; return 0; fi
  if command_exists brew; then
    brew install charmbracelet/tap/crush --quiet || true
  elif command_exists npm; then
    npm install -g @charmland/crush --silent || true
  else
    warn "crush needs Homebrew or Node.js (npm)."
    return 1
  fi
  reload_path
  if command_exists crush; then
    success "crush installed"
  else
    warn "crush didn't install. Try: npm install -g @charmland/crush"
    return 1
  fi
}

# =============================================================================
# Connect — let your AI apps use your Spaces (tekt connect [app])
# Registers the MCP filesystem server, scoped to ~/Tekt/Spaces, with each AI
# app on this computer: Claude Code, Claude Desktop, Codex. Re-running replaces
# Tekt's own entry and leaves everything else in those configs alone.
# =============================================================================
TEKT_MCP_NAME="tekt-spaces"
TEKT_MCP_PKG="@modelcontextprotocol/server-filesystem"

claude_desktop_config() {
  case "$(os_type)" in
    macos) echo "$HOME/Library/Application Support/Claude/claude_desktop_config.json" ;;
    *)     echo "${XDG_CONFIG_HOME:-$HOME/.config}/Claude/claude_desktop_config.json" ;;
  esac
}

codex_config() { echo "${CODEX_HOME:-$HOME/.codex}/config.toml"; }

connect_claude_code() {
  if ! command_exists claude; then
    warn "Claude Code isn't installed — skipping. Install: curl -fsSL https://claude.ai/install.sh | bash"
    return 1
  fi
  claude mcp remove --scope user "$TEKT_MCP_NAME" >/dev/null 2>&1 || true
  if claude mcp add --scope user "$TEKT_MCP_NAME" -- npx -y "$TEKT_MCP_PKG" "$TEKT_SPACES" >/dev/null 2>&1; then
    success "Claude Code can use your Spaces (MCP server '$TEKT_MCP_NAME')"
  else
    warn "Claude Code didn't accept the server. Add it by hand:"
    warn "  claude mcp add --scope user $TEKT_MCP_NAME -- npx -y $TEKT_MCP_PKG \"$TEKT_SPACES\""
    return 1
  fi
}

connect_claude_desktop() {
  local cfg merged=1
  cfg="$(claude_desktop_config)"
  if ! claude_desktop_installed && [ ! -d "$(dirname "$cfg")" ]; then
    warn "Claude Desktop isn't installed — skipping. Get it at https://claude.ai/download"
    return 1
  fi
  mkdir -p "$(dirname "$cfg")"
  if [ -f "$cfg" ]; then cp "$cfg" "$cfg.bak-tekt"; fi
  if command_exists python3; then
    python3 - "$cfg" "$TEKT_MCP_NAME" "$TEKT_MCP_PKG" "$TEKT_SPACES" <<'PY' || merged=0
import json, os, sys
path, name, pkg, spaces = sys.argv[1:5]
data = {}
if os.path.exists(path) and os.path.getsize(path) > 0:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
data.setdefault("mcpServers", {})[name] = {"command": "npx", "args": ["-y", pkg, spaces]}
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
  elif command_exists node; then
    node -e '
const fs = require("fs"); const [path, name, pkg, spaces] = process.argv.slice(1);
let data = {}; if (fs.existsSync(path) && fs.statSync(path).size) data = JSON.parse(fs.readFileSync(path, "utf8"));
(data.mcpServers ||= {})[name] = { command: "npx", args: ["-y", pkg, spaces] };
fs.writeFileSync(path, JSON.stringify(data, null, 2) + "\n");' "$cfg" "$TEKT_MCP_NAME" "$TEKT_MCP_PKG" "$TEKT_SPACES" || merged=0
  else
    merged=0
  fi
  if [ "$merged" -eq 1 ]; then
    success "Claude Desktop can use your Spaces after you restart it ($cfg)"
  else
    warn "Couldn't update $cfg (needs python3 or node, and the file must be valid JSON). Your original is untouched."
    return 1
  fi
}

connect_codex() {
  if ! command_exists codex; then
    warn "Codex CLI isn't installed — skipping. Install: npm install -g @openai/codex"
    return 1
  fi
  local cfg; cfg="$(codex_config)"
  mkdir -p "$(dirname "$cfg")"
  if [ -f "$cfg" ]; then
    cp "$cfg" "$cfg.bak-tekt"
    # drop Tekt's previous block (and trailing blank lines), keep everything else
    awk -v h="[mcp_servers.$TEKT_MCP_NAME]" '$0 == h { skip = 1; next } /^\[/ { skip = 0 } !skip' "$cfg.bak-tekt" \
      | awk 'NF { while (n > 0) { print ""; n-- } print; next } { n++ }' > "$cfg"
  fi
  printf '\n[mcp_servers.%s]\ncommand = "npx"\nargs = ["-y", "%s", "%s"]\n' "$TEKT_MCP_NAME" "$TEKT_MCP_PKG" "$TEKT_SPACES" >> "$cfg"
  success "Codex can use your Spaces ($cfg)"
}

opencode_config() { echo "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json"; }
crush_config()    { echo "${XDG_CONFIG_HOME:-$HOME/.config}/crush/crushrc"; }

connect_opencode() {
  if ! command_exists opencode; then
    warn "opencode isn't installed — skipping. Install: npm i -g opencode-ai@latest"
    return 1
  fi
  local cfg; cfg="$(opencode_config)"
  mkdir -p "$(dirname "$cfg")"
  if [ -f "$cfg" ]; then cp "$cfg" "$cfg.bak-tekt"; fi
  if command_exists python3 && python3 - "$cfg" "$TEKT_MCP_NAME" "$TEKT_MCP_PKG" "$TEKT_SPACES" <<'PY'
import json, os, sys
path, name, pkg, spaces = sys.argv[1:5]
data = {"$schema": "https://opencode.ai/config.json"}
if os.path.exists(path) and os.path.getsize(path) > 0:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)   # a JSONC file with comments fails here and is left alone
data.setdefault("mcp", {})[name] = {"type": "local", "command": ["npx", "-y", pkg, spaces], "enabled": True}
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
  then
    success "opencode can use your Spaces ($cfg)"
  else
    warn "Couldn't update $cfg by itself (it may contain comments). Add this under \"mcp\":"
    warn "  \"$TEKT_MCP_NAME\": { \"type\": \"local\", \"command\": [\"npx\", \"-y\", \"$TEKT_MCP_PKG\", \"$TEKT_SPACES\"], \"enabled\": true }"
    return 1
  fi
}

connect_crush() {
  if ! command_exists crush; then
    warn "crush isn't installed — skipping. Install: npm install -g @charmland/crush"
    return 1
  fi
  local cfg begin end path
  cfg="$(crush_config)"
  begin="# >>> $TEKT_MCP_NAME (managed by tekt connect) >>>"
  end="# <<< $TEKT_MCP_NAME <<<"
  path="$(printf '%s' "$TEKT_SPACES" | sed 's/[\\"$`]/\\&/g')"   # crushrc is Bash: escape for double quotes
  mkdir -p "$(dirname "$cfg")"
  if [ -f "$cfg" ]; then
    cp "$cfg" "$cfg.bak-tekt"
    awk -v b="$begin" -v e="$end" '$0 == b { skip = 1; next } skip && $0 == e { skip = 0; next } !skip' "$cfg.bak-tekt" \
      | awk 'NF { while (n > 0) { print ""; n-- } print; next } { n++ }' > "$cfg"
  fi
  printf '\n%s\nmcp add %s --command npx --args -y --args %s --args "%s"\n%s\n' \
    "$begin" "$TEKT_MCP_NAME" "$TEKT_MCP_PKG" "$path" "$end" >> "$cfg"
  success "crush can use your Spaces ($cfg)"
}

tekt_connect() {
  local app="${1:-all}" connected=0
  section "Connect your AI to your Spaces"
  mkdir -p "$TEKT_SPACES"
  case "$app" in
    claude-code|claude|code) connect_claude_code    && connected=1 ;;
    claude-desktop|desktop)  connect_claude_desktop && connected=1 ;;
    codex)                   connect_codex          && connected=1 ;;
    opencode)                connect_opencode       && connected=1 ;;
    crush)                   connect_crush          && connected=1 ;;
    all)
      if command_exists claude; then connect_claude_code && connected=1; fi
      if claude_desktop_installed || [ -d "$(dirname "$(claude_desktop_config)")" ]; then
        connect_claude_desktop && connected=1
      fi
      if command_exists codex; then connect_codex && connected=1; fi
      if command_exists opencode; then connect_opencode && connected=1; fi
      if command_exists crush; then connect_crush && connected=1; fi
      ;;
    *) error "Unknown AI app '$app'. Use: claude-code, claude-desktop, codex, opencode, crush or all."; return 1 ;;
  esac
  case "$app" in
    all|claude-code|claude|code)   # shared skills only concern Claude Code
      if command_exists claude || [ -d "$HOME/.claude" ]; then
        space_link_skills
        success "Shared skills from your Spaces are linked into Claude Code ($TEKT_CLAUDE_SKILLS)"
      fi
      ;;
  esac
  if ! command_exists npx; then
    warn "Your AI apps start the Spaces server with npx, which comes with Node.js. Install it first:  tekt install"
  fi
  echo ""
  if [ "$connected" -eq 0 ]; then
    warn "No AI app connected yet. Tekt connects Claude Code, Claude Desktop, Codex, opencode and crush."
  fi
  log "Other MCP apps: add a server with  command: npx   args: -y $TEKT_MCP_PKG $TEKT_SPACES"
  log "Running MCPHub (tekt mcp)? Apps can also use http://localhost:3000/mcp — it serves /spaces too."
  log "Try it: ask your AI \"What's in my team Space?\""
}

# =============================================================================
# Shared skills — skills in a Space appear in everyone's Claude Code
# (tekt skill list | new <space> <name> | link)
# Links ~/Tekt/Spaces/<space>/skills/<skill>/ into ~/.claude/skills/<space>--<skill>.
# Tekt only ever touches links that point into your Spaces folder.
# =============================================================================
TEKT_CLAUDE_SKILLS="${TEKT_CLAUDE_SKILLS:-$HOME/.claude/skills}"

skill_owned_link() {   # true if $1 is a symlink that points into the Spaces folder
  [ -L "$1" ] || return 1
  case "$(readlink "$1")" in
    "$TEKT_SPACES"/*) return 0 ;;
    *) return 1 ;;
  esac
}

space_link_skills() {  # space_link_skills [space] — link one Space's skills, or every Space's
  local only="${1:-}" link target tspace sdir name skill
  mkdir -p "$TEKT_CLAUDE_SKILLS"
  # Drop Tekt's links whose skill is gone, or whose Space was disconnected.
  for link in "$TEKT_CLAUDE_SKILLS"/*--*; do
    if ! skill_owned_link "$link"; then continue; fi
    if [ -n "$only" ]; then
      case "$(basename "$link")" in "$only"--*) ;; *) continue ;; esac
    fi
    target="$(readlink "$link")"
    tspace="${target#"$TEKT_SPACES"/}"; tspace="${tspace%%/*}"
    if [ ! -f "$target/SKILL.md" ] || [ ! -f "$TEKT_SPACES/$tspace/.tekt-space" ]; then rm -f "$link"; fi
  done
  for sdir in "$TEKT_SPACES"/*/; do
    sdir="${sdir%/}"
    [ -f "$sdir/.tekt-space" ] || continue
    name="$(basename "$sdir")"
    if [ -n "$only" ] && [ "$only" != "$name" ]; then continue; fi
    for skill in "$sdir"/skills/*/; do
      skill="${skill%/}"
      [ -f "$skill/SKILL.md" ] || continue
      link="$TEKT_CLAUDE_SKILLS/$name--$(basename "$skill")"
      if [ -e "$link" ] && ! skill_owned_link "$link"; then
        warn "Skipping $(basename "$link"): something else already lives at $link"
        continue
      fi
      ln -sfn "$skill" "$link"
    done
  done
  return 0
}

skill_list() {
  section "Shared skills"
  local sdir name skill link desc mark found=0
  for sdir in "$TEKT_SPACES"/*/; do
    sdir="${sdir%/}"
    [ -f "$sdir/.tekt-space" ] || continue
    name="$(basename "$sdir")"
    for skill in "$sdir"/skills/*/; do
      skill="${skill%/}"
      [ -f "$skill/SKILL.md" ] || continue
      found=1
      link="$TEKT_CLAUDE_SKILLS/$name--$(basename "$skill")"
      desc="$(sed -n '/^description:/{s/^description:[[:space:]]*//p;q;}' "$skill/SKILL.md")"
      if skill_owned_link "$link"; then mark="${GREEN}●${RESET}"; else mark="${YELLOW}○${RESET}"; fi
      printf "  %b %-28s %s\n" "$mark" "$name/$(basename "$skill")" "${desc:-(no description)}"
    done
  done
  if [ "$found" -eq 0 ]; then
    log "No shared skills yet. Make one:  tekt skill new team summarize"
  else
    log "● in Claude Code (~/.claude/skills)   ○ not linked yet — run: tekt skill link"
  fi
}

skill_new() {
  local space="${1:-}" name="${2:-}" dir
  if [ -z "$space" ] || [ -z "$name" ]; then error "Usage:  tekt skill new <space> <skill-name>"; return 1; fi
  if [ ! -f "$TEKT_SPACES/$space/.tekt-space" ]; then error "No Space named '$space'. See:  tekt space list"; return 1; fi
  name="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9-' '-' | sed 's/^-*//; s/-*$//')"
  if [ -z "$name" ]; then error "Give the skill a name, e.g.  tekt skill new $space summarize"; return 1; fi
  dir="$TEKT_SPACES/$space/skills/$name"
  if [ -f "$dir/SKILL.md" ]; then warn "Skill '$name' already exists: $dir/SKILL.md"; return 0; fi
  mkdir -p "$dir"
  cat > "$dir/SKILL.md" <<EOF
---
name: $name
description: One line: what this skill does and when to use it.
---

# $name

## When to use
- Describe the situations where an AI should reach for this skill.

## Steps
1. First step.
2. Next step.

## Notes
- Anything the AI should know: sources, tone, formats, pitfalls.
EOF
  space_link_skills "$space"
  success "New skill: $dir/SKILL.md"
  log "Edit it, then run  tekt space sync $space  — everyone in the Space gets it."
}

# =============================================================================
# RcloneView — a point-and-click window onto your storage (tekt space gui)
# Freemium and proprietary (Bdrive Inc.): core features free, Plus adds
# scheduling and filters. Installed on desktops only.
# =============================================================================
RCLONEVIEW_APPIMAGE="$HOME/.local/bin/RcloneView.AppImage"

has_desktop() {
  [ "$(os_type)" = macos ] || [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]
}

rcloneview_installed() {
  case "$(os_type)" in
    macos) [ -d "/Applications/RcloneView.app" ] || [ -d "$HOME/Applications/RcloneView.app" ] ;;
    *)     [ -x "$RCLONEVIEW_APPIMAGE" ] || command_exists rcloneview ;;
  esac
}

install_rcloneview() {
  section "RcloneView (point-and-click window onto your storage)"
  if rcloneview_installed; then success "RcloneView already installed"; return 0; fi
  if ! has_desktop; then
    log "No desktop on this machine — skipping RcloneView. Spaces work fine from the terminal."
    return 0
  fi
  case "$(os_type)" in
    macos)
      if command_exists brew; then
        brew install --cask rcloneview --quiet || true
      else
        warn "Install Homebrew first, or download RcloneView from https://rcloneview.com"
        return 1
      fi
      ;;
    linux)
      local arch url
      case "$(arch_type)" in
        amd64) arch=x86_64 ;;
        arm64) arch=aarch64 ;;
        *) warn "There's no RcloneView build for this CPU — see https://rcloneview.com"; return 1 ;;
      esac
      url="https://downloads.bdrive.com/rclone_view/linux/${RCLONEVIEW_LINUX_VERSION%.*}/RcloneView-${RCLONEVIEW_LINUX_VERSION}-${arch}.AppImage"
      ensure_local_bin
      log "Downloading RcloneView ${RCLONEVIEW_LINUX_VERSION} (AppImage, no sudo needed)..."
      if ! { curl -fL --progress-bar "$url" -o "$RCLONEVIEW_APPIMAGE" && chmod +x "$RCLONEVIEW_APPIMAGE"; }; then
        rm -f "$RCLONEVIEW_APPIMAGE"
        warn "The download didn't work — get RcloneView from https://rcloneview.com"
        return 1
      fi
      ;;
    *)
      warn "Get RcloneView from https://rcloneview.com"
      return 1
      ;;
  esac
  if rcloneview_installed; then
    success "RcloneView installed. It's freemium: the core features are free; RcloneView Plus adds scheduling and filters."
  else
    warn "RcloneView didn't install — get it from https://rcloneview.com"
    return 1
  fi
}

tekt_gui() {
  if ! has_desktop; then
    error "RcloneView needs a desktop. On this machine, use  tekt space list  and  tekt space open <name>."
    return 1
  fi
  install_rcloneview || return 1
  case "$(os_type)" in
    macos)
      open -a RcloneView
      ;;
    *)
      if ! ldconfig -p 2>/dev/null | grep "libfuse.so.2" >/dev/null; then
        warn "RcloneView (an AppImage) needs FUSE 2. Ubuntu/Debian: sudo apt install libfuse2   Fedora: sudo dnf install fuse"
      fi
      nohup "$RCLONEVIEW_APPIMAGE" >/dev/null 2>&1 &
      ;;
  esac
  success "RcloneView is opening — use it to browse and copy files between your computer and your cloud storage. Your Spaces live in $TEKT_SPACES."
}

# The tekt command: a copy of this script on your PATH (tekt space …, tekt status)
install_tekt_cli() {
  ensure_local_bin
  mkdir -p "$(dirname "$TEKT_BIN")"
  local src="${BASH_SOURCE[0]:-}"
  if [ -n "$src" ] && [ -f "$src" ]; then
    [ "$src" -ef "$TEKT_BIN" ] || cp "$src" "$TEKT_BIN"
  else
    curl -fsSL https://tekt.md/install.sh -o "$TEKT_BIN" || { warn "Couldn't download the tekt command — try again later."; return 1; }
  fi
  chmod +x "$TEKT_BIN"
  success "tekt command ready: $TEKT_BIN  (try: tekt help)"
}

tekt_help() {
  local me; me="$(basename "$0")"
  [ "$me" = "tekt" ] || me="bash install.sh"
  cat <<EOF
Usage: $me [command]

Share with your AI and your people
  space add <name> [storage] [folder]  Make a Space: a folder synced with Google Drive,
                                       OneDrive, Dropbox, Box, Nextcloud or a NAS folder
                                       (storage: drive, onedrive, dropbox, box, nextcloud, folder, s3)
  space list                           Show your Spaces
  space sync [name]                    Sync now (every Space, or one)
  space invite <name>                  Write an invitation to a Space (copied to your clipboard)
  space open <name>                    Open a Space's folder
  space gui                            Open your storage in a point-and-click window (RcloneView)
  space remove <name>                  Disconnect a Space (keeps every file)
  space autosync on|off                Sync every 10 minutes in the background
  connect [app]                        Let your AI apps use your Spaces
                                       (app: claude-code, claude-desktop, codex, opencode, crush;
                                        default: every one found)
  skill list                           Skills shared in your Spaces, and which are in Claude Code
  skill new <space> <name>             Start a skill in a Space; everyone gets it after sync
  skill link                           Re-link shared skills into Claude Code

Set up and check
  install        Install all Tekt tools (what the one-line installer runs)
  status         Check which tools are installed
  catalog        Print the tool catalog (tekt.catalog.yaml)
  mcp            Bring up MCPHub + the curated MCP servers (:3000)
  ui             Bring up LibreChat (:3080) and n8n (:5678)
  share [port]   HTTPS-expose a local port (Tailscale Serve, else ngrok)
  cli            Install the tekt command into ~/.local/bin
  help           Show this help

Guide: https://tekt.md/spaces/
EOF
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
  check "GitHub CLI"      gh
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
  check "Codex CLI"       codex
  check "opencode"        opencode
  check "crush"           crush

  echo ""
  log "Staged (tekt.cloud): MCPHub/LibreChat/n8n/Sovrant — bring up with:"
  log "  bash install.sh mcp     # MCPHub + curated MCP servers on :3000"
  log "  bash install.sh ui      # LibreChat :3080 and n8n :5678"
  log "  Sovrant Web :5100       # cd \$TEKT_INSTANCE/sovrant && dotnet run --project src/Sovrant.Web"
  log "Restart your terminal/session to reload PATH (required after some installs)."
  log "Share a folder with your AI and your people:  tekt space add team drive   (guide: https://tekt.md/spaces/)"
  log "Let your AI apps use your Spaces:              tekt connect"
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
        gh)      ver="$(gh --version 2>/dev/null | head -1)" ;;
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
  check_tool "GitHub CLI"      gh        dev
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
  if rcloneview_installed; then
    printf "  ${GREEN}✓${RESET}  %-18s %s\n" "RcloneView" "installed — point-and-click window onto your storage"
  else
    printf "  ${YELLOW}?${RESET}  %-18s %s\n" "RcloneView" "optional window onto your storage — tekt space gui"
  fi
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
  check_tool "Codex CLI"       codex     iris
  check_tool "opencode"        opencode  iris
  check_tool "crush"           crush     iris
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

  echo ""
  echo -e "${BOLD}Spaces — shared with your AI and your people${RESET}"
  local sdir sfound=0 slast
  for sdir in "$TEKT_SPACES"/*/; do
    sdir="${sdir%/}"
    [ -f "$sdir/.tekt-space" ] || continue
    sfound=1
    slast="$(space_meta "$sdir" last_sync)"
    printf "  ${GREEN}✓${RESET}  %-18s %s\n" "$(basename "$sdir")" "last sync ${slast:-never} — $sdir"
  done
  if [ "$sfound" -eq 0 ]; then printf "  ${YELLOW}?${RESET}  %-18s %s\n" "No Spaces yet" "tekt space add team drive"; fi
  local sk sk_total=0 sk_linked=0
  for sk in "$TEKT_SPACES"/*/skills/*/SKILL.md; do
    if [ -f "$sk" ] && [ -f "$(dirname "$(dirname "$(dirname "$sk")")")/.tekt-space" ]; then sk_total=$((sk_total + 1)); fi
  done
  for sk in "$TEKT_CLAUDE_SKILLS"/*--*; do
    if skill_owned_link "$sk"; then sk_linked=$((sk_linked + 1)); fi
  done
  if [ "$sk_total" -gt 0 ]; then
    printf "  ${GREEN}✓${RESET}  %-18s %s\n" "Shared skills" "$sk_linked of $sk_total linked into Claude Code"
  fi

  echo ""
  echo -e "${BOLD}AI apps connected to your Spaces${RESET}"
  local capps=0
  if grep -q "\"$TEKT_MCP_NAME\"" "$HOME/.claude.json" 2>/dev/null; then
    printf "  ${GREEN}✓${RESET}  %-18s %s\n" "Claude Code" "uses your Spaces"; capps=1
  fi
  if grep -q "\"$TEKT_MCP_NAME\"" "$(claude_desktop_config)" 2>/dev/null; then
    printf "  ${GREEN}✓${RESET}  %-18s %s\n" "Claude Desktop" "uses your Spaces"; capps=1
  fi
  if grep -q "^\[mcp_servers\.$TEKT_MCP_NAME\]" "$(codex_config)" 2>/dev/null; then
    printf "  ${GREEN}✓${RESET}  %-18s %s\n" "Codex" "uses your Spaces"; capps=1
  fi
  if grep -q "\"$TEKT_MCP_NAME\"" "$(opencode_config)" 2>/dev/null; then
    printf "  ${GREEN}✓${RESET}  %-18s %s\n" "opencode" "uses your Spaces"; capps=1
  fi
  if grep -q "^mcp add $TEKT_MCP_NAME " "$(crush_config)" 2>/dev/null; then
    printf "  ${GREEN}✓${RESET}  %-18s %s\n" "crush" "uses your Spaces"; capps=1
  fi
  if [ "$capps" -eq 0 ]; then printf "  ${YELLOW}?${RESET}  %-18s %s\n" "None yet" "tekt connect"; fi

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
  echo -e "  ${BOLD}Tekt${RESET} — the utility belt for your AI harness  ·  https://tekt.md"
  echo -e "  Pre-vetted tools for an AI sandbox. Bring your own intelligence: Ollama, OpenRouter, OpenAI, Anthropic."
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
  install_gh            || warn "GitHub CLI install failed — continuing..."
  install_system_deps   || warn "System deps install failed — continuing..."
  install_go            || warn "Go install failed — continuing..."
  install_python        || warn "Python install failed — continuing..."
  install_nvm_node      || warn "nvm/Node install failed — continuing..."
  install_vscode        || warn "VSCode install failed — continuing..."
  install_docker        || warn "Docker install failed — continuing..."

  # ── Tekt.Base ──
  install_rclone        || warn "rclone install failed — continuing..."
  install_s3_tools      || warn "S3 tools install failed — continuing..."
  install_tekt_cli      || warn "tekt command install failed — continuing..."
  install_rcloneview    || warn "RcloneView install skipped — continuing..."

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
  install_codex         || warn "Codex CLI install failed — continuing..."
  install_opencode      || warn "opencode install failed — continuing..."
  install_crush         || warn "crush install failed — continuing..."

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
  space)
    shift
    case "${1:-list}" in
      add)       shift; space_add "$@" ;;
      list|ls)   space_list ;;
      sync)      space_sync "${2:-}" ;;
      remove|rm) space_remove "${2:-}" ;;
      invite)    space_invite "${2:-}" ;;
      open)      space_open "${2:-}" ;;
      gui)       tekt_gui ;;
      autosync)  space_autosync "${2:-on}" ;;
      *) error "Unknown: space ${1} — use add, list, sync, invite, open, remove or autosync"; exit 1 ;;
    esac
    ;;
  cli)
    install_tekt_cli
    ;;
  gui)
    tekt_gui
    ;;
  connect)
    tekt_connect "${2:-all}"
    ;;
  skill|skills)
    shift
    case "${1:-list}" in
      list|ls) skill_list ;;
      new)     skill_new "${2:-}" "${3:-}" ;;
      link)    space_link_skills && success "Shared skills linked into Claude Code ($TEKT_CLAUDE_SKILLS)" ;;
      *) error "Unknown: skill ${1} — use list, new or link"; exit 1 ;;
    esac
    ;;
  install)
    main
    ;;
  help|--help|-h)
    tekt_help
    ;;
  "")
    # `tekt` on its own shows help; running the installer file installs everything.
    if [ "$(basename "$0")" = "tekt" ]; then tekt_help; else main; fi
    ;;
  *)
    error "Unknown command: $1"
    echo "Run '$(basename "$0") help' for usage."
    ;;
esac
