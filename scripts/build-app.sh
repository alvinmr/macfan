#!/usr/bin/env bash
# Builds build/MacFan.app from the Swift package, with its debug symbols in build/dSYMs.
#
#   scripts/build-app.sh                       # release, this Mac's architecture, ad-hoc signed
#   UNIVERSAL=1 scripts/build-app.sh           # Apple Silicon + Intel (what releases ship)
#   CONFIG=debug scripts/build-app.sh
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" scripts/build-app.sh
#
# Version: MACFAN_VERSION, else version.txt. Build number: MACFAN_BUILD, else 1.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
VERSION="${MACFAN_VERSION:-$(tr -d '[:space:]' < "$ROOT/version.txt")}"
BUILD="${MACFAN_BUILD:-1}"
APP="$ROOT/build/MacFan.app"
HELPER_ID="io.github.alvinmr.MacFan.helper"

cd "$ROOT"

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi
swift_build() { swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} "$@"; }

echo "▸ Building MacFan $VERSION ($BUILD), $CONFIG${UNIVERSAL:+, universal}"
swift_build --product MacFan
swift_build --product macfan-helper
BIN="$(swift_build --show-bin-path)"

echo "▸ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchDaemons" "$APP/Contents/Frameworks"
cp "$BIN/MacFan" "$APP/Contents/MacOS/MacFan"
cp "$BIN/macfan-helper" "$APP/Contents/MacOS/macfan-helper"
# Symbols are over half of each binary. Keep them in dSYMs next to the app (releases
# attach them, for reading crash reports), and ship the binaries without.
DSYMS="$ROOT/build/dSYMs"
rm -rf "$DSYMS"
mkdir -p "$DSYMS"
for binary in MacFan macfan-helper; do
  dsymutil "$APP/Contents/MacOS/$binary" -o "$DSYMS/$binary.dSYM"
  strip -x -S "$APP/Contents/MacOS/$binary"
done
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "Resources/$HELPER_ID.plist" "$APP/Contents/Library/LaunchDaemons/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"

echo "▸ Embedding Sparkle"
SPARKLE_SOURCE="$(find .build/artifacts -type d -name Sparkle.framework -path '*macos-*' | head -n 1)"
[[ -n "$SPARKLE_SOURCE" ]] || { echo "Sparkle.framework not found; run swift build first" >&2; exit 1; }
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
ditto "$SPARKLE_SOURCE" "$SPARKLE"
# MacFan isn't sandboxed, so Sparkle's XPC services aren't needed.
rm -rf "$SPARKLE/Versions/B/XPCServices" "$SPARKLE/XPCServices"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/MacFan" 2>/dev/null || true

echo "▸ Signing with identity: $SIGN_IDENTITY"
# Hardened runtime is required for notarization, but with an ad-hoc signature its
# library validation would refuse to load Sparkle. So: Developer ID builds only.
SIGN_FLAGS=(--force --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  SIGN_FLAGS+=(--options runtime --timestamp)
fi
# Inside-out: nested code first, the bundle last.
codesign "${SIGN_FLAGS[@]}" "$SPARKLE/Versions/B/Autoupdate"
codesign "${SIGN_FLAGS[@]}" "$SPARKLE/Versions/B/Updater.app"
codesign "${SIGN_FLAGS[@]}" "$SPARKLE"
codesign "${SIGN_FLAGS[@]}" --identifier "$HELPER_ID" "$APP/Contents/MacOS/macfan-helper"
codesign "${SIGN_FLAGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"

echo "✓ $APP"
