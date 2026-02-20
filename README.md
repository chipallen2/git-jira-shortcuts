# git-jira-shortcuts

Git + Jira workflow shortcuts for zsh — interactive branch switching, auto-prefixed commits, Jira integration, and more.

## Install

```bash
npm install -g git-jira-shortcuts
git-jira-shortcuts init
source ~/.zshrc
```

The `init` command will walk you through configuration and add the necessary source lines to your `~/.zshrc`.

## Configuration

Running `git-jira-shortcuts init` creates `~/.git-jira-shortcuts.env` with:

| Variable | Required | Description |
|----------|----------|-------------|
| `GJS_TICKET_PREFIX` | Yes | Jira project key (e.g. `MOTOMATE`, `PROJ`) |
| `GJS_JIRA_DOMAIN` | Yes | Jira domain (e.g. `yourco.atlassian.net`) |
| `GJS_JIRA_API_TOKEN` | Yes | Base64-encoded Jira API token |
| `GJS_BRANCH_WEBHOOK_URL` | No | Optional webhook for branch name generation |

### Generating your Jira API token

1. Go to [Atlassian API tokens](https://id.atlassian.com/manage-profile/security/api-tokens)
2. Create a new token
3. Base64-encode it:
   ```bash
   echo -n "your-email@company.com:your-api-token" | base64
   ```
4. Paste the result during `git-jira-shortcuts init`

## Commands

### Status & Info
| Command | Alias | Description |
|---------|-------|-------------|
| `gs` | `gstatus` | Clean git status with remote sync info |
| `glist` | `gl` | List files pending in this branch |
| `grecent` | — | Show recently checked out branches (last 10) |
| `grepos` | `repos` | Show all repo clones and their current branch |
| `ghelp` | — | Show all available commands |

### Branching
| Command | Alias | Description |
|---------|-------|-------------|
| `gswitch [branch]` | `gw` | Switch branches with interactive picker (↑/↓ arrows) |
| `gstart <branch\|ticket#>` | `gt`, `gcreate` | Create or switch to branch, auto-names from Jira |
| `gdelete [branch]` | `gdel` | Delete feature branch if clean and pushed |
| `gmerge [branch]` | `gm` | Merge branch into current if no conflicts |

### Committing & Pushing
| Command | Alias | Description |
|---------|-------|-------------|
| `gcfast <message>` | `gf` | Stage all, commit (skip hooks), push. Auto-prefixes ticket ID. |
| `gcommit <message>` | `gc` | Stage all, commit (with hooks), push. Auto-prefixes ticket ID. |
| `gpush [branch]` | `gpu` | Push with upstream tracking |
| `gp` | — | Pull without rebase or editor |

### Utilities
| Command | Alias | Description |
|---------|-------|-------------|
| `greset [file]` | `gr` | Reset a file with confirmation (interactive if no file given) |
| `gdiff [branch]` | — | List files changed vs target branch + GitHub compare link |
| `testJira` | `tj` | Test Jira API connection |

## Features

### Interactive branch picker
When you run `gswitch`, `gdelete`, or `gmerge` without a branch name, you get an arrow-key menu of your recent branches:

```
Switch to branch (↑/↓ select, Enter confirm, q cancel):
  ● feature-branch-1
  ○ feature-branch-2
  ○ develop
```

### Ticket number shortcuts
Type a ticket number instead of a full branch name:
```bash
gw 1234          # Switches to PROJ-1234-* branch
gstart 1234      # Creates PROJ-1234-<jira-title> branch
```

### Auto-prefixed commits
When on a ticket branch, commit messages are auto-prefixed:
```bash
gc fix the bug   # Commits as "PROJ-1234: fix the bug"
```

### Branch shorthand
- `m` → `master`
- `d` → `develop`

## Update

```bash
npm update -g git-jira-shortcuts
```

## Reconfigure

```bash
git-jira-shortcuts init
source ~/.zshrc
```

## CLI

```bash
git-jira-shortcuts init       # Interactive setup wizard
git-jira-shortcuts path       # Print path to shell script
git-jira-shortcuts --version  # Print version
git-jira-shortcuts --help     # Show help
```

## Requirements

- zsh
- Node.js >= 16
- `jq` (for Jira JSON parsing)
- `curl` (for Jira API calls)

## License

MIT
