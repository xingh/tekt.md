# Add opencode to tekt.iris agent layer

**Upstream:** [anomalyco/opencode](https://github.com/anomalyco/opencode)  
**Layer:** `tekt.iris` (Intelligence — Agents & Models)  
**Runtime:** Node.js (npm)  
**License:** MIT  
**Install cmd:** `npm i -g opencode-ai@latest` or `curl -fsSL https://opencode.ai/install | bash`  
**Platform support:** macOS, Linux, WSL2, Windows (Scoop/Chocolatey/winget), Arch Linux  

## Summary

[opencode](https://opencode.ai) is an open-source AI coding agent — a fully featured terminal-based assistant that supports multiple LLM providers and integrates with MCP servers. It is the open-source counterpart to Claude Code and fits directly in tekt.iris alongside it.

## Work to do

### 1. Catalog entry (`tekt.catalog.yaml`)

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

### 2. Installer function (`install.sh`)

Add `install_opencode()` function that:
- Checks if `opencode` is already installed (`opencode --version`)
- Installs via `npm i -g opencode-ai@latest` (Node.js must be installed; tekt.dev layer handles this)
- Alternatively on macOS: `brew install anomalyco/tap/opencode`
- Prints version and first-run hint on success
- Calls the function from `main()`
- Adds `opencode` to the `tekt_status` check

### 3. PowerShell installer (`install.ps1`)

Add Windows install path via `scoop install opencode` or `npm i -g opencode-ai@latest`.

### 4. Documentation (`03-software.md`)

Add opencode to the agent section with:
- Brief description
- MCP configuration notes (opencode reads from `~/.opencode/config.json`)
- Link to upstream docs at [opencode.ai/docs](https://opencode.ai/docs)

### 5. README.md table

Add row to the `Tekt.Iris — Intelligence` table:

| opencode | Open-source AI coding agent CLI, multi-model, MCP-extensible | anomalyco (MIT) |

## Testing checklist

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

## Notes

- opencode requires Node.js (already guaranteed by the tekt.dev layer)
- Interactive onboarding: run `opencode` after install and complete the setup wizard
- The desktop app (BETA) is available for download at [opencode.ai/download](https://opencode.ai/download) — consider adding a `brew install --cask opencode-desktop` path for macOS
