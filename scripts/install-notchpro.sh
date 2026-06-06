#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$HOME/Library/Developer/Xcode/DerivedData"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo "Stopping NotchPro..."
pkill -x NotchPro 2>/dev/null || true
pkill -x boringNotch 2>/dev/null || true
pkill -f "mediaremote-adapter.pl.*NotchPro.app" 2>/dev/null || true
sleep 0.5

echo "Removing stale Debug/Release builds from DerivedData..."
find "$DERIVED" \( -path '*/NotchPro-*/*' -o -path '*/boringNotch-*/*' \) \( -path '*/Debug/NotchPro.app' -o -path '*/Debug/boringNotch.app' -o -path '*/Release/boringNotch.app' \) -type d -maxdepth 10 2>/dev/null | while read -r stale; do
  echo "  Removing $stale"
  rm -rf "$stale"
done

echo "Building NotchPro (Release)..."
cd "$ROOT"
xcodebuild -project NotchPro.xcodeproj -scheme NotchPro -configuration Release -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" build 2>&1 | tail -5

APP="$(find "$DERIVED" -path '*/Release/NotchPro.app' -type d 2>/dev/null | xargs -I{} stat -f '%m %N' {} 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "Could not find NotchPro.app after build." >&2
  exit 1
fi

echo "Installing from: $APP"
rm -rf /Applications/NotchPro.app
ditto "$APP" /Applications/NotchPro.app
# Local Release builds are ad-hoc; only re-sign when needed so we don't break a valid DMG signature.
if codesign --verify --deep --strict /Applications/NotchPro.app 2>/dev/null; then
  echo "App signature verified — keeping existing signature."
else
  echo "Re-signing ad-hoc for local build..."
  codesign --force --deep --sign - /Applications/NotchPro.app
fi
xattr -cr /Applications/NotchPro.app

# DerivedData .app copies make Spotlight/Launchpad show duplicate icons — remove after install
echo "Removing DerivedData app copy used for install..."
rm -rf "$APP"

if [[ -x "$LSREGISTER" ]]; then
  echo "Unregistering ALL stale NotchPro/boringNotch copies from Launch Services..."
  find "$DERIVED" \( -path '*/NotchPro.app' -o -path '*/boringNotch.app' \) -type d 2>/dev/null | while read -r stale; do
    "$LSREGISTER" -u "$stale" 2>/dev/null || true
  done
  # Release DerivedData copy gets re-registered by xcodebuild — unregister so Spotlight only shows /Applications
  if [[ -n "$APP" && -d "$APP" ]]; then
    "$LSREGISTER" -u "$APP" 2>/dev/null || true
  fi
  find "$ROOT" \( -path '*/NotchPro.app' -o -path '*/boringNotch.app' \) -type d 2>/dev/null | while read -r stale; do
    "$LSREGISTER" -u "$stale" 2>/dev/null || true
  done
  find "$HOME/Desktop" \( -path '*/NotchPro.app' -o -path '*/boringNotch.app' \) -type d 2>/dev/null | while read -r stale; do
    "$LSREGISTER" -u "$stale" 2>/dev/null || true
  done
  "$LSREGISTER" -f /Applications/NotchPro.app
  echo "Restarting Dock to clear duplicate icons..."
  killall Dock 2>/dev/null || true
fi

echo ""
echo "First time opening from a GitHub DMG? If macOS blocks the app:"
echo "  Right-click NotchPro in Applications → Open → confirm Open once."
echo ""
echo "Launching NotchPro..."
open /Applications/NotchPro.app
echo "Done — single NotchPro at /Applications/NotchPro.app"
