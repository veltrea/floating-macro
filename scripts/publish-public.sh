#!/usr/bin/env bash
# publish-public.sh — Publish whitelisted files to the public GitHub repository
# with history preserved (no force-push).
#
# What this script does:
#   1. Shallow-clones the public repo into /tmp.
#   2. Removes all tracked files (keeping .git/).
#   3. Copies ONLY whitelisted files from the private repo via rsync.
#   4. Sanitizes transient/sensitive files that may have snuck in.
#   5. If there are changes, commits and pushes (normal push, no -f).
#
# Everything outside the whitelist stays private. Update the whitelist
# arrays below when the project structure changes.
#
# Assumptions:
#   - `gh` is authenticated as `veltrea`
#   - Public repo exists: https://github.com/veltrea/floating-macro.git
#   - Force-push is intentionally NOT used — public history is preserved
#
# Usage:
#   bash scripts/publish-public.sh              # diff preview + commit + push
#   DRY_RUN=1 bash scripts/publish-public.sh    # diff preview only, no push
#   KEEP_TMP=1 bash scripts/publish-public.sh   # don't delete the tmp clone
#
# Re-runnable: safe to call repeatedly. If nothing changed, no commit is made.

set -euo pipefail

# ------------------------------------------------------------------------- #
# Config
# ------------------------------------------------------------------------- #

PUBLIC_URL="https://github.com/veltrea/floating-macro.git"
PUBLIC_BRANCH="main"

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "$HERE/.." && pwd)"

TMP="/tmp/floatingmacro-public-$(date +%Y%m%d-%H%M%S)-$$"

# ------------------------------------------------------------------------- #
# Whitelist: only these files/directories are published.
#
# Paths are relative to the project root. Everything else stays private.
# ------------------------------------------------------------------------- #

INCLUDE_DIRS=(
    "Sources"          # All source code (Core + CLI + App + bundled Lucide)
    "Tests"            # Unit tests
    "scripts"          # Build / smoke-test / publish scripts
    "App"              # Info.plist (build-app.sh reads it as a template)
    "npm"              # Bundled MCP stdio package — AI 連携 CLI 登録に必要
    "manual"           # User-facing manuals (basic + AI examples + images)
    ".github"          # GitHub Actions workflows
)

INCLUDE_FILES=(
    "Package.swift"
    "LICENSE"
    "THIRD_PARTY_LICENSES.md"
    "README.md"
    "README.ja.md"
    "SPEC.md"
    "DESIGN.md"
    "CHANGELOG.md"
    # "CLAUDE.md"  — AI internal instructions, not published
    ".gitignore"
    # build-app.sh references only one file for generating AppIcon.icns.
    # When the entire directory in assets/ is published, Stitch's intermediate files (zip / candidates) are generated.
    # Include files individually because the icon (20+) file is included.
    "assets/icons/stitch-hero-v1-squircle-vector-1024.png"
)

# Intentionally NOT published:
#   .build/ .swiftpm/ Package.resolved   -> build artifacts
#   .claude/                              -> Claude Code local settings
#   .git/                                 -> source repo history (private)
# Stitch intermediate files (excluding hero PNG)
# blog/ -> blog draft
# docs/ -> Internal documents (HANDOVER, INCIDENT, plans)
# TODO.md -> Work Memo

