#!/usr/bin/env bash
# Packages build/MacFan.app into build/MacFan-v<version>-macOS.dmg and writes its SHA-256.
# Run scripts/build-app.sh first.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/MacFan.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]] || { echo "Invalid app version: $VERSION" >&2; exit 1; }
codesign --verify --deep --strict "$APP"

DMG="$ROOT/build/MacFan-v${VERSION}-macOS.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

ditto "$APP" "$STAGING/MacFan.app"
ln -s /Applications "$STAGING/Applications"
# The mounted volume shows MacFan's icon instead of a generic disk.
cp "$ROOT/Resources/AppIcon.icns" "$STAGING/.VolumeIcon.icns"
SetFile -a C "$STAGING" 2>/dev/null || true

rm -f "$DMG"
hdiutil create -volname MacFan -srcfolder "$STAGING" -format UDZO -fs HFS+ -ov "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null

if [[ -n "${SIGN_IDENTITY:-}" && "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi

(cd "$ROOT/build" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "✓ $DMG"
cat "$DMG.sha256"
