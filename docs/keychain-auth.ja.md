# Keychain 認証のセットアップと動作

対象バージョン: 認証機能実装後（`requireAuth` 対応）

---

## 概要

FloatingMacro は起動時にランダムな Bearer トークンを macOS の Keychain に保存します。
制御 API（ポート 17430）へのリクエストはすべてこのトークンを要求します。
`fmcli token show` で取得したトークンを Claude Code などのツールに渡すことで、
**FloatingMacro だけが許可したツール** だけが API を叩ける状態になります。

---

## 初回セットアップの手順

### 1. config.json を確認する

`requireAuth` がデフォルト `true` になっているはずです。

```json
"controlAPI": {
  "enabled": true,
  "port": 17430,
  "requireAuth": true,
  "testMode": false
}
```

`testMode: true` になっていたら `false` に変えてください（スモークテスト用の設定が残っている場合）。

---

### 2. FloatingMacro を起動する

アプリが起動すると、Keychain にトークンがなければ自動生成して保存します。

**このとき画面に何も出ません。** アプリ自身がトークンを作った場合、自分のアイテムへのアクセスはダイアログなしで完了します。

---

### 3. `fmcli token show` を初めて実行する

```bash
swift run --package-path /path/to/floatingmacro fmcli token show
```

**ここで Keychain アクセスのダイアログが出ます。**

```
fmcli がキーチェーン内の項目 "ControlAPIToken" にアクセスしようとしています。
```

> ダイアログのアプリ名は `fmcli`（バイナリ名）になります。

ボタンが 3 つあります：

| ボタン | 意味 |
|---|---|
| **常に許可** | 以降このダイアログは出ない。**これを選んでください** |
| 許可 | 今回だけ許可。次回またダイアログが出る |
| 拒否 | アクセスを拒否。トークンが取れない |

→ **「常に許可」をクリックします。**

トークンが stdout に出力されます（64文字の hex 文字列）：

```
3f7a2e...（64文字）
```

---

### 4. 逆順の場合（fmcli が先にトークンを作った場合）

`.zshrc` に `fmcli token show` を書いていると、アプリより先にシェルがトークンを生成することがあります。

この場合、FloatingMacro アプリの起動時に Keychain ダイアログが出ます：

```
FloatingMacro がキーチェーン内の項目 "ControlAPIToken" にアクセスしようとしています。
```

同じく **「常に許可」** をクリックします。

---

### 5. `~/.zshrc` にトークン取得を設定する

```bash
# ~/.zshrc に追加
export FLOATINGMACRO_TOKEN=$(swift run --package-path /path/to/floatingmacro fmcli token show)
```

ターミナルを再起動すると `$FLOATINGMACRO_TOKEN` が使えるようになります。

> **注意**: `swift run` はビルドを確認してから起動するため、毎回シェル起動が少し遅くなります。
> ビルド済みバイナリを直接呼ぶ方が速いです：
> ```bash
> export FLOATINGMACRO_TOKEN=$(/path/to/.build/debug/fmcli token show)
> ```

---

### 6. Claude Code の MCP 設定（`~/.claude.json`）

```json
{
  "mcpServers": {
    "floatingmacro": {
      "url": "http://127.0.0.1:17430/mcp",
      "headers": {
        "Authorization": "Bearer ${FLOATINGMACRO_TOKEN}"
      }
    }
  }
}
```

---

## セットアップ後の動作

| 操作 | ダイアログ |
|---|---|
| FloatingMacro 起動 | 出ない（一度「常に許可」済み） |
| `fmcli token show` 実行 | 出ない |
| Claude Code からの API リクエスト | 出ない（Claude Code は Keychain に触らない） |
| トークンを知らない別プロセスが API を叩く | 401 が返るだけ（ダイアログも出ない） |

「常に許可」した記録は **Keychain Access.app** で確認・取り消しできます。

---

## トークンのリセット

トークンが漏洩した、または使い回したくない場合：

```bash
swift run --package-path /path/to/floatingmacro fmcli token reset
```

出力例：
```
New token: 9b4c1a...（新しい64文字）
```

リセット後は FloatingMacro を再起動してください（起動中の場合）。
`~/.claude.json` や `.zshrc` の環境変数は次回シェル起動で自動的に新しいトークンを取得します。

---

## よくあるトラブル

### `fmcli token show` がハングする

Keychain ダイアログが画面の裏に隠れている可能性があります。
Dock や通知センターでダイアログを探して、「常に許可」をクリックしてください。

### API を叩くと 401 が返る

1. `fmcli token show` でトークンを確認する
2. Claude Code の設定（`~/.claude.json`）の `Authorization` ヘッダーと一致しているか確認する
3. FloatingMacro を再起動後にトークンが変わっていないか確認する（変わらないはずですが）

### アプリを再ビルドしたらダイアログがまた出た

`swift run` や Xcode でリビルドするとバイナリのハッシュが変わります。
macOS はバイナリ単位で Keychain アクセスを管理しているため、**リビルドのたびにダイアログが出ます。**

毎回「常に許可」をクリックするか、開発中は `"testMode": true` にして Keychain を使わない運用にしてください。

> コード署名されたリリースビルドでは署名 ID で判定するためリビルドでもダイアログは出ません。

---

## セキュリティの範囲

この認証が守るもの・守らないもの：

| 脅威 | 結果 |
|---|---|
| トークンを知らないプロセスが API を叩く | 401（ブロックされる） |
| `~/.config/` などを覗いてトークンを盗む | 守られる（Keychain は暗号化） |
| 悪意あるアプリが Keychain を読もうとする | ダイアログが出てユーザーが判断できる |
| ユーザーが「許可」してしまった後 | アプリ側ではそれ以上の防御手段なし |

最終的にどのアプリを「常に許可」するかは **ユーザーの判断** に委ねられています。
