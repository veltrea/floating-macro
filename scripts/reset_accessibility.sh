#!/bin/bash
# reset_accessibility.sh — drop FloatingMacro's Accessibility entry from
# the macOS TCC database and reopen the Accessibility settings pane so
# you can re-add it with one drag.
#
# Why this exists:
#   macOS occasionally silently invalidates the Accessibility permission
#   for an app — the entry is still listed in System Settings, but
#   `CGEvent.post` is dropped at the OS level. The recovery is "remove
#   from the list, then add back". Removing from the list manually is
#   a finicky few-click dance through System Settings → list scroll →
#   "i" button → Remove. `tccutil reset` does the removal in one shot.
#
# `tccutil reset` is Apple's official tool, requires NO sudo, and only
# touches THIS app's entry — other apps' Accessibility permissions are
# left alone. The "Successfully reset" message may print twice if there
# are entries for both the bundle id and a path-based variant.
#
# After reset, you still have to manually re-add (Apple deliberately
# doesn't let any process grant Accessibility programmatically). This
# script opens the right pane so the next two clicks finish it.

set -euo pipefail

BUNDLE_ID="${1:-com.veltrea.FloatingMacro}"

echo "Resetting Accessibility approval for $BUNDLE_ID..."
tccutil reset Accessibility "$BUNDLE_ID"

# Brief pause so the TCC daemon settles before the user re-adds.
sleep 0.3

echo "Opening System Settings → Privacy & Security → Accessibility..."
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

cat <<'EOF'

→ Next:
  1) Click + (or drag the .app into the list)
  2) Pick /Volumes/DISK/dev/floatingmacro/build/FloatingMacro.app
  3) Toggle ON
  4) The orange badge in the FloatingMacro panel will disappear within
     a few seconds.

EOF
