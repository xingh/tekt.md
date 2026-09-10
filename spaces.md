---
layout: layout.njk
title: Spaces
eyebrow: share · docs · knowledge · skills
lead: Share documents, knowledge and skills with your AI and your people, through the storage you already use.
permalink: /spaces/index.html
---

# Spaces

## What a Space is

A **Space** is a folder on your computer that stays in sync with storage you and your people already use: Google Drive, OneDrive, Dropbox, Box, Nextcloud, or a shared folder on a NAS. Nobody needs to learn git or set up S3.

Every Space is laid out the same way, so people and AI tools always know where to look:

| Folder | What goes in it |
| --- | --- |
| `docs/` | Documents you want your AI and your colleagues to read |
| `knowledge/` | Notes, decisions and reference material worth keeping |
| `skills/` | Skills for AI agents: one folder per skill, each with a `SKILL.md` |

Everyone who joins keeps a synced copy at `~/Tekt/Spaces/<name>` on their own computer.

## Make your first Space

```bash
curl -fsSL https://tekt.md/install.sh | bash   # once: installs Tekt and the tekt command
tekt space add team drive                      # sign in to Google Drive in your browser
tekt space autosync on                         # keep it in sync every 10 minutes
```

On Windows, install with `irm https://tekt.md/install.ps1 | iex`, then run the same `tekt space` commands.

Only need the Spaces part? Any computer with [rclone](https://rclone.org/install/) can run `bash install.sh space add team drive` from a copy of the installer.

## Where it can live

| Type this | Storage | What happens |
| --- | --- | --- |
| `drive` | Google Drive | Your browser opens to sign in. The Space lives in the `Tekt/<name>` folder of your Drive. |
| `onedrive` | OneDrive / SharePoint | Your browser opens to sign in, then you pick the drive. |
| `dropbox` | Dropbox | Your browser opens to sign in. |
| `box` | Box | Your browser opens to sign in. |
| `nextcloud` | Nextcloud | You enter the address, your username and an app password. |
| `folder` | A folder or network drive | You give a path, like `/mnt/nas/team` or `~/Dropbox/Team`. |
| `s3` | S3, MinIO, R2, B2 (advanced) | rclone asks for the endpoint and keys. |

Tekt never sees your password. Sign-in tokens stay in rclone's config on your own computer.

## Invite people

1. Share the Space's folder (for example `Tekt/team` in Google Drive) the way you share any folder.
2. They install Tekt, then run the command `tekt space add` printed for them:

```bash
tekt space add team drive "Tekt/team"
```

On Google Drive, a folder someone shared with you shows up under *Shared with me*. Add a shortcut to it in *My Drive* first, then use that path.

Now everyone, and everyone's AI, works from the same files.

## What goes where

- **Documents** (`docs/`): proposals, PDFs, spreadsheets, meeting notes. Anything you'd want an assistant to read before it helps.
- **Knowledge** (`knowledge/`): the things your group has agreed on: decisions, how-tos, glossaries, reference answers. Keep it short and current.
- **Skills** (`skills/`): packaged instructions an AI agent loads for one kind of job. One folder per skill, with a `SKILL.md` inside. Starting with v0.4, Tekt links shared skills straight into Claude Code.

## Give your AI access

Your Space is a normal folder, so any AI tool that can read files can use it: point it at `~/Tekt/Spaces`.

- **MCPHub** (`tekt mcp`) now exposes `/spaces` to every connected client, alongside `/workspace`.
- **Coming in v0.3:** `tekt connect` registers your Spaces with Claude Code, Claude Desktop and Codex in one command.

## Everyday commands

| Command | What it does |
| --- | --- |
| `tekt space add <name> [storage] [folder]` | Make a Space, or join one someone shared with you |
| `tekt space list` | Show your Spaces, when they last synced, and what's in them |
| `tekt space sync [name]` | Sync now: every Space, or just one |
| `tekt space autosync on` / `off` | Sync every 10 minutes in the background |
| `tekt space remove <name>` | Disconnect a Space. Every file stays where it is. |
| `tekt status` | Your tools and your Spaces in one check |

## How it works

- Tekt uses [rclone](https://rclone.org) `bisync` for two-way sync. The first sync merges both sides without deleting anything.
- If the same file changed in two places, the **newest version wins** and the other is kept next to it with a `.conflict` number, so nothing is lost.
- System clutter stays out of the shared folder: `.DS_Store`, `Thumbs.db`, Office lock files (`~$…`) and `*.tmp`.
- Each Space keeps a small `.tekt-space` file with its settings. It stays on your computer and is never uploaded.

## Troubleshooting

- **A Space won't sync.** Run `tekt space sync <name>` to see the message. If it keeps failing, reset it with the `rclone bisync … --resync` command Tekt prints. That merges both sides again.
- **Sign-in didn't open a browser.** This happens on a computer without a desktop. Run `rclone authorize drive` on a computer that has a browser and paste the result back, as rclone explains.
- **Autosync on Windows.** `tekt space autosync on` creates a Scheduled Task named *TektSpacesAutosync*. On macOS and Linux it adds one line to your crontab.
