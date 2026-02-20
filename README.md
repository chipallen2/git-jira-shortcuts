# git-jira-shortcuts

Stop typing long git commands. Stop copy-pasting branch names. Stop forgetting to prefix your commits with the Jira ticket number.

## Why use this?

**Type a ticket number, get a branch.** Run `gt 1234` and it hits your Jira API, grabs the story title, and creates a properly named branch like `PROJ-1234-fix-login-redirect`. No more looking up titles or manually slugifying them.

**Never type a branch name again.** Run `gw` with no arguments and pick from your recent branches with arrow keys. Same for deleting (`gdel`) and merging (`gm`).

**Commits auto-prefix themselves.** On branch `PROJ-1234-fix-login`? Just type `gf "fixed the redirect"` — it stages everything, commits as `PROJ-1234: fixed the redirect`, and pushes. One command.

**Merging is safe and easy.** Stay on your feature branch, run `gm develop`, and it pulls the latest develop, checks for conflicts, and merges it into your branch. No switching back and forth.

**Everything has guardrails.** Delete won't nuke master. Merge checks for conflicts before touching anything. Reset asks for confirmation. Switch warns you about uncommitted work.

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
| `GJS_TICKET_PREFIX` | Yes | Jira project key (e.g. `MYPROJ`, `ACME`) |
| `GJS_JIRA_DOMAIN` | Yes | Jira domain (e.g. `yourco.atlassian.net`) |
| `GJS_JIRA_API_TOKEN` | Yes | Base64-encoded Jira API token |
| `GJS_BRANCH_WEBHOOK_URL` | No | Optional webhook for branch name generation |

### Generating your Jira API token

1. Go to [Atlassian Security Settings](https://id.atlassian.com/manage-profile/security)
2. Click **"Create and manage API tokens"**
3. Click **"Create API token"**, give it a name
4. Set **Expires On** to next year (tokens last 1 year max)
5. Copy the token, then Base64-encode it with your email:
   ```bash
   echo -n "your-email@company.com:your-api-token" | base64
   ```
6. Paste the result during `git-jira-shortcuts init`

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
