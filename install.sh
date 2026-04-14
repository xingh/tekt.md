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
GO_VERSION="1.22.4"
PYTHON_VERSION="3.12.4"
NODE_VERSION="20"          # LTS major; nvm installs latest patch
NVM_VERSION="0.40.1"

# ── Repo / binary sources for Tekt-native tools ───────────────────────────────
# TODO: Replace these with final release URLs once published
OPENCLAW_REPO="https://github.com/anantcorp/openclaw"
PICOCLAW_REPO="https://github.com/anantcorp/picoclaw"
HERMES_REPO="https://github.com/anantcorp/hermes-agent"

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
      error "sudo is required but not available. Re-run as root."
      exit 1
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
  # nvm
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
}

append_to_shell_profile() {
  local line="$1"
  for f in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.zshrc"; do
    [ -f "$f" ] && grep -qF "$line" "$f" 2>/dev/null || echo "$line" >> "$f"
  done
}

# =============================================================================
# 1. Homebrew
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
# 2. System dependencies (Linux only)
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
        build-essential curl wget git unzip zip tar \
        libssl-dev libffi-dev zlib1g-dev libbz2-dev \
        libreadline-dev libsqlite3-dev liblzma-dev \
        xz-utils ca-certificates gnupg
      ;;
    fedora|rhel|centos|rocky|alma)
      $SUDO dnf groupinstall -y "Development Tools"
      $SUDO dnf install -y \
        curl wget git unzip zip tar \
        openssl-devel libffi-devel zlib-devel bzip2-devel \
        readline-devel sqlite-devel xz-devel ca-certificates gnupg2
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

  log "Downloading $tarball..."
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
    append_to_shell_profile 'export PYENV_ROOT="$HOME/.pyenv"'
    append_to_shell_profile 'export PATH="$PYENV_ROOT/bin:$PATH"'
    append_to_shell_profile 'eval "$(pyenv init -)"'
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"
  else
    success "pyenv already installed — $(pyenv --version)"
  fi

  if pyenv versions --bare | grep -qx "$PYTHON_VERSION"; then
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
# 5. nvm + Node.js + npm
# =============================================================================
install_nvm_node() {
  section "nvm + Node.js $NODE_VERSION LTS"

  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

  if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    log "Installing nvm $NVM_VERSION..."
    curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" | bash
    append_to_shell_profile 'export NVM_DIR="$HOME/.nvm"'
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
# 6. rclone
# =============================================================================
install_rclone() {
  section "rclone"
  if command_exists rclone; then
    success "rclone already installed — $(rclone version | head -1)"
    return
  fi

  log "Installing rclone..."
  curl -fsSL https://rclone.org/install.sh | bash

  success "rclone $(rclone version | head -1 | awk '{print $2}') installed"
}

# =============================================================================
# 7. AWS CLI + s3 utilities
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
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    arch="$(arch_type)"
    tmpdir="$(mktemp -d)"

    if [ "$os" = "darwin" ]; then
      local pkg="AWSCLIV2.pkg"
      curl -fsSL "https://awscli.amazonaws.com/${pkg}" -o "$tmpdir/$pkg"
      $SUDO installer -pkg "$tmpdir/$pkg" -target /
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
    log "Installing s3cmd..."
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
      go install github.com/peak/s5cmd/v2@latest
    fi
    success "s5cmd installed"
  fi
}

