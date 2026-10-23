#!/bin/bash
# Build, sign and install into /Applications.
#
# Signs with a stable self-signed identity rather than ad-hoc. macOS ties
# Accessibility permission to the code signature, and an ad-hoc signature is
# derived from the binary, so it changes on every build and the permission has
# to be granted again each time. A fixed certificate keeps the app's designated
# requirement constant across rebuilds, so the grant sticks.
#
# The identity lives in the login keychain; a backup sits in
# ~/Library/Application Support/CopyPaste/signing.
set -euo pipefail
cd "$(dirname "$0")"
REPO="$(pwd)"

# SHA-1 of the maintainer's "CopyPaste Local Signing" certificate; set
# FIOKA_SIGN_ID to your own. Without one, the app is signed ad-hoc: it builds
# and runs, but Accessibility has to be granted again after every rebuild.
SIGN_ID="${FIOKA_SIGN_ID:-${COPYPASTE_SIGN_ID:-67B262BB8BC8C6383D826076F21DDC9076392CA6}}"
if ! security find-certificate -Z 2>/dev/null | grep -qi "$SIGN_ID"; then
  echo "note: no stable signing identity found, signing ad-hoc."
  echo "      After a rebuild, turn Fioka's Accessibility switch off and on again."
  echo "      The README's Install section shows how to make a stable identity."
  SIGN_ID="-"
fi

CONFIG="${1:-Release}"
APP="build/Build/Products/$CONFIG/Fioka.app"

echo "==> Building $CONFIG"
xcodebuild -project Fioka.xcodeproj -scheme Fioka -configuration "$CONFIG" \
  -derivedDataPath ./build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
  build 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:" || true

[ -d "$APP" ] || { echo "build failed: $APP missing"; exit 1; }

echo "==> Quitting running instance"
pkill -x Fioka 2>/dev/null || true
sleep 1

# Maccy is left alone: Fioka copies its history and settings on first launch
# (LegacyMigration) and never touches the original. That import includes
# Maccy's shortcut, so with both running they fight over the same keys.
if pgrep -xq Maccy; then
  echo "note: Maccy is running. Fioka imports its shortcut, so quit Maccy or"
  echo "      give one of them a different shortcut in Settings."
fi

echo "==> Installing to /Applications"
rm -rf /Applications/Fioka.app
cp -R "$APP" /Applications/

echo "==> Signing with ${SIGN_ID}"
"$REPO/scripts/sign-app.sh" /Applications/Fioka.app "$SIGN_ID"

# Xcode registers build products with LaunchServices, so Spotlight and "open"
# can find the copy under build/ instead of the installed one. That copy is
# ad-hoc signed, so it is a different code identity and does not carry the
# Accessibility grant — it looks like the app simply stopped pasting.
echo "==> Unregistering build-folder copies from LaunchServices"
LSREG=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
for stray in "$REPO/build/Build/Products"/*/Fioka.app "$REPO/build/Build/Products"/*/Maccy.app; do
  [ -d "$stray" ] && "$LSREG" -u "$stray" 2>/dev/null || true
done

echo "==> Launching"
open -a /Applications/Fioka.app
sleep 3
pgrep -lx Fioka && echo "==> RUNNING" || { echo "==> FAILED TO LAUNCH"; exit 1; }
