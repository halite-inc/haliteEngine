#!/bin/zsh
set -euo pipefail

# ==============================================================================
# Halite Automated Release Script
# Builds Halite.app, generates Halite.dmg & Halite-macos.zip, tags git,
# and publishes the official GitHub Release with assets attached.
#
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
  CHANGELOG="### Improvements & Fixes in ${TAG}
- General performance and stability updates."
fi

echo "🚀 Preparing release ${TAG}..."

# 1. Stage and commit any unstaged changes
echo "📦 Staging and committing changes..."
git add .
if ! git diff --cached --quiet; then
  git commit -m "Release ${TAG}: ${CHANGELOG}"
fi

# 2. Build Release binary with Xcode
echo "🔨 Building Release application binary with xcodebuild..."
xcodebuild -project appleint.xcodeproj -scheme appleint -configuration Release -destination "platform=macOS" -derivedDataPath build/DerivedData -skipPackagePluginValidation -skipMacroValidation clean build -quiet

# 3. Create DMG and ZIP distribution packages
echo "📦 Packaging Halite.dmg and Halite-macos.zip..."
rm -rf build/dmg_staging Halite.dmg Halite-macos.zip
mkdir -p build/dmg_staging

APP_PATH="build/DerivedData/Build/Products/Release/Halite.app"
if [ ! -d "$APP_PATH" ]; then
  APP_PATH="build/DerivedData/Build/Products/Release/appleint.app"
fi

cp -R "$APP_PATH" build/dmg_staging/Halite.app
ln -s /Applications build/dmg_staging/Applications
hdiutil create -volname "Halite" -srcfolder build/dmg_staging -ov -format UDZO Halite.dmg -quiet

ROOT_DIR="$(pwd)"
(cd "$(dirname "$APP_PATH")" && zip -r -y -q "${ROOT_DIR}/Halite-macos.zip" "$(basename "$APP_PATH")")

# 4. Create and push git tag
echo "🏷️ Creating and pushing git tag ${TAG}..."
if git rev-parse "$TAG" >/dev/null 2>&1; then
  git tag -d "$TAG" 2>/dev/null || true
fi
git tag -a "$TAG" -m "$(echo -e "$CHANGELOG")"
git push origin main
git push origin "$TAG" --force

# 5. Create or update GitHub Release with DMG & ZIP attached
echo "🌐 Publishing GitHub Release ${TAG} with Halite.dmg attached..."
if command -v gh >/dev/null 2>&1; then
  if gh release view "$TAG" >/dev/null 2>&1; then
    gh release upload "$TAG" Halite.dmg Halite-macos.zip --clobber
    gh release edit "$TAG" --title "Halite ${TAG}" --notes "$(echo -e "$CHANGELOG")"
  else
    gh release create "$TAG" Halite.dmg Halite-macos.zip \
      --title "Halite ${TAG}" \
      --notes "$(echo -e "$CHANGELOG")"
  fi
fi

echo "✅ Successfully published ${TAG} to GitHub with Halite.dmg!"
echo "🔗 View releases at: https://github.com/halite-inc/haliteEngine/releases"
