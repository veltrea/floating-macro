#!/usr/bin/env bash
# rebuild-and-relaunch.sh - Launches FloatingMacro.app with the latest binary at 100% certainty.
#
# Purpose:
# Prevent "running old .app even after building" by reliably confirming running processes.
# Delete first, then completely clear the SwiftPM build cache and run build-app.sh.
# Build a new .app from scratch and open it.
#
# Configuration source:
# Launch directly from the default build/FloatingMacro.app (no copy).
# Back to this flow for now, as TCC was stable up to v0.2, so let's verify with it first.
#
# When copied to Applications, macOS sets the com.apple.provenance xattr on the file.
# Assigned to the App Management category. Ad-hoc signed apps since Sequoia.
# Under the App Management category, TCC is treated unusually strictly, and every rebuild requires it.
# Suspicion that it was behaving as if permission was silent and peeled off.
#
# Overwrite DEPLOY_DEST when deploying to /Applications:
#     DEPLOY_DEST=/Applications/FloatingMacro.app bash scripts/rebuild-and-relaunch.sh
#
# Usage:
#   bash scripts/rebuild-and-relaunch.sh
#   DEPLOY_DEST=/path/to/FloatingMacro.app bash scripts/rebuild-and-relaunch.sh

set -u -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
cd "$ROOT"

# build-app.sh builds the .app at this path. The deployment destination (DEPLOY_DEST) is
# Separately set to the default Applications.
BUILD_APP="$ROOT/build/FloatingMacro.app"
DEPLOY_DEST="${DEPLOY_DEST:-$BUILD_APP}"
BIN_NAME="FloatingMacro"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*" >&2; }
ok()  { printf '\033[1;32m[OK]\033[0m %s\n' "$*" >&2; }
err() { printf '\033[1;31m[X]\033[0m %s\n' "$*" >&2; }

# ------------------------------------------------------------------- #
# Stop running processes reliably
# ------------------------------------------------------------------- #
say "Stopping any running FloatingMacro …"

# Gracefully terminate the instance launched via .app
osascript -e 'tell application "FloatingMacro" to quit' >/dev/null 2>&1 || true

# Run via swift run, app via .app, command-line via - Kill them all.
pkill -x "$BIN_NAME" >/dev/null 2>&1 || true
pkill -f "/$BIN_NAME$" >/dev/null 2>&1 || true

# Check if still remaining and send SIGKILL
sleep 0.5
if pgrep -x "$BIN_NAME" >/dev/null 2>&1; then
    pkill -9 -x "$BIN_NAME" >/dev/null 2>&1 || true
fi

if pgrep -x "$BIN_NAME" >/dev/null 2>&1; then
    err "$BIN_NAME Still alive. Please exit manually and try again."
    pgrep -x "$BIN_NAME" | sed 's/^/   pid: /' >&2
    exit 1
fi
ok "stopped"

# ------------------------------------------------------------------- #
# Fully clean
# ------------------------------------------------------------------- #
say "Cleaning SwiftPM build artifacts …"
swift package clean >/dev/null
# Delete the entire .build directory used by SwiftPM
rm -rf "$ROOT/.build"
# Delete previously built .app also
rm -rf "$BUILD_APP"
rm -rf "$ROOT/build/AppIcon.icns" "$ROOT/build/AppIcon.iconset"
ok "cleaned"

# ------------------------------------------------------------------- #
# Full build → .app assembly
# ------------------------------------------------------------------- #
say "Rebuilding .app from scratch …"
bash "$ROOT/scripts/build-app.sh"

if [ ! -d "$BUILD_APP" ]; then
    err "Build failed: $BUILD_APP does not exist"
    exit 1
fi

# ------------------------------------------------------------------- #
# Display binary timestamp and verify it is not old
# ------------------------------------------------------------------- #
NEW_BIN="$BUILD_APP/Contents/MacOS/$BIN_NAME"
if [ ! -x "$NEW_BIN" ]; then
    err "Binary not found: $NEW_BIN"
    exit 1
fi
BUILT_AT="$(date -r "$NEW_BIN" '+%Y-%m-%d %H:%M:%S')"
ok "binary built at: $BUILT_AT"

# ------------------------------------------------------------------- #
# 5. Deploy - Overwritten by default to /Applications/FloatingMacro.app.
# Ad-hoc-signed app's TCC (Accessibility) is identified by the path, so
# Deploying to a fixed path allows permissions to persist across rebuilds.
# ------------------------------------------------------------------- #
DEPLOY_DIR="$(dirname "$DEPLOY_DEST")"
if [ "$BUILD_APP" = "$DEPLOY_DEST" ]; then
    # Copy unnecessary if build and placement are the same
    say "Deploy dest matches build path — skipping copy"
else
    say "Deploying to $DEPLOY_DEST …"
    if [ ! -d "$DEPLOY_DIR" ]; then
        err "Deployment directory does not exist: $DEPLOY_DIR"
        exit 1
    fi
    if [ ! -w "$DEPLOY_DIR" ]; then
        err "Cannot write to deployment target: $DEPLOY_DIR"
        err "If you want to deploy to a different path, use DEPLOY_DEST.=/path/to/Foo.app Please specify: Please specify:"
        exit 1
    fi
    rm -rf "$DEPLOY_DEST"
    cp -R "$BUILD_APP" "$DEPLOY_DEST"
    ok "deployed: $DEPLOY_DEST"
fi

# ------------------------------------------------------------------- #
# TCC reset has been centralized on the app side (BinaryIdentity), so it is removed.
#
# Previously, we called `tccutil reset Accessibility <bundleId>` right before this.
# However, after the app launch, same reset in handleStartupCheck
# was running twice due to double firing. Immediately after a double reset, calling prompt:true would result in:
# In Sequoia, authentication for list addition is required at the System Settings level, along with toggle-on authentication.
# The password is requested twice, so remove the reset on the script side.
# BinaryIdentity detects hash changes and resets, so there are no functional gaps.
# ------------------------------------------------------------------- #

# ------------------------------------------------------------------- #
# Launch - Always via .app
# ------------------------------------------------------------------- #
say "Launching $DEPLOY_DEST …"
# -: Launch a new instance even if there are existing instances (at this point, the existing ones should not exist as a precaution).
# Launch the current .app while ignoring the Finder cache
open -n -F "$DEPLOY_DEST"

# Launch Confirmation
sleep 1
if pgrep -x "$BIN_NAME" >/dev/null 2>&1; then
    PID="$(pgrep -x "$BIN_NAME" | head -1)"
    ok "launched (pid: $PID)"
else
    err "Failed to launch. Console.app Please check your logs."
    exit 1
fi

ok "Done."
