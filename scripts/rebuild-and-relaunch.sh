#!/usr/bin/env bash
# rebuild-and-relaunch.sh — 100% 確実に最新のバイナリで FloatingMacro.app を起動する。
#
# 目的:
#   「ビルドしたのに古い .app が動いてる」を防ぐ。起動中のプロセスを確実に
#   殺してから、SwiftPM のビルドキャッシュを完全に消して、build-app.sh で
#   ゼロから .app を組み立て直し、新しい .app を open する。
#
# 使い方:
#   bash scripts/rebuild-and-relaunch.sh

set -u -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
cd "$ROOT"

APP="$ROOT/build/FloatingMacro.app"
BIN_NAME="FloatingMacro"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*" >&2; }
ok()  { printf '\033[1;32m[OK]\033[0m %s\n' "$*" >&2; }
err() { printf '\033[1;31m[X]\033[0m %s\n' "$*" >&2; }

# ------------------------------------------------------------------- #
# 1. 起動中のプロセスを確実に停止
# ------------------------------------------------------------------- #
say "Stopping any running FloatingMacro …"

# .app 経由で起動したインスタンスをまず穏やかに終了
osascript -e 'tell application "FloatingMacro" to quit' >/dev/null 2>&1 || true

# swift run 経由 / .app 経由 / コマンドライン経由 — 全部拾って殺す
pkill -x "$BIN_NAME" >/dev/null 2>&1 || true
pkill -f "/$BIN_NAME$" >/dev/null 2>&1 || true

# まだ残っているか確認して SIGKILL
sleep 0.5
if pgrep -x "$BIN_NAME" >/dev/null 2>&1; then
    pkill -9 -x "$BIN_NAME" >/dev/null 2>&1 || true
fi

if pgrep -x "$BIN_NAME" >/dev/null 2>&1; then
    err "$BIN_NAME がまだ生きています。手動で終了してから再実行してください。"
    pgrep -x "$BIN_NAME" | sed 's/^/   pid: /' >&2
    exit 1
fi
ok "stopped"

# ------------------------------------------------------------------- #
# 2. 完全クリーン
# ------------------------------------------------------------------- #
say "Cleaning SwiftPM build artifacts …"
swift package clean >/dev/null
# SwiftPM が使う .build ディレクトリを丸ごと消す
rm -rf "$ROOT/.build"
# 以前組み立てた .app も消す
rm -rf "$APP"
rm -rf "$ROOT/build/AppIcon.icns" "$ROOT/build/AppIcon.iconset"
ok "cleaned"

# ------------------------------------------------------------------- #
# 3. フルビルド → .app 組み立て
# ------------------------------------------------------------------- #
say "Rebuilding .app from scratch …"
bash "$ROOT/scripts/build-app.sh"

if [ ! -d "$APP" ]; then
    err "ビルド失敗: $APP が存在しません"
    exit 1
fi

# ------------------------------------------------------------------- #
# 4. バイナリのタイムスタンプを表示して古くないことを確認
# ------------------------------------------------------------------- #
NEW_BIN="$APP/Contents/MacOS/$BIN_NAME"
if [ ! -x "$NEW_BIN" ]; then
    err "バイナリが見つかりません: $NEW_BIN"
    exit 1
fi
BUILT_AT="$(date -r "$NEW_BIN" '+%Y-%m-%d %H:%M:%S')"
ok "binary built at: $BUILT_AT"

# ------------------------------------------------------------------- #
# 5. 起動 — 必ず .app 経由で
# ------------------------------------------------------------------- #
say "Launching $APP …"
# -n: 既存インスタンスがあっても新しく起動 (この時点で既存はいないはずだが保険)
# -F: Finder キャッシュを無視して今の .app を起動
open -n -F "$APP"

# 起動確認
sleep 1
if pgrep -x "$BIN_NAME" >/dev/null 2>&1; then
    PID="$(pgrep -x "$BIN_NAME" | head -1)"
    ok "launched (pid: $PID)"
else
    err "起動に失敗しました。Console.app のログを確認してください。"
    exit 1
fi

ok "Done."
