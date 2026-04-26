#!/usr/bin/env bash
# release.sh — Build FloatingMacro.app, wrap it in a DMG, publish the source
#              to the public repo, and create a GitHub latest-release.
#
# Usage:
#   bash scripts/release.sh 0.3.0             # explicit version
#   bash scripts/release.sh                   # use current Info.plist version
#   bash scripts/release.sh --bump-minor      # auto-increment minor (0.1 → 0.2)
#   bash scripts/release.sh --bump-patch      # auto-increment patch (0.1.0 → 0.1.1)
#
# Extra env vars:
#   DRY_RUN=1      — build + package DMG, but skip source-publish and GitHub release
#   SKIP_PUBLISH=1 — skip source-publish (useful when re-releasing the same commit)

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
INFO_PLIST="$ROOT/App/Info.plist"
PUBLIC_REPO="veltrea/floating-macro"

# ------------------------------------------------------------------ #
# Helpers
# ------------------------------------------------------------------ #

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[OK]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[X]\033[0m %s\n' "$*" >&2; exit 1; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
ask()  { read -r -p "$(printf '\033[1;33m[?]\033[0m %s [y/N] ' "$1")" _ans; [[ "${_ans:-}" =~ ^[yY] ]]; }

plist_read()  { plutil -extract "$1" raw "$INFO_PLIST"; }
plist_write() { plutil -replace "$1" -string "$2" "$INFO_PLIST"; }

# ------------------------------------------------------------------ #
# 1. Resolve version
# ------------------------------------------------------------------ #

say "Resolving version"

CURRENT_VERSION=$(plist_read CFBundleShortVersionString)
CURRENT_BUILD=$(plist_read CFBundleVersion)

case "${1:-}" in
    --bump-minor)
        IFS='.' read -r MAJOR MINOR PATCH <<< "${CURRENT_VERSION}.0"
        VERSION="${MAJOR}.$((MINOR + 1)).0"
        VERSION="${VERSION%.0}"   # keep "0.2" instead of "0.2.0" if no patch
        ;;
    --bump-patch)
        IFS='.' read -r MAJOR MINOR PATCH <<< "${CURRENT_VERSION}.0"
        VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))"
        ;;
    "")
        VERSION="${CURRENT_VERSION}"
        ;;
    *)
        VERSION="${1}"
        ;;
esac

# Build number = current + 1 (stored back in Info.plist)
NEW_BUILD=$((CURRENT_BUILD + 1))
TAG="v${VERSION}"

printf '   current : %s (build %s)\n' "$CURRENT_VERSION" "$CURRENT_BUILD" >&2
printf '   release : %s (build %s) → tag %s\n' "$VERSION" "$NEW_BUILD" "$TAG" >&2

# ------------------------------------------------------------------ #
# 2. Pre-flight checks
# ------------------------------------------------------------------ #

say "Pre-flight checks"

command -v gh      >/dev/null 2>&1 || err "'gh' not found. brew install gh"
command -v hdiutil >/dev/null 2>&1 || err "hdiutil not found (macOS only)"
gh auth status     >/dev/null 2>&1 || err "gh not authenticated. gh auth login"
ok "tools available"

# Warn if the release tag already exists on the public repo.
if gh release view "$TAG" --repo "$PUBLIC_REPO" >/dev/null 2>&1; then
    warn "Release $TAG already exists on github.com/$PUBLIC_REPO"
    if ask "Delete existing release and recreate?"; then
        gh release delete "$TAG" --repo "$PUBLIC_REPO" --yes
        ok "Deleted existing release $TAG"
    else
        err "Aborted."
    fi
fi

# ------------------------------------------------------------------ #
# 3. Bump version in Info.plist (before build so binary carries it)
# ------------------------------------------------------------------ #

say "Writing version to Info.plist"
plist_write CFBundleShortVersionString "$VERSION"
plist_write CFBundleVersion            "$NEW_BUILD"
ok "Info.plist → $VERSION (build $NEW_BUILD)"

# ------------------------------------------------------------------ #
# 4. Build .app
# ------------------------------------------------------------------ #

say "Building FloatingMacro.app (release)"
bash "$HERE/build-app.sh"

APP="$ROOT/build/FloatingMacro.app"
[ -d "$APP" ] || err ".app not found at $APP after build"
ok ".app ready"

# ------------------------------------------------------------------ #
# 5. Create DMG
# ------------------------------------------------------------------ #

OUT="$ROOT/build"
DMG_NAME="FloatingMacro-${VERSION}.dmg"
DMG="$OUT/$DMG_NAME"
STAGING="$OUT/dmg-staging"

say "Packaging $DMG_NAME"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -sf /Applications "$STAGING/Applications"

# AI 連携の手順書を DMG にも同梱する。DMG ユーザーはリポジトリを見ないので、
# AI 経由で操作するために必要な情報を Finder マウント時に並ぶ位置で渡す。
if [ -f "$ROOT/CLAUDE.md" ]; then
    cp "$ROOT/CLAUDE.md" "$STAGING/AIに渡す手順書.md"
fi

hdiutil create \
    -volname "FloatingMacro ${VERSION}" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG" >/dev/null

rm -rf "$STAGING"
ok "DMG ready: $DMG_NAME ($(du -sh "$DMG" | awk '{print $1}'))"

# ------------------------------------------------------------------ #
# DRY_RUN stops here
# ------------------------------------------------------------------ #

if [ "${DRY_RUN:-0}" = "1" ]; then
    warn "DRY_RUN=1 — stopping before source-publish and GitHub release"
    say "DMG: $DMG"
    exit 0
fi

# ------------------------------------------------------------------ #
# 6. Publish source to public repo
# ------------------------------------------------------------------ #

if [ "${SKIP_PUBLISH:-0}" != "1" ]; then
    say "Publishing source to github.com/$PUBLIC_REPO"
    COMMIT_MESSAGE="FloatingMacro ${VERSION}" bash "$HERE/publish-public.sh"
    ok "Source published"
else
    warn "SKIP_PUBLISH=1 — skipping source publish"
fi

# ------------------------------------------------------------------ #
# 7. Create GitHub release with DMG attached
# ------------------------------------------------------------------ #

say "Creating release $TAG on github.com/$PUBLIC_REPO"

RELEASE_NOTES=$(cat <<NOTES
## FloatingMacro ${VERSION}

**インストール方法**

1. DMG ファイルを開く
2. FloatingMacro.app を Applications フォルダへドラッグ
3. 初回起動時はアクセシビリティ権限を許可（システム設定 → プライバシーとセキュリティ → アクセシビリティ）

**動作環境**

- macOS 13 Ventura 以降
- Apple Silicon / Intel 両対応
NOTES
)

gh release create "$TAG" \
    --repo "$PUBLIC_REPO" \
    --title "FloatingMacro ${VERSION}" \
    --notes "$RELEASE_NOTES" \
    --latest \
    "$DMG#FloatingMacro-${VERSION}.dmg"

ok "Released: https://github.com/$PUBLIC_REPO/releases/tag/$TAG"
say "Done."
