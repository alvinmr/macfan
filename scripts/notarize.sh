#!/usr/bin/env bash
# Notarizes and staples a signed DMG. Needs a Developer ID–signed build and:
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD (an app-specific password)
#
#   scripts/notarize.sh build/MacFan-v1.2.3-macOS.dmg
set -euo pipefail
DMG="$1"
: "${APPLE_ID:?}" "${APPLE_TEAM_ID:?}" "${APPLE_APP_PASSWORD:?}"

echo "▸ Submitting $(basename "$DMG") for notarization"
xcrun notarytool submit "$DMG" \
  --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" \
  --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
# Stapling changed the file; refresh its checksum.
(cd "$(dirname "$DMG")" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "✓ Notarized and stapled"
