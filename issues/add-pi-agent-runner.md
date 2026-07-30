# Add pi (earendil-works/pi) to tekt.iris agent layer

**Upstream:** [earendil-works/pi](https://github.com/earendil-works/pi)  
**Layer:** `tekt.iris` (Intelligence — Agents & Models)  
**Runtime:** Node.js / Bun (TypeScript monorepo)  
**License:** MIT  
**Install cmd:** `npm install -g @earendil-works/pi-coding-agent`  
**Platform support:** macOS, Linux, WSL2, Windows  

## Summary

[Pi](https://pi.dev) is the Pi Agent Harness — an interactive coding agent CLI built as a TypeScript/Node.js monorepo with a modular architecture: a unified multi-provider LLM API (`pi-ai`), an agent runtime with tool calling and state management (`pi-agent-core`), and the interactive coding agent CLI (`pi-coding-agent`). Pi supports OpenAI, Anthropic, Google, and other LLM providers, includes a built-in TUI (`pi-tui`), and has a containerization guide for Gondolin/Docker/OpenShell sandboxing.

Pi was previously maintained as `badlogic/pi` (mario@badlogicgames.com) and has strong supply-chain hardening: pinned direct deps, `npm-shrinkwrap.json`, `npm ci --ignore-scripts`, and scheduled audit CI.

## Work to do

### 1. Catalog entry (`tekt.catalog.yaml`)

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

### 2. Installer function (`install.sh`)

Add `install_pi()` function that:
- Checks if `pi` is already installed (`pi --version`)
- Installs via `npm install -g @earendil-works/pi-coding-agent` (Node.js must be present; tekt.dev layer handles this)
- Prints version and first-run hint on success
- Calls the function from `main()`
- Adds `pi` to the `tekt_status` check

Note: Pi uses `--ignore-scripts` for security — consider `npm install -g --ignore-scripts @earendil-works/pi-coding-agent` where supported (check if this works for global installs).

### 3. PowerShell installer (`install.ps1`)

Add Windows install path via `npm install -g @earendil-works/pi-coding-agent`.

### 4. Documentation (`03-software.md`)

Add Pi to the agent section with:
- Brief description (multi-provider, TypeScript, modular monorepo)
- Configuration notes: `~/.pi/` directory, BYOK for API providers
- Containerization note: Gondolin / plain Docker / OpenShell patterns
- Link to [pi.dev/docs/latest](https://pi.dev/docs/latest)

### 5. README.md table

Add row to the `Tekt.Iris — Intelligence` table:

| Pi | Interactive coding agent CLI, multi-provider LLM (OpenAI/Anthropic/Google), TypeScript | earendil-works (MIT) |

## Testing checklist

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

## Notes

- Pi requires an API key for at least one provider (OpenAI, Anthropic, or Google); document BYOK setup in tekt docs
- The `.pi/` config directory holds settings and session history
- Pi has a `pi update --self` command for self-updating; note compatibility with `--ignore-scripts`
- Do NOT confuse with `nanobot-ai/nanobot` (MCP host) — same kind of naming collision as tekt already documents for Nanobot
- Session sharing: Pi has a `pi-share-hf` tool for publishing sessions to Hugging Face; mention in docs as optional
- For Bun users: Pi publishes a Bun-compiled standalone binary via GitHub releases
