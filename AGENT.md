# Agent Notes

## Project Overview
`git-jira-shortcuts` is an npm package providing zsh shell shortcuts for Git + Jira workflows.

- **Main source:** `shell/git-extras.sh`
- **CLI entry:** `bin/cli.js`
- **Package registry:** npm (`git-jira-shortcuts`)

## Deployment

Publishing to npm is handled by a **GitHub Action** (`.github/workflows/publish.yml`).

- It triggers on **release published**, NOT on push to main.
- To deploy a new version:
  1. Bump `version` in `package.json`
  2. Commit and push to `main`
  3. Create a GitHub release: `gh release create v<version> --title "v<version>" --notes "<description>" --target main`
- Do **not** run `npm publish` locally — the action handles it with provenance.

## Adding a New Command

1. Add the function to `shell/git-extras.sh` in the **PUBLIC COMMANDS** section
2. Follow the comment convention: `funcname() { # funcname [args] | Description`
3. If it has an alias, add it right after: `alias short='funcname' # funcname [args] | Alias for funcname`
4. Update `ghelp()` help text in the appropriate section
5. Update `README.md` command tables

## When Updating

- Always update **three places**: the function, `ghelp`, and `README.md`
- Branch resolution uses `_gjs_resolve_branch_input` — supports ticket numbers, aliases (`m`→master, `d`→develop), and full branch names
- GitHub repo path is derived from `git remote get-url origin` — no extra ENV needed for GitHub URLs

## Git Rules

- Always ask the user before making git changes (add, commit, push, merge, etc.)