# ------------------------------------------------------------------------- #
# Pretty logging
# ------------------------------------------------------------------------- #

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[X]\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[OK]\033[0m %s\n' "$*" >&2; }

# ------------------------------------------------------------------------- #
# Pre-flight checks
# ------------------------------------------------------------------------- #

say "Pre-flight checks"

if ! command -v gh >/dev/null 2>&1; then
    err "gh CLI not found. Install with 'brew install gh'."
    exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
    err "gh not authenticated. Run 'gh auth login' first."
    exit 1
fi
if ! command -v rsync >/dev/null 2>&1; then
    err "rsync not found."
    exit 1
fi
ok "gh + git + rsync available"

# Derive commit message from private repo's latest commit.
PRIVATE_MSG="$(cd "$SRC" && git log -1 --format='%s')"
PRIVATE_HASH="$(cd "$SRC" && git log -1 --format='%h')"

# ------------------------------------------------------------------------- #
# 1. Shallow-clone the public repo
# ------------------------------------------------------------------------- #

say "Cloning public repo (shallow) into $TMP"

if git clone --depth 1 --branch "$PUBLIC_BRANCH" "$PUBLIC_URL" "$TMP" 2>/dev/null; then
    ok "Cloned existing public repo"
else
    # Public repo might be empty (first run after switching from force-push).
    say "Clone failed — initializing fresh repo"
    mkdir -p "$TMP"
    cd "$TMP"
    git init -b "$PUBLIC_BRANCH" >/dev/null
    git remote add origin "$PUBLIC_URL"
fi

cd "$TMP"
git config user.name  "veltrea"
git config user.email "veltrea@users.noreply.github.com"

# ------------------------------------------------------------------------- #
# 2. Remove all tracked content (keep .git/)
# ------------------------------------------------------------------------- #

say "Clearing working tree"
# Remove everything except .git to get a clean slate for the whitelist copy.
find "$TMP" -mindepth 1 -maxdepth 1 -not -name '.git' -exec rm -rf {} +

# ------------------------------------------------------------------------- #
# 3. Copy whitelisted files via rsync
# ------------------------------------------------------------------------- #

say "Copying whitelisted content from private repo"

copied=0
for dir in "${INCLUDE_DIRS[@]}"; do
    if [ -d "$SRC/$dir" ]; then
        # rsync with trailing / to copy contents into the matching dir.
        mkdir -p "$TMP/$dir"
        rsync -a --exclude '.DS_Store' \
                 --exclude '*.log' \
                 --exclude '.build' \
                 --exclude '.swiftpm' \
                 --exclude 'Package.resolved' \
                 --exclude 'fm_stitch_project.json' \
                 --exclude '.translate-cache.json' \
            "$SRC/$dir/" "$TMP/$dir/"
        copied=$((copied+1))
        printf '   + %s/\n' "$dir" >&2
    else
        warn "directory missing in source: $dir (skipped)"
    fi
done

for f in "${INCLUDE_FILES[@]}"; do
    if [ -f "$SRC/$f" ]; then
        mkdir -p "$TMP/$(dirname "$f")"
        cp "$SRC/$f" "$TMP/$f"
        copied=$((copied+1))
        printf '   + %s\n' "$f" >&2
    else
        warn "file missing in source: $f (skipped)"
    fi
done

# Extra sanitation — belt-and-suspenders cleanup.
find "$TMP" -name '.DS_Store' -delete 2>/dev/null || true
find "$TMP" -name '*.log' -delete 2>/dev/null || true

file_count=$(find "$TMP" -type f ! -path '*/.git/*' | wc -l | tr -d ' ')
dir_size=$(du -sh "$TMP" | awk '{print $1}')
ok "Snapshot ready: $file_count files, $dir_size"

# ------------------------------------------------------------------------- #
# 3.5. Translate Japanese comments to English
# ------------------------------------------------------------------------- #

if [ "${SKIP_TRANSLATE:-0}" != "1" ]; then
    say "Translating Japanese comments to English"
    bash "$HERE/translate-comments.sh" "$TMP" || warn "Comment translation had errors (continuing)"
else
    warn "SKIP_TRANSLATE=1 → skipping comment translation"
fi

# ------------------------------------------------------------------------- #
# 3.7. Translate Markdown docs (Japanese → English + keep .ja.md copy)
# ------------------------------------------------------------------------- #

TRANSLATE_MD_FILES=("SPEC.md")

if [ "${SKIP_TRANSLATE:-0}" != "1" ] && command -v claude >/dev/null 2>&1; then
    for mdfile in "${TRANSLATE_MD_FILES[@]}"; do
        if [ -f "$TMP/$mdfile" ] && grep -q '[ぁ-んァ-ヶ一-龥]' "$TMP/$mdfile"; then
            base="${mdfile%.md}"
            say "Translating $mdfile → English (keeping ${base}.ja.md)"
            cp "$TMP/$mdfile" "$TMP/${base}.ja.md"
            TRANSLATED=$(claude -p "Translate this Markdown document from Japanese to English. Keep all Markdown formatting, code blocks, file paths, version numbers, and technical terms intact. Output ONLY the translated document, nothing else." < "$TMP/$mdfile" 2>/dev/null) || true
            if [ -n "$TRANSLATED" ]; then
                printf '%s\n' "$TRANSLATED" > "$TMP/$mdfile"
                ok "$mdfile translated to English"
            else
                warn "$mdfile translation failed, keeping original"
            fi
        fi
    done
fi

# ------------------------------------------------------------------------- #
# 4. Show diff preview
# ------------------------------------------------------------------------- #

say "Top-level contents:"
(cd "$TMP" && ls -1) | sed 's/^/   /' >&2

# Stage everything to compute the diff.
cd "$TMP"
git add -A

say "Changes to be published:"
DIFF_STAT="$(git diff --cached --stat 2>/dev/null || true)"
if [ -z "$DIFF_STAT" ]; then
    ok "No changes — public repo is already up to date."
    if [ "${KEEP_TMP:-0}" != "1" ]; then
        cd /; rm -rf "$TMP"
    fi
    exit 0
fi
echo "$DIFF_STAT" | sed 's/^/   /' >&2
echo >&2

if [ "${DRY_RUN:-0}" = "1" ]; then
    warn "DRY_RUN=1 → stopping before commit/push"
    say "Full diff available at: $TMP"
    if [ "${KEEP_TMP:-0}" != "1" ]; then
        cd /; rm -rf "$TMP"
        ok "Snapshot removed"
    else
        ok "Snapshot kept at $TMP"
    fi
    exit 0
fi

# ------------------------------------------------------------------------- #
# 4.5. Translate commit message to English
# ------------------------------------------------------------------------- #

COMMIT_MSG="$PRIVATE_MSG"
if printf '%s' "$PRIVATE_MSG" | grep -q '[ぁ-んァ-ヶ一-龥]'; then
    say "Translating commit message to English"
    TRANSLATE_PROMPT="Translate this git commit message from Japanese to English. Keep it concise (one line). Keep version numbers, file names, and technical terms unchanged. Output ONLY the English translation, nothing else: $PRIVATE_MSG"
    if command -v claude >/dev/null 2>&1; then
        TRANSLATED_MSG="$(claude -p "$TRANSLATE_PROMPT" 2>/dev/null)" || true
        if [ -n "$TRANSLATED_MSG" ]; then
            COMMIT_MSG="$TRANSLATED_MSG"
            ok "Commit message: $COMMIT_MSG"
        else
            warn "Commit message translation failed, using original"
        fi
    else
        warn "claude CLI not available, using original commit message"
    fi
fi

# ------------------------------------------------------------------------- #
# 5. Commit and push (normal push — history preserved)
# ------------------------------------------------------------------------- #

say "Committing"
git commit -m "$COMMIT_MSG" >/dev/null
ok "Committed: $COMMIT_MSG"

say "Pushing to $PUBLIC_URL ($PUBLIC_BRANCH)"
if git push -u origin "$PUBLIC_BRANCH" 2>&1; then
    ok "Published successfully"
else
    err "Push failed. Snapshot kept at $TMP for inspection."
    exit 1
fi

# ------------------------------------------------------------------------- #
# 6. Clean up
# ------------------------------------------------------------------------- #

if [ "${KEEP_TMP:-0}" = "1" ]; then
    ok "Snapshot kept at $TMP"
else
    cd /
    rm -rf "$TMP"
    ok "Snapshot removed"
fi

say "Done. Public repo updated with history preserved."
