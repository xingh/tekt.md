# Add crush to tekt.iris agent layer

**Upstream:** [charmbracelet/crush](https://github.com/charmbracelet/crush)  
**Layer:** `tekt.iris` (Intelligence — Agents & Models)  
**Runtime:** Go (single binary)  
**License:** MIT  
**Install cmd:** `brew install charmbracelet/tap/crush` or `npm install -g @charmland/crush`  
**Platform support:** macOS, Linux, Windows (PowerShell, WSL), Android, FreeBSD, OpenBSD, NetBSD  

## Summary

[Crush](https://github.com/charmbracelet/crush) is a terminal-based AI coding agent built by the [Charmbracelet](https://charm.sh) team — the authors behind widely used Go TUI libraries such as Bubble Tea, Lip Gloss, and Glamour. Crush is multi-model (OpenAI, Anthropic, and any OpenAI- or Anthropic-compatible API), session-based, LSP-enhanced, and MCP-extensible via `http`, `stdio`, and `sse`. It is distributed as a single Go binary with first-class cross-platform support and is ideal as a complement to the existing Go-based tools in tekt.

## Work to do

### 1. Catalog entry (`tekt.catalog.yaml`)

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

### 2. Installer function (`install.sh`)

Add `install_crush()` function that:
- Checks if `crush` is already installed (`crush --version`)
- Installs via `brew install charmbracelet/tap/crush` (preferred on macOS/Linux where Homebrew is present)
- Falls back to `npm install -g @charmland/crush` if Homebrew is not available
- Alternatively: download binary from GitHub Releases for platforms without Homebrew or npm
- Prints version and first-run hint on success
- Calls the function from `main()`
- Adds `crush` to `tekt_status` check

### 3. PowerShell installer (`install.ps1`)

Add Windows install path:
- `winget install charmbracelet.crush`
- Or: `scoop install charm; scoop install crush` (via Scoop charm bucket)

### 4. Documentation (`03-software.md`)

Add crush to the agent section with:
- Brief description mentioning Charmbracelet ecosystem
- How to connect to MCPHub: add `tekt.cloud` MCPHub entry to `~/.config/crush/crush.json`
- Link to upstream docs and the `crush.json` schema at [schema.json](https://github.com/charmbracelet/crush/blob/main/schema.json)

### 5. README.md table

Add row to the `Tekt.Iris — Intelligence` table:

| Crush | Multi-model terminal coding agent, LSP-enhanced, MCP-extensible | Charmbracelet (MIT) |

## Testing checklist

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

## Notes

- Crush config is a single JSON file; the schema is published at `crush.json` / `schema.json` in the repo
- The `@charmland/crush` npm package is an alternative install path that doesn't require Go
- Charmbracelet maintains a Homebrew tap (`charmbracelet/tap`) and an apt/yum repo at `repo.charm.sh`
- Built on the Charm ecosystem — compatible with Bubbletea TUI tooling already present in the Go ecosystem
