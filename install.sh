#!/usr/bin/env bash
# =============================================================================
# tekt-bootstrap.sh
# Tekt Platform — Full Environment Bootstrap
# https://tekt.md
#
# Installs: Homebrew, Go, Python (pyenv), nvm/Node, rclone, AWS CLI,
#           VSCode, Claude Code, OpenClaw, PicoClaw, Hermes Agent
#
# Supported: macOS (Intel + Apple Silicon), Ubuntu/Debian, Fedora/RHEL
# Usage:     curl -fsSL https://tekt.md/install.sh | bash
#            — or —
#            bash tekt-bootstrap.sh
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

# ── Repo / binary sources for Tekt-native tools ───────────────────────────────
OPENCLAW_REPO="https://github.com/openclaw/openclaw"
PICOCLAW_REPO="https://github.com/sipeed/picoclaw"
HERMES_REPO="https://github.com/NousResearch/hermes-agent"

# ── Helpers ───────────────────────────────────────────────────────────────────
command_exists() { command -v "$1" &>/dev/null; }

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
  # Re-source common shell profile snippets so subsequent commands see new bins
  for f in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.zshrc" "$HOME/.profile"; do
    [ -f "$f" ] && source "$f" 2>/dev/null || true
  done
  export PATH="$HOME/.local/bin:$HOME/go/bin:/usr/local/go/bin:$PATH"
  # Homebrew
  if [ -f "/opt/homebrew/bin/brew" ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -f "/usr/local/bin/brew" ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  elif [ -f "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  fi
  # pyenv
  export PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
  [[ -d "$PYENV_ROOT/bin" ]] && export PATH="$PYENV_ROOT/bin:$PATH"
  command_exists pyenv && eval "$(pyenv init -)" 2>/dev/null || true
  # nvm
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
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

  # Prefer the official install script (handles platform detection)
  log "Installing OpenClaw..."
  if curl -fsSL https://openclaw.ai/install.sh -o /tmp/openclaw-install.sh 2>/dev/null; then
    bash /tmp/openclaw-install.sh
    rm -f /tmp/openclaw-install.sh
    success "OpenClaw installed (script)"
  elif command_exists npm; then
    # Fallback: npm global install
    log "Install script not reachable — falling back to npm..."
    npm install -g openclaw@latest
    success "OpenClaw installed (npm)"
  else
    error "Could not install OpenClaw. Install manually:"
    error "  npm install -g openclaw@latest"
    error "  — or —"
    error "  curl -fsSL https://openclaw.ai/install.sh | bash"
    return
  fi

  if command_exists openclaw; then
    log "Run 'openclaw onboard --install-daemon' to complete setup."
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
      log "Run 'openclaw onboard --install-daemon' to complete setup."
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
# Summary
# =============================================================================
print_summary() {
  reload_path

  section "Installation Summary"
  echo ""

  check() {
    local label="$1" cmd="$2"
    if command_exists "$cmd"; then
      local ver
      case "$cmd" in
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
  # ── Tekt.Base ──
  check "rclone"          rclone
  check "aws-cli"         aws
  check "s3cmd"           s3cmd
  check "s5cmd"           s5cmd
  # ── Tekt.Iris ──
  check "Claude Code"     claude
  check "OpenClaw"        openclaw
  check "PicoClaw"        picoclaw
  check "Hermes Agent"    hermes

  echo ""
  log "Restart your terminal (or run: source ~/.zshrc) to reload PATH."
  log "Docs: https://tekt.md"
  echo ""
}

# =============================================================================
# Main
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

  # ── Tekt.Iris ──
  install_claude_code   || warn "Claude Code install failed — continuing..."
  install_openclaw      || warn "OpenClaw install failed — continuing..."
  install_picoclaw      || warn "PicoClaw install failed — continuing..."
  install_hermes        || warn "Hermes Agent install failed — continuing..."

  print_summary
}

main "$@"
