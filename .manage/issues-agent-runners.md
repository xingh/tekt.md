# Agent Runners — New Additions for tekt.iris (Issue #15)

This backlog plans the work to add four new agent runners to tekt.iris.

| Tool | Layer | Language/Runtime | License |
|------|-------|-----------------|---------|
| [opencode](https://github.com/anomalyco/opencode) | tekt.iris | Node.js (npm) | MIT |
| [crush](https://github.com/charmbracelet/crush) | tekt.iris | Go (single binary) | MIT |
| [open-design](https://github.com/nexu-io/open-design) | tekt.cloud | Desktop app + MCP | Apache 2.0 |
| [pi](https://github.com/earendil-works/pi) | tekt.iris | Node.js/TypeScript | MIT |

---

## 1. Add opencode to tekt.iris agent layer

**Upstream:** [anomalyco/opencode](https://github.com/anomalyco/opencode)  
**Layer:** `tekt.iris` (Intelligence — Agents & Models)  
**Runtime:** Node.js (npm)  
**License:** MIT  
**Install cmd:** `npm i -g opencode-ai@latest` or `curl -fsSL https://opencode.ai/install | bash`  
**Platform support:** macOS, Linux, WSL2, Windows (Scoop/Chocolatey/winget), Arch Linux  

### Summary

[opencode](https://opencode.ai) is an open-source AI coding agent — a fully featured terminal-based assistant that supports multiple LLM providers and integrates with MCP servers. It is the open-source counterpart to Claude Code and fits directly in tekt.iris alongside it.

### Work to do

#### 1. Catalog entry (`tekt.catalog.yaml`)

Add to the `tekt.iris` layer tools list:

```yaml
- name: opencode
  cmd: opencode
  upstream: "anomalyco & contributors (MIT)"
  repo: https://github.com/anomalyco/opencode
  install: "npm i -g opencode-ai@latest"
  install_macos: "brew install anomalyco/tap/opencode"
  install_windows: "scoop install opencode"
  note: "Open-source AI coding agent; multi-model, MCP-extensible, desktop app available."
```

#### 2. Installer function (`install.sh`)

Add `install_opencode()` function that:
- Checks if `opencode` is already installed (`opencode --version`)
- Installs via `npm i -g opencode-ai@latest` (Node.js must be installed; tekt.dev layer handles this)
- Alternatively on macOS: `brew install anomalyco/tap/opencode`
- Prints version and first-run hint on success
- Calls the function from `main()`
- Adds `opencode` to the `tekt_status` check

#### 3. PowerShell installer (`install.ps1`)

Add Windows install path via `scoop install opencode` or `npm i -g opencode-ai@latest`.

#### 4. Documentation (`03-software.md`)

Add opencode to the agent section with:
- Brief description
- MCP configuration notes (opencode reads from `~/.opencode/config.json`)
- Link to upstream docs at [opencode.ai/docs](https://opencode.ai/docs)

#### 5. README.md table

Add row to the `Tekt.Iris — Intelligence` table:

| opencode | Open-source AI coding agent CLI, multi-model, MCP-extensible | anomalyco (MIT) |

### Testing checklist

- [ ] `install.sh` installs opencode on macOS (Intel + Apple Silicon)
- [ ] `install.sh` installs opencode on Ubuntu/Debian
- [ ] `install.sh` installs opencode on Fedora/RHEL
- [ ] `install.sh` installs opencode on Arch Linux
- [ ] `install.sh` installs opencode on WSL2
- [ ] `install.ps1` installs opencode on Windows (native PowerShell)
- [ ] `install.sh status` shows opencode version correctly
- [ ] `opencode --version` runs after install
- [ ] MCP server integration: opencode can connect to the tekt MCPHub at `localhost:3000/mcp`
- [ ] Desktop app download link verified in docs

### Notes

- opencode requires Node.js (already guaranteed by the tekt.dev layer)
- Interactive onboarding: run `opencode` after install and complete the setup wizard
- The desktop app (BETA) is available for download at [opencode.ai/download](https://opencode.ai/download) — consider adding a `brew install --cask opencode-desktop` path for macOS

---

## 2. Add crush to tekt.iris agent layer

**Upstream:** [charmbracelet/crush](https://github.com/charmbracelet/crush)  
**Layer:** `tekt.iris` (Intelligence — Agents & Models)  
**Runtime:** Go (single binary)  
**License:** MIT  
**Install cmd:** `brew install charmbracelet/tap/crush` or `npm install -g @charmland/crush`  
**Platform support:** macOS, Linux, Windows (PowerShell, WSL), Android, FreeBSD, OpenBSD, NetBSD  

### Summary

[Crush](https://github.com/charmbracelet/crush) is a terminal-based AI coding agent built by the [Charmbracelet](https://charm.sh) team — the authors behind widely used Go TUI libraries such as Bubble Tea, Lip Gloss, and Glamour. Crush is multi-model (OpenAI, Anthropic, and any OpenAI- or Anthropic-compatible API), session-based, LSP-enhanced, and MCP-extensible via `http`, `stdio`, and `sse`. It is distributed as a single Go binary with first-class cross-platform support and is ideal as a complement to the existing Go-based tools in tekt.

### Work to do

#### 1. Catalog entry (`tekt.catalog.yaml`)

Add to the `tekt.iris` layer tools list:

```yaml
- name: Crush
  cmd: crush
  upstream: "Charmbracelet (MIT)"
  repo: https://github.com/charmbracelet/crush
  install_macos: "brew install charmbracelet/tap/crush"
  install_linux: "brew install charmbracelet/tap/crush"
  install_windows: "winget install charmbracelet.crush"
  note: >
    Multi-model terminal coding agent by Charmbracelet; LSP-enhanced,
    MCP-extensible (http/stdio/sse), session-based. Config at ~/.config/crush/.
```

#### 2. Installer function (`install.sh`)

Add `install_crush()` function that:
- Checks if `crush` is already installed (`crush --version`)
- Installs via `brew install charmbracelet/tap/crush` (preferred on macOS/Linux where Homebrew is present)
- Falls back to `npm install -g @charmland/crush` if Homebrew is not available
- Alternatively: download binary from GitHub Releases for platforms without Homebrew or npm
- Prints version and first-run hint on success
- Calls the function from `main()`
- Adds `crush` to `tekt_status` check

#### 3. PowerShell installer (`install.ps1`)

Add Windows install path:
- `winget install charmbracelet.crush`
- Or: `scoop install charm; scoop install crush` (via Scoop charm bucket)

#### 4. Documentation (`03-software.md`)

Add crush to the agent section with:
- Brief description mentioning Charmbracelet ecosystem
- How to connect to MCPHub: add `tekt.cloud` MCPHub entry to `~/.config/crush/crush.json`
- Link to upstream docs and the `crush.json` schema at [schema.json](https://github.com/charmbracelet/crush/blob/main/schema.json)

#### 5. README.md table

Add row to the `Tekt.Iris — Intelligence` table:

| Crush | Multi-model terminal coding agent, LSP-enhanced, MCP-extensible | Charmbracelet (MIT) |

### Testing checklist

- [ ] `install.sh` installs crush on macOS (Intel + Apple Silicon)
- [ ] `install.sh` installs crush on Ubuntu/Debian
- [ ] `install.sh` installs crush on Fedora/RHEL
- [ ] `install.sh` installs crush on Arch Linux
- [ ] `install.sh` installs crush on WSL2
- [ ] `install.ps1` installs crush on Windows via winget
- [ ] `install.sh status` shows crush version correctly
- [ ] `crush --version` runs after install
- [ ] MCP integration: crush connects to tekt MCPHub at `localhost:3000/mcp` (configure in `~/.config/crush/crush.json`)
- [ ] Session management: `crush` starts a new session, context is preserved
- [ ] LSP integration: verify LSP features work alongside existing Go/Python tooling

### Notes

- Crush config is a single JSON file; the schema is published at `crush.json` / `schema.json` in the repo
- The `@charmland/crush` npm package is an alternative install path that doesn't require Go
- Charmbracelet maintains a Homebrew tap (`charmbracelet/tap`) and an apt/yum repo at `repo.charm.sh`
- Built on the Charm ecosystem — compatible with Bubbletea TUI tooling already present in the Go ecosystem

---

## 3. Add open-design to tekt.iris or tekt.cloud layer

**Upstream:** [nexu-io/open-design](https://github.com/nexu-io/open-design)  
**Layer:** `tekt.cloud` (or `tekt.iris`) — design tool / agent-native studio  
**Runtime:** Desktop app (macOS, Windows) + CLI skills via agent integration  
**License:** Apache 2.0  
**Install:** Download from [open-design.ai/download](https://open-design.ai/) or via release page  
**Platform support:** macOS, Windows (native desktop app); agent CLI skills work wherever the agent runs  

### Summary

[Open Design](https://open-design.ai) is the open-source alternative to Claude Design and Figma for the agent era. Rather than a canvas-based design tool, it delivers single-page HTML/CSS artifacts, live dashboards, decks, images, video (HyperFrames/MP4), and more — all driven by a `DESIGN.md` design system and rendered through coding agents already on your machine (Claude Code, OpenClaw, OpenCode, Cursor, Codex, Hermes, and 25+ others). It exposes an MCP server for integration and runs skills as a filesystem of composable design templates.

Relevant to tekt.md because:
- It integrates directly with the existing tekt.iris agents (Claude Code, OpenClaw, Hermes, opencode)
- It exposes an MCP server that can plug into the tekt MCPHub
- It is a local-first, self-hosted, agent-native design studio aligned with tekt's sovereignty goals

### Work to do

#### 1. Determine layer placement

Open Design is a desktop application with agent integrations, not a pure CLI agent runner. Recommended placement: `tekt.cloud` (alongside LibreChat, n8n, Sovrant as a UI tool) OR add a new `tekt.design` subsection within `tekt.iris`. **Discuss with maintainer before implementing.**

#### 2. Catalog entry (`tekt.catalog.yaml`)

Proposed entry in `tekt.cloud`:

```yaml
- name: Open Design
  runtime: desktop-app
  upstream: "nexu-io & contributors (Apache-2.0)"
  repo: https://github.com/nexu-io/open-design
  docs: https://open-design.ai
  install_macos: "Download from https://open-design.ai/download"
  install_windows: "Download from https://open-design.ai/download"
  note: >
    Open-source Claude Design / Figma alternative for the agent era.
    Delivers HTML/CSS prototypes, decks, images, and video via DESIGN.md
    design systems, integrated with Claude Code, OpenClaw, OpenCode, and others.
    Exposes an MCP server — configure in MCPHub for agent access.
```

#### 3. Installer notes (`install.sh` / `install.ps1`)

Open Design is a desktop GUI app — auto-install is not straightforward for a headless bootstrap script. Recommended approach:
- Print a notice/hint in the `tekt_status` output: "Open Design: not installed — download from https://open-design.ai/download"
- Optionally add a `brew install --cask` path if an official Homebrew cask is published (check upstream)
- On Windows: check for a winget package ID when available

#### 4. MCP integration

Open Design exposes an MCP server. Document how to add it to the MCPHub `mcp_settings.json`:
- Identify the MCP server package name / endpoint from the upstream docs
- Add a sample entry to the `mcp_servers` section in `tekt.catalog.yaml`

#### 5. Documentation (`04-interface.md`)

Add Open Design to the interface doc with:
- Brief description (agent-native design studio, Figma/Claude Design alternative)
- Installation instructions for macOS and Windows
- How to connect to existing tekt.iris agents via `DESIGN.md`
- How to wire the Open Design MCP server into MCPHub

#### 6. README.md table

Add row to the `Tekt.Cloud — Chat, Workflows & Command Center` table (or create a new `Tekt.Design` section):

| Open Design | Agent-native design studio; prototypes, decks, images, video via DESIGN.md | nexu-io (Apache-2.0) |

### Testing checklist

- [ ] Download and install on macOS (Apple Silicon)
- [ ] Download and install on macOS (Intel)
- [ ] Download and install on Windows
- [ ] Verify Open Design can discover and use Claude Code (already installed by tekt)
- [ ] Verify Open Design can discover and use OpenClaw (already installed by tekt)
- [ ] Connect Open Design MCP server to tekt MCPHub — confirm endpoint works
- [ ] Generate a test prototype artifact from a minimal `DESIGN.md`
- [ ] Export artifact to HTML and verify output
- [ ] `install.sh status` shows "Open Design: [version or download hint]"
- [ ] Document any required API keys (Open Design Cloud vs local model)

### Notes

- Open Design Cloud (paid hosted model service) is optional; it also works with local models via BYOK/Ollama
- The `.claude-plugin` directory in the repo suggests it integrates with Claude Code as a plugin — investigate for tekt-specific wiring
- Governance note: Apache 2.0 license; explicitly compatible with tekt's distribution goals

---

## 4. Add pi (earendil-works/pi) to tekt.iris agent layer

**Upstream:** [earendil-works/pi](https://github.com/earendil-works/pi)  
**Layer:** `tekt.iris` (Intelligence — Agents & Models)  
**Runtime:** Node.js / Bun (TypeScript monorepo)  
**License:** MIT  
**Install cmd:** `npm install -g @earendil-works/pi-coding-agent`  
**Platform support:** macOS, Linux, WSL2, Windows  

### Summary

[Pi](https://pi.dev) is the Pi Agent Harness — an interactive coding agent CLI built as a TypeScript/Node.js monorepo with a modular architecture: a unified multi-provider LLM API (`pi-ai`), an agent runtime with tool calling and state management (`pi-agent-core`), and the interactive coding agent CLI (`pi-coding-agent`). Pi supports OpenAI, Anthropic, Google, and other LLM providers, includes a built-in TUI (`pi-tui`), and has a containerization guide for Gondolin/Docker/OpenShell sandboxing.

Pi was previously maintained as `badlogic/pi` (mario@badlogicgames.com) and has strong supply-chain hardening: pinned direct deps, `npm-shrinkwrap.json`, `npm ci --ignore-scripts`, and scheduled audit CI.

### Work to do

#### 1. Catalog entry (`tekt.catalog.yaml`)

Add to the `tekt.iris` layer tools list:

```yaml
- name: Pi
  cmd: pi
  upstream: "earendil-works & contributors (MIT)"
  repo: https://github.com/earendil-works/pi
  install: "npm install -g @earendil-works/pi-coding-agent"
  note: >
    Interactive coding agent CLI (TypeScript/Node); multi-provider LLM API
    (OpenAI, Anthropic, Google, …), tool calling, TUI, sandboxing via
    Gondolin/Docker/OpenShell. Config in ~/.pi/ directory.
```

#### 2. Installer function (`install.sh`)

Add `install_pi()` function that:
- Checks if `pi` is already installed (`pi --version`)
- Installs via `npm install -g @earendil-works/pi-coding-agent` (Node.js must be present; tekt.dev layer handles this)
- Prints version and first-run hint on success
- Calls the function from `main()`
- Adds `pi` to the `tekt_status` check

Note: Pi uses `--ignore-scripts` for security — consider `npm install -g --ignore-scripts @earendil-works/pi-coding-agent` where supported (check if this works for global installs).

#### 3. PowerShell installer (`install.ps1`)

Add Windows install path via `npm install -g @earendil-works/pi-coding-agent`.

#### 4. Documentation (`03-software.md`)

Add Pi to the agent section with:
- Brief description (multi-provider, TypeScript, modular monorepo)
- Configuration notes: `~/.pi/` directory, BYOK for API providers
- Containerization note: Gondolin / plain Docker / OpenShell patterns
- Link to [pi.dev/docs/latest](https://pi.dev/docs/latest)

#### 5. README.md table

Add row to the `Tekt.Iris — Intelligence` table:

| Pi | Interactive coding agent CLI, multi-provider LLM (OpenAI/Anthropic/Google), TypeScript | earendil-works (MIT) |

### Testing checklist

- [ ] `install.sh` installs pi on macOS (Intel + Apple Silicon)
- [ ] `install.sh` installs pi on Ubuntu/Debian
- [ ] `install.sh` installs pi on Fedora/RHEL
- [ ] `install.sh` installs pi on Arch Linux
- [ ] `install.sh` installs pi on WSL2
- [ ] `install.ps1` installs pi on Windows (native PowerShell)
- [ ] `install.sh status` shows pi version correctly
- [ ] `pi --version` runs after install
- [ ] Pi connects to at least one LLM provider (test with Anthropic key from tekt environment)
- [ ] Pi connects to tekt MCPHub at `localhost:3000/mcp` (configure in `.pi/config`)
- [ ] Test Gondolin/Docker containerization pattern documented in tekt docs
- [ ] `pi-test.sh` or `./test.sh` from source repo passes

### Notes

- Pi requires an API key for at least one provider (OpenAI, Anthropic, or Google); document BYOK setup in tekt docs
- The `.pi/` config directory holds settings and session history
- Pi has a `pi update --self` command for self-updating; note compatibility with `--ignore-scripts`
- Do NOT confuse with `nanobot-ai/nanobot` (MCP host) — same kind of naming collision as tekt already documents for Nanobot
- Session sharing: Pi has a `pi-share-hf` tool for publishing sessions to Hugging Face; mention in docs as optional
- For Bun users: Pi publishes a Bun-compiled standalone binary via GitHub releases
