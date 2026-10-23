#!/bin/bash
# Sign an app bundle and everything nested in it: scripts/sign-app.sh APP IDENTITY
# IDENTITY is a certificate SHA-1, or "-" for ad-hoc.
#
# Nested code has to be signed before the bundle that contains it. Xcode leaves
# embedded frameworks (Sparkle in particular) on their original signature, and
# dyld refuses to load a framework whose Team ID differs from the process.
#
# Errors are NOT suppressed here: a silently failed codesign leaves the bundle
# ad-hoc signed with mangled nested code, which then fails to launch with a
# confusing dyld error rather than a signing one.
set -euo pipefail
APP="$1"
SIGN_ID="$2"

sign() {
  codesign --force --sign "$SIGN_ID" --timestamp=none "$1" || {
    echo "codesign FAILED on $1" >&2
    exit 1
  }
}

# Deepest first: bundled helper apps and XPC services, then loose Mach-O
# helpers, then the framework wrapper, then the app.
find "$APP/Contents/Frameworks" -type d \( -name "*.xpc" -o -name "*.app" \) -print0 |
  while IFS= read -r -d '' n; do sign "$n"; done

find "$APP/Contents/Frameworks" -type f -perm +111 \
  ! -path "*.xpc/*" ! -path "*/Updater.app/*" -print0 |
  while IFS= read -r -d '' f; do
    file "$f" | grep -q "Mach-O" && sign "$f"
  done

find "$APP/Contents/Frameworks" -maxdepth 1 -name "*.framework" -print0 |
  while IFS= read -r -d '' fw; do sign "$fw"; done

sign "$APP"

codesign --verify --deep --strict "$APP" || { echo "VERIFY FAILED" >&2; exit 1; }
echo "signature OK"
codesign -d -r- "$APP" 2>&1 | grep designated || true
