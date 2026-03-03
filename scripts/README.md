# Maintainer Scripts

These scripts are for package maintainers only and are not published to npm.

## Releasing a New Version

```bash
./scripts/release.sh [patch|minor|major] ["release notes"]
```

### Examples

```bash
./scripts/release.sh patch                    # 1.0.5 → 1.0.6
./scripts/release.sh minor                    # 1.0.5 → 1.1.0  
./scripts/release.sh major                    # 1.0.5 → 2.0.0
./scripts/release.sh patch "Fixed greset UI"  # with custom release notes
```

### What it does

1. Verifies you're on `main` with a clean working directory
2. Pulls latest changes
3. Bumps version in `package.json`
4. Commits and pushes to GitHub
5. Creates a GitHub Release → triggers npm publish automatically

### Requirements

- Must be on `main` branch
- Working directory must be clean (no uncommitted changes)
- [GitHub CLI](https://cli.github.com/) (`gh`) must be installed and authenticated
- Trusted Publishing must be configured on npmjs.com (see below)

### npm Trusted Publishing Setup (one-time)

1. Go to [npmjs.com](https://www.npmjs.com) → `git-jira-shortcuts` → **Settings**
2. Find **Trusted Publisher** section
3. Click **GitHub Actions** and enter:
   - **Organization or user:** `chipallen2`
   - **Repository:** `git-jira-shortcuts`
   - **Workflow filename:** `publish.yml`
