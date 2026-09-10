---
layout: layout.njk
title: Changelog
eyebrow: releases · tekt.md
lead: What changed in each release. Tekt ships in small, usable steps toward one goal. It should be simple to connect your computer to your AI, and to share documents, knowledge and skills with the people you work with.
permalink: /changelog/index.html
---

# Changelog

## v0.9.0 — Skill shelf

Getting a good skill is one command, and it lands where your colleagues get it too (#46).

- **`tekt skill shelf`** lists the hand-curated skills in the Tekt catalog, and marks the ones you already have.
- **`tekt skill add <skill> [space]`** downloads a curated skill into a Space and links it into your Claude Code. The next sync shares it with everyone in the Space. With no Space yet, it installs the skill just for you.
- **The first skills on the shelf** come from the arkitype plugin: `rfp-proposal-responder`, `domain-to-diligence` and `opportunity-finder`. The catalog marks them `available`, and it always reads the latest shelf from tekt.md.

## v0.8.0 — More AI apps

Bring your own intelligence, in the app you like (#64).

- **Installed for you:**
  - the **Codex CLI** (OpenAI; closes #29)
  - **opencode**, an open-source agent for any provider (closes #36)
  - **crush**, Charm's terminal assistant (closes #37)

  They're installed on macOS, Linux and Windows, and each appears in `tekt status` and the catalog.
- **`tekt connect` reaches them too.**
  - **opencode:** `tekt-spaces` goes under `"mcp"` in `opencode.json`. A file with comments is left untouched, and you get the lines to paste.
  - **crush:** one marked `mcp add` block goes in your `crushrc`, replaced in place on later runs.
  - Checked with a real crush: the server starts with exactly the right arguments, even for paths with spaces.
- **`tekt status`** shows opencode and crush under "AI apps connected to your Spaces".

## v0.7.0 — See your Spaces

For people who never open a terminal (#31).

- **`tekt space gui`** installs [RcloneView](https://rcloneview.com) and opens it: a point-and-click window for browsing your cloud storage and copying files to and from your computer. macOS installs it from the Homebrew cask. Windows uses the official installer, because winget's package is years out of date. Linux gets a no-sudo AppImage and a FUSE 2 hint if needed.
- **Desktops only.** The full install adds RcloneView where there's a desktop and skips it on servers.
- **Honest labeling.** RcloneView is freemium and proprietary (Bdrive Inc.), and the catalog says so. Versions are pinned in `tekt.catalog.yaml`.

## v0.6.0 — Invite

Bringing people in shouldn't take a how-to (#61).

- **`tekt space invite <name>`** writes a ready-to-send invitation and copies it to your clipboard: how to accept the shared folder on your storage, how to install Tekt, the exact join command, and how to connect their AI.
- **The right join command.** A folder shared with you lands at the top of your Drive, OneDrive or Dropbox under its own name, so invitations use `"team"`, not the owner's `"Tekt/team"`. Folder Spaces use the real network path.
- **`tekt space open <name>`** opens a Space's folder in your file manager.
- **Clear warning for very long paths** (#58). If a Space's paths are long enough that rclone may not manage to sync them, Tekt says so before syncing and suggests a shorter `TEKT_SPACES`.

## v0.5.0 — Solid ground

Installs you can trust, on every OS.

- **Windows reports honestly** (#28). Before installing anything, Tekt checks that winget's package sources work, and fixes them when it can (`winget source reset`). When it can't, it tells you the exact commands to run as Administrator. An install only shows `[OK]` if winget succeeded and the command is really on your PATH. A summary lists anything that failed by name.
- **GitHub CLI everywhere** (#26). `gh` is installed on macOS, Ubuntu/Debian, Fedora/RHEL, Arch and Windows, and it appears in `tekt status` and in the catalog.

## v0.4.0 — Shared skills

Share skills with colleagues the way you share documents (#55).

- **Skills in a Space appear in everyone's Claude Code.** After each sync, Tekt links `~/Tekt/Spaces/<space>/skills/<skill>/` into `~/.claude/skills/<space>--<skill>`. It uses a symlink on macOS and Linux and a directory junction on Windows, which needs no admin rights.
- **Only Tekt's own links.** Links whose skill was deleted, or whose Space was disconnected, are removed. Your personal skills and any other folder are never touched, and a name clash is skipped with a warning.
- **`tekt skill new <space> <name>`** starts a `SKILL.md` from a template. **`tekt skill list`** shows every shared skill and whether it's in Claude Code. **`tekt skill link`** repairs the links.
- **`tekt connect`** also links shared skills, and **`tekt status`** counts them.

## v0.3.0 — Connect

Connect your computer to your AI in one step (#54).

- **`tekt connect [app]`** lets the AI apps on your computer read and write your Spaces. It registers the MCP filesystem server `tekt-spaces`, scoped to `~/Tekt/Spaces`, with **Claude Code** (user scope), **Claude Desktop** (`claude_desktop_config.json`) and **Codex** (`~/.codex/config.toml`). With no app named, it connects every one it finds.
- **Safe to re-run.** Tekt replaces only its own entry and keeps every other server and setting. It saves a `.bak-tekt` copy of each config before editing, and leaves invalid JSON untouched.
- **`tekt status`** shows which AI apps are connected to your Spaces.
- **Windows.** The same `connect` command in `install.ps1`. It launches the server through `cmd /c npx`, which native Windows needs.
- **Fix: joining a Space works on the first try** (#57). Tekt no longer writes its own README when the shared folder already has one. On rclone ≥ 1.66, the first sync keeps the newer copy of any file that differs, instead of stopping with "out of sync".

## v0.2.0 — Spaces

Share documents, knowledge and skills with your AI and your people, through the storage you already use (#53).

- **`tekt space add <name> [storage]`** creates a Space: a folder at `~/Tekt/Spaces/<name>` that syncs two ways with Google Drive, OneDrive, Dropbox, Box, Nextcloud, a NAS folder or S3. Sign-in happens in your browser. Every Space has `docs/`, `knowledge/` and `skills/`.
- **`tekt space list | sync | remove | autosync on|off`** lets you see your Spaces, sync now or every 10 minutes (cron on macOS and Linux, a Scheduled Task on Windows), and disconnect without deleting anything.
- **The `tekt` command.** The installer now puts `tekt` on your PATH. Typing `tekt` by itself shows help; `tekt install` installs everything.
- **AI access.** New MCPHub setups expose `/spaces` to every connected client.
- **`tekt status`** lists your Spaces and when each last synced.
- **Windows.** `install.ps1` has the same `space` and `cli` commands, and it reads and writes the same Space format as `install.sh`. It's now plain ASCII, so Windows PowerShell 5.1 can no longer misread its em dashes as quote characters.
- **Docs.** A plain-language [Spaces guide](/spaces/), a "Share with your people" section on the home page, and this changelog.

## v0.1.0 — Blueprint

The first tagged release: a new face, a clear message, and a catalog you can browse.

- A site redesign in the arkitype blueprint style, with layer-coded navigation, light and dark themes, and Mermaid diagrams that render (#45; closes #33, #34).
- The rebrand, "the utility belt for your AI harness", with bring-your-own intelligence: Ollama, OpenRouter, OpenAI, Anthropic (#45).
- A catalog-first site: `tekt.catalog.yaml` drives the home shelves and the [catalog](/catalog/) page (#45).
- A new cover, "One workspace. Many clients.", and the roadmap artwork (#51, #52; closes #48, #49, #50).
