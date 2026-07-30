# Issue Plans: New Agent Runners for tekt.iris

This directory contains the plans for adding four new agent runners to tekt.md (#15).

Each file is formatted as a GitHub issue spec, ready to be created as an issue in this repo.

| File | Tool | Layer | Language/Runtime | License |
|------|------|-------|-----------------|---------|
| [add-opencode-agent-runner.md](add-opencode-agent-runner.md) | [opencode](https://github.com/anomalyco/opencode) | tekt.iris | Node.js (npm) | MIT |
| [add-crush-agent-runner.md](add-crush-agent-runner.md) | [crush](https://github.com/charmbracelet/crush) | tekt.iris | Go (single binary) | MIT |
| [add-open-design-agent-runner.md](add-open-design-agent-runner.md) | [open-design](https://github.com/nexu-io/open-design) | tekt.cloud | Desktop app + MCP | Apache 2.0 |
| [add-pi-agent-runner.md](add-pi-agent-runner.md) | [pi](https://github.com/earendil-works/pi) | tekt.iris | Node.js/TypeScript | MIT |

## To create these as GitHub issues

```bash
gh issue create --repo xingh/tekt.md \
  --title "Add opencode to tekt.iris agent layer" \
  --body-file issues/add-opencode-agent-runner.md \
  --label "enhancement"

gh issue create --repo xingh/tekt.md \
  --title "Add crush to tekt.iris agent layer" \
  --body-file issues/add-crush-agent-runner.md \
  --label "enhancement"

gh issue create --repo xingh/tekt.md \
  --title "Add open-design to tekt.iris or tekt.cloud layer" \
  --body-file issues/add-open-design-agent-runner.md \
  --label "enhancement"

gh issue create --repo xingh/tekt.md \
  --title "Add pi (earendil-works/pi) to tekt.iris agent layer" \
  --body-file issues/add-pi-agent-runner.md \
  --label "enhancement"
```
