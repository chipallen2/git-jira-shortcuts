#!/usr/bin/env bash
# Maintainer release script — bumps version, commits, pushes, creates GitHub release
# Usage: ./scripts/release.sh [patch|minor|major] [release notes]

set -e

BUMP_TYPE="${1:-patch}"
NOTES="${2:-Release $BUMP_TYPE update}"

if [[ ! "$BUMP_TYPE" =~ ^(patch|minor|major)$ ]]; then
  echo "Usage: ./scripts/release.sh [patch|minor|major] [release notes]"
  exit 1
fi

# Ensure we're on main and up to date
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$BRANCH" != "main" ]]; then
  echo "❌ Must be on main branch (currently on $BRANCH)"
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "❌ Working directory not clean. Commit or stash changes first."
  exit 1
fi

echo "⬇️  Pulling latest..."
git pull

# Bump version
OLD_VERSION=$(node -p "require('./package.json').version")
npm version "$BUMP_TYPE" --no-git-tag-version
NEW_VERSION=$(node -p "require('./package.json').version")

echo "📦 Version: $OLD_VERSION → $NEW_VERSION"

# Commit and push
git add package.json
git commit -m "Release v$NEW_VERSION"
git push origin main

# Create GitHub release (triggers npm publish via GitHub Actions)
echo "🚀 Creating GitHub release v$NEW_VERSION..."
gh release create "v$NEW_VERSION" --title "v$NEW_VERSION" --notes "$NOTES"

echo "✅ Done! GitHub Actions will publish to npm automatically."
