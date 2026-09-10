---
layout: layout.njk
title: Changelog
eyebrow: releases · tekt.md
lead: What changed in each release. Tekt ships in small, usable steps toward one goal. It should be simple to connect your computer to your AI, and to share documents, knowledge and skills with the people you work with.
permalink: /changelog/index.html
---

# Changelog

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
