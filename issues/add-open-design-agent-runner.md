# Add open-design to tekt.iris or tekt.cloud layer

**Upstream:** [nexu-io/open-design](https://github.com/nexu-io/open-design)  
**Layer:** `tekt.cloud` (or `tekt.iris`) — design tool / agent-native studio  
**Runtime:** Desktop app (macOS, Windows) + CLI skills via agent integration  
**License:** Apache 2.0  
**Install:** Download from [open-design.ai/download](https://open-design.ai/) or via release page  
**Platform support:** macOS, Windows (native desktop app); agent CLI skills work wherever the agent runs  

## Summary

[Open Design](https://open-design.ai) is the open-source alternative to Claude Design and Figma for the agent era. Rather than a canvas-based design tool, it delivers single-page HTML/CSS artifacts, live dashboards, decks, images, video (HyperFrames/MP4), and more — all driven by a `DESIGN.md` design system and rendered through coding agents already on your machine (Claude Code, OpenClaw, OpenCode, Cursor, Codex, Hermes, and 25+ others). It exposes an MCP server for integration and runs skills as a filesystem of composable design templates.

Relevant to tekt.md because:
- It integrates directly with the existing tekt.iris agents (Claude Code, OpenClaw, Hermes, opencode)
- It exposes an MCP server that can plug into the tekt MCPHub
- It is a local-first, self-hosted, agent-native design studio aligned with tekt's sovereignty goals

## Work to do

### 1. Determine layer placement

Open Design is a desktop application with agent integrations, not a pure CLI agent runner. Recommended placement: `tekt.cloud` (alongside LibreChat, n8n, Sovrant as a UI tool) OR add a new `tekt.design` subsection within `tekt.iris`. **Discuss with maintainer before implementing.**

### 2. Catalog entry (`tekt.catalog.yaml`)

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

### 3. Installer notes (`install.sh` / `install.ps1`)

Open Design is a desktop GUI app — auto-install is not straightforward for a headless bootstrap script. Recommended approach:
- Print a notice/hint in the `tekt_status` output: "Open Design: not installed — download from https://open-design.ai/download"
- Optionally add a `brew install --cask` path if an official Homebrew cask is published (check upstream)
- On Windows: check for a winget package ID when available

### 4. MCP integration

Open Design exposes an MCP server. Document how to add it to the MCPHub `mcp_settings.json`:
- Identify the MCP server package name / endpoint from the upstream docs
- Add a sample entry to the `mcp_servers` section in `tekt.catalog.yaml`

### 5. Documentation (`04-interface.md`)

Add Open Design to the interface doc with:
- Brief description (agent-native design studio, Figma/Claude Design alternative)
- Installation instructions for macOS and Windows
- How to connect to existing tekt.iris agents via `DESIGN.md`
- How to wire the Open Design MCP server into MCPHub

### 6. README.md table

Add row to the `Tekt.Cloud — Chat, Workflows & Command Center` table (or create a new `Tekt.Design` section):

| Open Design | Agent-native design studio; prototypes, decks, images, video via DESIGN.md | nexu-io (Apache-2.0) |

## Testing checklist

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

## Notes

- Open Design Cloud (paid hosted model service) is optional; it also works with local models via BYOK/Ollama
- The `.claude-plugin` directory in the repo suggests it integrates with Claude Code as a plugin — investigate for tekt-specific wiring
- Governance note: Apache 2.0 license; explicitly compatible with tekt's distribution goals
