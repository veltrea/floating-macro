#!/usr/bin/env bash
# build-app.sh — Build FloatingMacro.app (release, ad-hoc signed).
#
# SwiftPM `executableTarget` produces a flat binary. macOS wants an .app
# bundle: Contents/MacOS/<exe>, Contents/Info.plist, Contents/Resources/...
# This script assembles one from the SwiftPM output so the result:
#
#   - launches from /Applications (no `swift run` needed)
#   - has LSUIElement=YES → no Dock icon, no standard menu bar
#   - carries a real AppIcon.icns (expanded from the Stitch hero art)
#   - includes the Lucide SVG resource bundle so icons render
#
# Ad-hoc signed (`codesign -s -`) so Gatekeeper accepts it locally. For
# distribution outside this machine, re-sign with a Developer ID cert.
#
# Usage:
#   bash scripts/build-app.sh                 # build to ./build/FloatingMacro.app
#   OPEN=1 bash scripts/build-app.sh          # also `open` the .app after build
#   INSTALL=1 bash scripts/build-app.sh       # also copy to /Applications/

set -u -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
cd "$ROOT"

# Xcode must be active (CommandLineTools alone lacks some SDKs).
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

OUT="$ROOT/build"
APP="$OUT/FloatingMacro.app"
CONTENTS="$APP/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"

INFO_TEMPLATE="$ROOT/App/Info.plist"
HERO_PNG="$ROOT/assets/icons/stitch-hero-v1-squircle-vector-1024.png"

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[OK]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[X]\033[0m %s\n' "$*" >&2; }

# ------------------------------------------------------------------- #
# 1. Compile release binary
# ------------------------------------------------------------------- #

say "Compiling (release) …"
swift build -c release --product FloatingMacro >/dev/null
BIN_DIR="$(swift build -c release --product FloatingMacro --show-bin-path)"
BIN="$BIN_DIR/FloatingMacro"
if [ ! -x "$BIN" ]; then
    err "executable not found at $BIN"
    exit 1
fi
ok "binary: $BIN"

# ------------------------------------------------------------------- #
# 2. Build AppIcon.icns from the Stitch hero PNG
# ------------------------------------------------------------------- #

if [ ! -f "$HERO_PNG" ]; then
    err "hero icon missing at $HERO_PNG"
    exit 1
fi

say "Building AppIcon.icns from $HERO_PNG"
ICONSET="$OUT/AppIcon.iconset"
rm -rf "$ICONSET" "$OUT/AppIcon.icns"
mkdir -p "$ICONSET"

# Apple .iconset convention — each size expressed at 1x and 2x.
gen() {
    local size="$1" name="$2"
    sips -s format png -z "$size" "$size" "$HERO_PNG" \
        --out "$ICONSET/$name" >/dev/null
}
# 16
gen 16   icon_16x16.png
gen 32   icon_16x16@2x.png
# 32
gen 32   icon_32x32.png
gen 64   icon_32x32@2x.png
# 128
gen 128  icon_128x128.png
gen 256  icon_128x128@2x.png
# 256
gen 256  icon_256x256.png
gen 512  icon_256x256@2x.png
# 512
gen 512  icon_512x512.png
gen 1024 icon_512x512@2x.png

iconutil -c icns -o "$OUT/AppIcon.icns" "$ICONSET"
ok "AppIcon.icns built"

# ------------------------------------------------------------------- #
# 3. Lay out the .app bundle
# ------------------------------------------------------------------- #

say "Assembling $APP"
rm -rf "$APP"
mkdir -p "$MACOS_DIR" "$RES_DIR"

cp "$BIN"             "$MACOS_DIR/FloatingMacro"
cp "$INFO_TEMPLATE"   "$CONTENTS/Info.plist"
cp "$OUT/AppIcon.icns" "$RES_DIR/AppIcon.icns"

# SwiftPM emits a resource bundle alongside the binary. We need it inside
# Contents/Resources so Bundle.module keeps working at runtime.
for bundle in "$BIN_DIR"/*_FloatingMacroApp.bundle "$BIN_DIR"/FloatingMacro_FloatingMacroApp.bundle; do
    if [ -d "$bundle" ]; then
        cp -R "$bundle" "$RES_DIR/"
        ok "copied resource bundle: $(basename "$bundle")"
    fi
done

# ------------------------------------------------------------------- #
# 4. Ad-hoc sign
# ------------------------------------------------------------------- #

say "Ad-hoc signing"
codesign --sign - --deep --force --timestamp=none "$APP" 2>&1 | tail -2
ok "signed"

# ------------------------------------------------------------------- #
# 5. Report
# ------------------------------------------------------------------- #

say "Bundle contents:"
( cd "$APP" && find Contents -maxdepth 3 -type d -o -maxdepth 3 -name '*.plist' -o -maxdepth 3 -name '*.icns' -o -maxdepth 3 -name 'FloatingMacro' -type f ) | sed 's/^/   /'
say "Size:"
du -sh "$APP" | awk '{printf "   %s\n", $0}'

# ------------------------------------------------------------------- #
# 6. Optional actions
# ------------------------------------------------------------------- #

if [ "${INSTALL:-0}" = "1" ]; then
    say "Installing to /Applications/"
    rm -rf "/Applications/FloatingMacro.app"
    cp -R "$APP" "/Applications/"
    ok "installed to /Applications/FloatingMacro.app"
fi

if [ "${OPEN:-0}" = "1" ]; then
    say "Launching"
    open "$APP"
fi

ok "Done: $APP"
