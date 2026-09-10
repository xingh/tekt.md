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
tekt connect                                   # let Claude Code, Claude Desktop and Codex use it
tekt space invite team                         # write an invitation for your people
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

1. Share the Space's folder (for example `Tekt/team` in Google Drive) with them, the way you share any folder.
2. Let Tekt write the invitation:

```bash
tekt space invite team
```

It prints a short message and copies it to your clipboard, ready to paste into an email or chat:

```
Join our "team" Space on Tekt: shared documents, knowledge and AI skills.

1. I've shared the folder "team" with you on Google Drive. Open "Shared with me",
   right-click it, choose Organize > Add shortcut, and pick My Drive.
2. Install Tekt (once):
   macOS / Linux:  curl -fsSL https://tekt.md/install.sh | bash
   Windows:        irm https://tekt.md/install.ps1 | iex
3. Join:                tekt space add team drive "team"
4. Let your AI use it:  tekt connect
```

The steps match where the Space lives. Google Drive and OneDrive need a shortcut to the shared folder; Dropbox, Box and Nextcloud need the invitation accepted; a network folder needs its path. A folder someone shares with you lands at the top of your storage under its own name, so the join command uses `"team"`, not `"Tekt/team"`.

Now everyone, and everyone's AI, works from the same files.

## What goes where

- **Documents** (`docs/`): proposals, PDFs, spreadsheets, meeting notes. Anything you'd want an assistant to read before it helps.
- **Knowledge** (`knowledge/`): the things your group has agreed on: decisions, how-tos, glossaries, reference answers. Keep it short and current.
- **Skills** (`skills/`): packaged instructions an AI agent loads for one kind of job. One folder per skill, with a `SKILL.md` inside. Tekt links shared skills straight into Claude Code (see below).

## Give your AI access

One command lets the AI apps on your computer read and write your Spaces:

```bash
tekt connect                   # every supported app it finds
tekt connect claude-desktop    # or just one: claude-code, claude-desktop, codex
```

| App | What Tekt does |
| --- | --- |
| **Claude Code** | Registers the MCP server `tekt-spaces` for your user account |
| **Claude Desktop** | Adds `tekt-spaces` to `claude_desktop_config.json` and saves a `.bak-tekt` copy of the original first. Restart the app afterwards. |
| **Codex** | Adds `[mcp_servers.tekt-spaces]` to `~/.codex/config.toml`, with a `.bak-tekt` copy first |
| **Anything else that speaks MCP** | Run `npx -y @modelcontextprotocol/server-filesystem ~/Tekt/Spaces`, or use MCPHub (`tekt mcp`) at `http://localhost:3000/mcp`, which serves `/spaces` too |

Running it again changes nothing, and Tekt only touches its own `tekt-spaces` entry. Then ask your AI: *"What's in my team Space?"* or *"Summarize the new files in team/docs."*

## Share skills

A skill is a folder with a `SKILL.md`: a short set of instructions an AI loads for one kind of job, like "summarize meeting notes our way" or "draft a proposal from our template". You share skills the way you share documents:

```bash
tekt skill new team summarize    # starts team/skills/summarize/SKILL.md from a template
# edit the SKILL.md, then:
tekt space sync team             # everyone in the Space gets it on their next sync
tekt skill list                  # every shared skill, and which ones are in your Claude Code
```

After each sync, Tekt links every skill in your Spaces into Claude Code as `~/.claude/skills/<space>--<skill>`. When someone deletes a skill, it disappears from everyone's Claude Code, and when you disconnect a Space, its skills go too. Tekt only manages its own links. Your personal skills and any folder that isn't Tekt's are never touched.

Skills from people outside your group work the same way. Put them in a Space's `skills/` folder, for example the curated arkitype skills listed on the [catalog](/catalog/#skill).

## Everyday commands

| Command | What it does |
| --- | --- |
| `tekt space add <name> [storage] [folder]` | Make a Space, or join one someone shared with you |
| `tekt space list` | Show your Spaces, when they last synced, and what's in them |
| `tekt space sync [name]` | Sync now: every Space, or just one |
| `tekt space autosync on` / `off` | Sync every 10 minutes in the background |
| `tekt space invite <name>` | Write an invitation to a Space and copy it to your clipboard |
| `tekt space open <name>` | Open a Space's folder |
| `tekt space remove <name>` | Disconnect a Space. Every file stays where it is. |
| `tekt connect [app]` | Let Claude Code, Claude Desktop and Codex use your Spaces |
| `tekt skill new <space> <name>` | Start a shared skill from a template |
| `tekt skill list` | Every shared skill, and which are in your Claude Code |
| `tekt skill link` | Re-link shared skills into Claude Code (repair) |
| `tekt status` | Your tools, your Spaces, and which AI apps are connected, in one check |

## How it works

- Tekt uses [rclone](https://rclone.org) `bisync` for two-way sync. The first sync merges both sides without deleting anything.
- If the same file changed in two places, the **newest version wins** and the other is kept next to it with a `.conflict` number, so nothing is lost.
- System clutter stays out of the shared folder: `.DS_Store`, `Thumbs.db`, Office lock files (`~$…`) and `*.tmp`.
- Each Space keeps a small `.tekt-space` file with its settings. It stays on your computer and is never uploaded.

## Troubleshooting

- **A Space won't sync.** Run `tekt space sync <name>` to see the message. If it keeps failing, reset it with the `rclone bisync … --resync` command Tekt prints. That merges both sides again.
- **Sign-in didn't open a browser.** This happens on a computer without a desktop. Run `rclone authorize drive` on a computer that has a browser and paste the result back, as rclone explains.
- **Autosync on Windows.** `tekt space autosync on` creates a Scheduled Task named *TektSpacesAutosync*. On macOS and Linux it adds one line to your crontab.