# =============================================================================
# 8. Visual Studio Code
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
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
          | gpg --dearmor \
          | $SUDO tee /usr/share/keyrings/packages.microsoft.gpg > /dev/null
        echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/packages.microsoft.gpg] \
          https://packages.microsoft.com/repos/code stable main" \
          | $SUDO tee /etc/apt/sources.list.d/vscode.list > /dev/null
        $SUDO apt-get update -q
        $SUDO apt-get install -y -q code
        ;;
      fedora|rhel|centos|rocky|alma)
        require_sudo
        $SUDO rpm --import https://packages.microsoft.com/keys/microsoft.asc
        $SUDO sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
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
# 9. Claude Code
# =============================================================================
install_claude_code() {
  section "Claude Code"

  # Ensure nvm / node is loaded
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

  if command_exists claude; then
    success "Claude Code already installed — $(claude --version 2>/dev/null || echo 'version unknown')"
    return
  fi

  log "Installing Claude Code via npm..."
  npm install -g @anthropic-ai/claude-code

  success "Claude Code installed — $(claude --version 2>/dev/null || echo 'run: claude')"
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

  # ── Option A: npm package (uncomment when published) ────────────────────────
  # npm install -g @anantcorp/openclaw

  # ── Option B: install script from release (active path) ─────────────────────
  log "Installing OpenClaw from $OPENCLAW_REPO ..."
  if curl -fsSL "${OPENCLAW_REPO}/releases/latest/download/install.sh" -o /tmp/openclaw-install.sh 2>/dev/null; then
    bash /tmp/openclaw-install.sh
    rm -f /tmp/openclaw-install.sh
    success "OpenClaw installed"
  else
    warn "OpenClaw install script not reachable at ${OPENCLAW_REPO}."
    warn "Clone manually:"
    warn "  git clone ${OPENCLAW_REPO} && cd openclaw && npm install && npm link"
  fi
}

# =============================================================================
# 11. PicoClaw
# =============================================================================
install_picoclaw() {
  section "PicoClaw"

  if command_exists picoclaw; then
    success "PicoClaw already installed — $(picoclaw --version 2>/dev/null || echo 'version unknown')"
    return
  fi

  log "Installing PicoClaw from $PICOCLAW_REPO ..."
  if curl -fsSL "${PICOCLAW_REPO}/releases/latest/download/install.sh" -o /tmp/picoclaw-install.sh 2>/dev/null; then
    bash /tmp/picoclaw-install.sh
    rm -f /tmp/picoclaw-install.sh
    success "PicoClaw installed"
  else
    warn "PicoClaw install script not reachable at ${PICOCLAW_REPO}."
    warn "Clone manually:"
    warn "  git clone ${PICOCLAW_REPO} && cd picoclaw && npm install && npm link"
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

  log "Installing Hermes Agent from $HERMES_REPO ..."
  if curl -fsSL "${HERMES_REPO}/releases/latest/download/install.sh" -o /tmp/hermes-install.sh 2>/dev/null; then
    bash /tmp/hermes-install.sh
    rm -f /tmp/hermes-install.sh
    success "Hermes Agent installed"
  else
    warn "Hermes install script not reachable at ${HERMES_REPO}."
    warn "Clone manually:"
    warn "  git clone ${HERMES_REPO} && cd hermes-agent && go build -o hermes . && mv hermes /usr/local/bin/"
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
        brew)   ver="$(brew --version | head -1)" ;;
        go)     ver="$(go version | awk '{print $3}')" ;;
        python3) ver="$(python3 --version)" ;;
        node)   ver="$(node --version)" ;;
        npm)    ver="$(npm --version)" ;;
        rclone) ver="$(rclone version | head -1 | awk '{print $2}')" ;;
        aws)    ver="$(aws --version | awk '{print $1}')" ;;
        code)   ver="$(code --version | head -1)" ;;
        claude) ver="$(claude --version 2>/dev/null || echo 'installed')" ;;
        *)      ver="installed" ;;
      esac
      printf "  ${GREEN}✓${RESET}  %-18s %s\n" "$label" "$ver"
    else
      printf "  ${YELLOW}?${RESET}  %-18s %s\n" "$label" "(not in PATH — may need shell reload)"
    fi
  }

  check "Homebrew"      brew
  check "Go"            go
  check "Python"        python3
  check "Node.js"       node
  check "npm"           npm
  check "rclone"        rclone
  check "aws-cli"       aws
  check "s3cmd"         s3cmd
  check "s5cmd"         s5cmd
  check "VSCode"        code
  check "Claude Code"   claude
  check "OpenClaw"      openclaw
  check "PicoClaw"      picoclaw
  check "Hermes Agent"  hermes

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

  install_homebrew
  install_system_deps
  install_go
  install_python
  install_nvm_node
  install_rclone
  install_s3_tools
  install_vscode
  install_claude_code
  install_openclaw
  install_picoclaw
  install_hermes

  print_summary
}

main "$@"
