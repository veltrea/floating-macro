#!/usr/bin/env bash
# rebuild-and-relaunch.sh — 100% 確実に最新のバイナリで FloatingMacro.app を起動する。
#
# 目的:
#   「ビルドしたのに古い .app が動いてる」を防ぐ。起動中のプロセスを確実に
#   殺してから、SwiftPM のビルドキャッシュを完全に消して、build-app.sh で
#   ゼロから .app を組み立て直し、新しい .app を open する。
#
# 配置先:
#   既定では build/FloatingMacro.app から直接起動する（コピーなし）。
#   v0.2 までこのフローで TCC が安定していたため、まずこれに戻して検証する。
#
#   /Applications にコピーすると macOS が com.apple.provenance xattr を
#   付与し App Management 配下に置かれる。Sequoia 以降の ad-hoc 署名アプリ
#   は App Management 下では TCC が異常に厳しく扱われ、リビルドのたびに
#   許可が無音で剥がれる挙動を踏んでいた疑いが強い。
#
#   配布検証で /Applications に入れたいときは DEPLOY_DEST で上書きする：
#     DEPLOY_DEST=/Applications/FloatingMacro.app bash scripts/rebuild-and-relaunch.sh
#
# 使い方:
#   bash scripts/rebuild-and-relaunch.sh
#   DEPLOY_DEST=/path/to/FloatingMacro.app bash scripts/rebuild-and-relaunch.sh

set -u -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
cd "$ROOT"

# build-app.sh はこのパスに .app を組み立てる。デプロイ先 (DEPLOY_DEST) は
# 別途 /Applications を既定にしている。
BUILD_APP="$ROOT/build/FloatingMacro.app"
DEPLOY_DEST="${DEPLOY_DEST:-$BUILD_APP}"
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
rm -rf "$BUILD_APP"
rm -rf "$ROOT/build/AppIcon.icns" "$ROOT/build/AppIcon.iconset"
ok "cleaned"

# ------------------------------------------------------------------- #
# 3. フルビルド → .app 組み立て
# ------------------------------------------------------------------- #
say "Rebuilding .app from scratch …"
bash "$ROOT/scripts/build-app.sh"

if [ ! -d "$BUILD_APP" ]; then
    err "ビルド失敗: $BUILD_APP が存在しません"
    exit 1
fi

# ------------------------------------------------------------------- #
# 4. バイナリのタイムスタンプを表示して古くないことを確認
# ------------------------------------------------------------------- #
NEW_BIN="$BUILD_APP/Contents/MacOS/$BIN_NAME"
if [ ! -x "$NEW_BIN" ]; then
    err "バイナリが見つかりません: $NEW_BIN"
    exit 1
fi
BUILT_AT="$(date -r "$NEW_BIN" '+%Y-%m-%d %H:%M:%S')"
ok "binary built at: $BUILT_AT"

# ------------------------------------------------------------------- #
# 5. デプロイ — 既定で /Applications/FloatingMacro.app に上書きコピー。
#     ad-hoc 署名アプリの TCC (Accessibility) はパスで識別されるため、
#     固定パスにデプロイすることで許可がリビルドを跨いで残る。
# ------------------------------------------------------------------- #
DEPLOY_DIR="$(dirname "$DEPLOY_DEST")"
if [ "$BUILD_APP" = "$DEPLOY_DEST" ]; then
    # ビルド先と配置先が同じならコピー不要
    say "Deploy dest matches build path — skipping copy"
else
    say "Deploying to $DEPLOY_DEST …"
    if [ ! -d "$DEPLOY_DIR" ]; then
        err "デプロイ先ディレクトリが存在しません: $DEPLOY_DIR"
        exit 1
    fi
    if [ ! -w "$DEPLOY_DIR" ]; then
        err "デプロイ先に書き込めません: $DEPLOY_DIR"
        err "別パスに置く場合は DEPLOY_DEST=/path/to/Foo.app を指定してください"
        exit 1
    fi
    rm -rf "$DEPLOY_DEST"
    cp -R "$BUILD_APP" "$DEPLOY_DEST"
    ok "deployed: $DEPLOY_DEST"
fi

# ------------------------------------------------------------------- #
# 5.5. TCC リセット — 起動前に必須
# ------------------------------------------------------------------- #
# ad-hoc 署名でリビルドすると毎回バイナリハッシュが変わる。TCC は
# 「bundle ID + 署名 ID (= ad-hoc ではバイナリハッシュ)」で trust を
# 記録しているので、新バイナリは TCC からは「初見の別アプリ」扱い。
# にも関わらず、UI 上は「FloatingMacro」というエントリが既存のまま
# 残るため、「リスト追加 + トグル ON は通るのに trust が立たない」
# という silent revoke 状態に陥る。
#
# 起動の直前にエントリを完全削除しておけば、新バイナリが AX を
# 使おうとしたとき OS は本当に「新規アプリ」として扱い、通常の
# 許可ダイアログが出て、ユーザーが追加すれば trust が正しく立つ。
#
# NOTE: tccutil reset は sudo 不要、対象 bundle ID 以外の TCC 記録には
# 一切影響しない (FM のエントリだけが消える)。
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
    "$DEPLOY_DEST/Contents/Info.plist" 2>/dev/null || echo 'com.veltrea.FloatingMacro')"
say "Resetting TCC Accessibility entry for $BUNDLE_ID (ad-hoc rebuild required) …"
if tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1; then
    ok "TCC entry reset (you'll be prompted to re-grant on first AX use)"
else
    say "(no existing TCC entry to reset — fine on first install)"
fi

# ------------------------------------------------------------------- #
# 6. 起動 — 必ず .app 経由で
# ------------------------------------------------------------------- #
say "Launching $DEPLOY_DEST …"
# -n: 既存インスタンスがあっても新しく起動 (この時点で既存はいないはずだが保険)
# -F: Finder キャッシュを無視して今の .app を起動
open -n -F "$DEPLOY_DEST"

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
