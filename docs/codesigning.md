# コード署名とアクセシビリティ権限

## 問題

macOS のアクセシビリティ許可はバイナリのコード署名に紐づく。
`swift build` でリビルドするたびに署名が変わり、macOS が「別のアプリ」と判定して許可がリセットされる。

## 署名の種類

| 方式 | 費用 | 配布 | アクセシビリティ権限の持続 |
|------|------|------|--------------------------|
| アドホック署名 (`-`) | 無料 | 自分のマシンのみ | ビルドごとにリセット |
| Apple Developer ID | 年額 $99 (Apple Developer Program) | Notarize して配布可能 | 署名 ID が同じなら持続 |
| 自己署名証明書 | 無料 | 自分のマシンのみ | 証明書が同じなら持続 |

## 開発中の解決策: 自己署名証明書（無料）

キーチェーンアクセスで自己署名証明書を作り、ビルド後に毎回同じ証明書で署名する。

### 1. 証明書の作成

```bash
# キーチェーンアクセス.app → 証明書アシスタント → 証明書を作成 でも可
# コマンドラインの場合:
cat > /tmp/cert.conf <<EOF
[req]
distinguished_name = req_dn
prompt = no
[req_dn]
CN = FloatingMacro Dev
EOF

# 自己署名証明書を作成してキーチェーンに追加
openssl req -x509 -newkey rsa:2048 -keyout /tmp/fm-key.pem -out /tmp/fm-cert.pem \
  -days 3650 -nodes -config /tmp/cert.conf
security import /tmp/fm-key.pem -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign
security import /tmp/fm-cert.pem -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign
rm /tmp/fm-key.pem /tmp/fm-cert.pem /tmp/cert.conf
```

**より簡単な方法（キーチェーンアクセス GUI）:**

1. キーチェーンアクセス.app を開く
2. メニュー → 証明書アシスタント → 証明書を作成...
3. 名前: `FloatingMacro Dev`、証明書のタイプ: `コード署名`、自己署名ルートを選択
4. 作成をクリック

### 2. ビルド後に署名

```bash
swift build
codesign --force --sign "FloatingMacro Dev" .build/debug/FloatingMacro
```

### 3. 自動化（ビルドスクリプトに組み込む）

```bash
#!/bin/bash
swift build && codesign --force --sign "FloatingMacro Dev" .build/debug/FloatingMacro
```

### 4. アクセシビリティ許可の付与（初回のみ）

署名後のバイナリを一度起動し、システム設定 → プライバシーとセキュリティ → アクセシビリティで許可する。
同じ証明書で署名している限り、リビルドしても許可は維持される。

## リリース配布の場合: Apple Developer ID

Notarization（公証）が必要な場合は Apple Developer Program（年額 $99）に加入する。

1. [developer.apple.com](https://developer.apple.com/programs/) で登録
2. Xcode → Settings → Accounts でサインイン
3. Developer ID Application 証明書を取得
4. 署名 + Notarize:
   ```bash
   codesign --force --sign "Developer ID Application: Your Name (TEAMID)" \
     --options runtime .build/release/FloatingMacro

   # Notarize（zip にして送信）
   ditto -c -k --keepParent .build/release/FloatingMacro.app FM.zip
   xcrun notarytool submit FM.zip --apple-id YOU@EXAMPLE.COM \
     --team-id TEAMID --password APP-SPECIFIC-PASSWORD --wait
   xcrun stapler staple .build/release/FloatingMacro.app
   ```

## 確認コマンド

```bash
# 署名の確認
codesign -dvv .build/debug/FloatingMacro

# アクセシビリティ権限のリセット（トラブル時）
tccutil reset Accessibility
```
