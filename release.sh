#!/bin/bash
# Build a downloadable Fioka-<version>.dmg in build/release.
#
# Universal (Apple silicon and Intel). Signed with the same stable identity as
# install.sh when it is in the keychain, so a downloaded update keeps its
# Accessibility grant; ad-hoc otherwise. Not notarized: that needs a paid
# Apple Developer account, so on first launch macOS asks the user to allow it
# in System Settings → Privacy & Security (see the README).
set -euo pipefail
cd "$(dirname "$0")"
REPO="$(pwd)"

SIGN_ID="${FIOKA_SIGN_ID:-${COPYPASTE_SIGN_ID:-67B262BB8BC8C6383D826076F21DDC9076392CA6}}"
if ! security find-certificate -Z 2>/dev/null | grep -qi "$SIGN_ID"; then
  echo "note: no stable signing identity found, signing ad-hoc."
  SIGN_ID="-"
fi

DERIVED="build/release-derived"
OUT="build/release"
STAGE="$OUT/stage"

echo "==> Building Release (universal)"
rm -rf "$DERIVED"
xcodebuild -project Fioka.xcodeproj -scheme Fioka -configuration Release \
  -derivedDataPath "$DERIVED" \
  ONLY_ACTIVE_ARCH=NO ARCHS="arm64 x86_64" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
  build 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:" || true

APP="$DERIVED/Build/Products/Release/Fioka.app"
[ -d "$APP" ] || { echo "build failed: $APP missing"; exit 1; }

# Xcode registered the product with LaunchServices; an ad-hoc copy found by
# Spotlight would launch instead of the installed app.
LSREG=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
"$LSREG" -u "$APP" 2>/dev/null || true

VERSION="$(defaults read "$REPO/$APP/Contents/Info.plist" CFBundleShortVersionString)"
echo "==> Fioka $VERSION: $(lipo -archs "$APP/Contents/MacOS/Fioka")"

rm -rf "$STAGE"
mkdir -p "$STAGE"
# ditto keeps the bundle's symlinks and extended attributes intact.
ditto "$APP" "$STAGE/Fioka.app"
"$LSREG" -u "$APP" 2>/dev/null || true

echo "==> Signing with ${SIGN_ID}"
scripts/sign-app.sh "$STAGE/Fioka.app" "$SIGN_ID"

ln -s /Applications "$STAGE/Applications"

DMG="$OUT/Fioka-$VERSION.dmg"
rm -f "$DMG"
echo "==> Making $DMG"
hdiutil create -volname "Fioka $VERSION" -srcfolder "$STAGE" -fs HFS+ \
  -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"

shasum -a 256 "$DMG"
echo "==> Done: $DMG"
