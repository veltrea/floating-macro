#!/usr/bin/env bash
# publish-public.sh — Publish a clean, history-less snapshot of this project
# to the public GitHub repository.
#
# What this script does:
#   1. Copies ONLY whitelisted files into a fresh /tmp/ directory.
#   2. Initializes a brand-new git repo there (no prior history).
#   3. Makes a single initial commit.
#   4. Force-pushes to https://github.com/veltrea/floating-macro.git on branch `main`.
#
# Everything outside the whitelist stays private. Iterate the whitelist if
# something is missing.
#
# Assumptions:
#   - `gh` is authenticated as `veltrea`
#   - Origin at https://github.com/veltrea/floating-macro.git exists (public)
#   - You are OK with overwriting the public repo's history every run
#
# Usage:
#   bash scripts/publish-public.sh              # preview + run
#   DRY_RUN=1 bash scripts/publish-public.sh    # preview only, no push
#   KEEP_TMP=1 bash scripts/publish-public.sh   # don't delete the tmp copy
#
# Re-runnable: safe to call repeatedly. Each run overwrites the public repo.

set -u -o pipefail

# ------------------------------------------------------------------------- #
# Config
# ------------------------------------------------------------------------- #

PUBLIC_URL="https://github.com/veltrea/floating-macro.git"
PUBLIC_BRANCH="main"
COMMIT_MESSAGE="Release of FloatingMacro"

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "$HERE/.." && pwd)"

TMP="/tmp/floatingmacro-public-$(date +%Y%m%d-%H%M%S)-$$"

# ------------------------------------------------------------------------- #
# Whitelist: only these files/directories are published.
#
# If you change the project structure, update this list. Paths are relative
# to the project root.
# ------------------------------------------------------------------------- #

INCLUDE_DIRS=(
    "Sources"          # All source code (Core + CLI + App + bundled Lucide)
    "Tests"            # Unit tests (226 tests)
    "scripts"          # fmcli_smoke, control_api_smoke, this script
    "docs"             # English + Japanese documentation
    ".github"          # GitHub Actions CI
)

INCLUDE_FILES=(
    "Package.swift"
    "LICENSE"
    "THIRD_PARTY_LICENSES.md"
    "README.md"
    "README.ja.md"
    "SPEC.md"
    "DESIGN.md"
    ".gitignore"
)

# Intentionally NOT published:
#   .build/ .swiftpm/ Package.resolved   -> build artifacts
#   .claude/                              -> Claude Code local settings
#   assets/                               -> tentative Stitch-generated icons
#                                            (keep private until final)
#   .git/                                 -> source repo history

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
if ! git --version >/dev/null 2>&1; then
    err "git not found."
    exit 1
fi
ok "gh + git available"

# ------------------------------------------------------------------------- #
# 1. Build the /tmp snapshot
# ------------------------------------------------------------------------- #

say "Creating snapshot at $TMP"
mkdir -p "$TMP"

copied=0
for dir in "${INCLUDE_DIRS[@]}"; do
    if [ -d "$SRC/$dir" ]; then
        cp -R "$SRC/$dir" "$TMP/"
        copied=$((copied+1))
        printf '   + %s/\n' "$dir" >&2
    else
        warn "directory missing in source: $dir (skipped)"
    fi
done
for f in "${INCLUDE_FILES[@]}"; do
    if [ -f "$SRC/$f" ]; then
        cp "$SRC/$f" "$TMP/"
        copied=$((copied+1))
        printf '   + %s\n' "$f" >&2
    else
        warn "file missing in source: $f (skipped)"
    fi
done

# Extra sanitation — delete known transient / sensitive files that may have
# snuck into included directories.
find "$TMP" -name '.DS_Store' -delete 2>/dev/null || true
find "$TMP" -name '*.log' -delete 2>/dev/null || true
find "$TMP" -name 'fm_stitch_project.json' -delete 2>/dev/null || true

file_count=$(find "$TMP" -type f ! -path '*/.git/*' | wc -l | tr -d ' ')
dir_size=$(du -sh "$TMP" | awk '{print $1}')
ok "Snapshot ready: $file_count files, $dir_size"

# ------------------------------------------------------------------------- #
# 2. Show a preview of what will be published
# ------------------------------------------------------------------------- #

say "Top-level contents of the snapshot:"
(cd "$TMP" && ls -1) | sed 's/^/   /' >&2

if [ "${DRY_RUN:-0}" = "1" ]; then
    warn "DRY_RUN=1 → stopping before git init / push"
    if [ "${KEEP_TMP:-0}" = "1" ]; then
        ok "Snapshot kept at $TMP"
    else
        rm -rf "$TMP"
        ok "Snapshot removed"
    fi
    exit 0
fi

# ------------------------------------------------------------------------- #
# 3. git init + single commit
# ------------------------------------------------------------------------- #

say "Initializing fresh git history"
cd "$TMP"

git init -b "$PUBLIC_BRANCH" >/dev/null
git config user.name  "veltrea"
git config user.email "veltrea@users.noreply.github.com"

git add -A
git commit -m "$COMMIT_MESSAGE" >/dev/null
ok "Single-commit history created"

# ------------------------------------------------------------------------- #
# 4. Force-push to public repo
# ------------------------------------------------------------------------- #

say "Force-pushing to $PUBLIC_URL ($PUBLIC_BRANCH)"
git remote add origin "$PUBLIC_URL"

# -f is intentional: we are replacing the public repo each run by design.
if git push -f -u origin "$PUBLIC_BRANCH" 2>&1; then
    ok "Published successfully"
else
    err "Push failed. Snapshot kept at $TMP for inspection."
    exit 1
fi

# ------------------------------------------------------------------------- #
# 5. Clean up
# ------------------------------------------------------------------------- #

if [ "${KEEP_TMP:-0}" = "1" ]; then
    ok "Snapshot kept at $TMP"
else
    cd /
    rm -rf "$TMP"
    ok "Snapshot removed"
fi

say "Done."
