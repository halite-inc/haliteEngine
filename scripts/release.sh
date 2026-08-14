#!/bin/zsh
set -euo pipefail

# ==============================================================================
# AppleInt Release Script
# Usage:
#   ./scripts/release.sh <version> "<improvements_and_fixes>"
# Example:
#   ./scripts/release.sh 1.0.1 "• Added MCP Server support\n• Added Check for Updates\n• Web search performance improvements"
# ==============================================================================

VERSION="${1:-}"
CHANGELOG="${2:-}"

if [ -z "$VERSION" ]; then
  echo "❌ Error: Version argument missing."
  echo "Usage: ./scripts/release.sh <version> [\"<improvements and fixes>\"]"
  echo "Example: ./scripts/release.sh 1.0.1 \"• Added MCP server integration\n• Added in-app update checker\""
  exit 1
fi

# Ensure version format
VERSION="${VERSION#v}"
TAG="v${VERSION}"

if [ -z "$CHANGELOG" ]; then
  CHANGELOG="### Improvements & Fixes in ${TAG}\n- General performance and stability updates."
fi

echo "🚀 Preparing release ${TAG}..."

# 1. Update CFBundleShortVersionString in project or Xcode configuration if desired
echo "📦 Staging and committing changes..."
git add .
if ! git diff --cached --quiet; then
  git commit -m "Release ${TAG}: ${CHANGELOG}"
fi

# 2. Create git tag with release notes
echo "🏷️ Creating git tag ${TAG}..."
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "⚠️ Tag $TAG already exists locally. Deleting and recreating..."
  git tag -d "$TAG"
fi

git tag -a "$TAG" -m "$(echo -e "$CHANGELOG")"

# 3. Push commit and tag to GitHub
echo "⬆️ Pushing commits and tag to origin main..."
git push origin main
git push origin "$TAG" --force

echo "✅ Successfully pushed ${TAG} to GitHub!"
echo "✨ GitHub Actions will now automatically build the macOS app and publish the release with your improvements & fixes."
echo "🔗 View releases at: https://github.com/halite-inc/haliteEngine/releases"
