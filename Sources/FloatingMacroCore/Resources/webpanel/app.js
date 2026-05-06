// FloatingMacro Web Panel — Phase 5
//
// 動作モデル:
// - HTML はサーバーが SSR して preset 構造を window.__FM_PRESET__ に inline
//   注入してくる。最初の paint で skeleton カードが既に並んでいる。
// - この JS は loaded 後に DOM をスキャンして data-id 属性から button を引き、
//   skeleton を本物に差し替える (画像 src 注入 + click ハンドラ装着)。
// - サーバー側 fetch は **画像のみ**。preset_get ラウンドトリップは無し。

(function () {
  "use strict";

  const TOKEN  = window.__FM_TOKEN__  || "";
  const PRESET = window.__FM_PRESET__ || null;
  const statusEl = document.getElementById("status");

  function setStatus(text, kind) {
    statusEl.textContent = text;
    statusEl.classList.remove("ok", "error");
    if (kind) statusEl.classList.add(kind);
  }

  // ── サイズ算出 (DPR は 2x キャップ) ──
  const EFFECTIVE_DPR = Math.min(window.devicePixelRatio || 1, 2);
  const ICON_BUCKETS  = [64, 96, 128];
  const THUMB_BUCKETS = [256, 384, 512];

  function snapBucket(value, buckets) {
    for (const b of buckets) if (value <= b) return b;
    return buckets[buckets.length - 1];
  }
  function pickIconSize() {
    return snapBucket(Math.ceil(32 * EFFECTIVE_DPR), ICON_BUCKETS);
  }
  function pickThumbSize() {
    const vw = window.innerWidth || 320;
    const cardCSSWidth = Math.max(140, (vw - 32 - 12) / 2);
    return snapBucket(Math.ceil(cardCSSWidth * EFFECTIVE_DPR), THUMB_BUCKETS);
  }

  function iconURL(ref, kind) {
    // kind 別:
    //   - "thumb"     : 写真サムネ。WebP lossy で容量優先。
    //   - "icon"      : 小アイコン (icon/wide グループ)。PNG (alpha 維持 + シャープ)。
    //   - "app-card"  : card 型でアプリアイコンを大きめに出す用。PNG @ DPR×60。
    let size, format;
    if (kind === "thumb") {
      size = pickThumbSize();
      format = "webp";
    } else if (kind === "app-card") {
      // iOS のアプリアイコン表示が 60×60 pt 相当なので、それを 2x で 120,
      // バケットに合わせて 128 にする。PNG なので体積は数 KB。
      size = 128;
      format = "png";
    } else {
      size = pickIconSize();
      format = "png";
    }
    return "/webpanel/icon"
      + "?ref="    + encodeURIComponent(ref)
      + "&token="  + encodeURIComponent(TOKEN)
      + "&size="   + size
      + "&format=" + format;
  }

  function resolveImageRef(button) {
    if (!button) return null;
    if (button.icon) return button.icon;
    const a = button.action;
    if (a && a.type === "launch" && typeof a.target === "string" && a.target) {
      return a.target;
    }
    return null;
  }

  // ── ボタン id → ButtonDefinition の lookup ──
  const buttonsById = new Map();
  if (PRESET && PRESET.groups) {
    for (const g of PRESET.groups) {
      for (const b of g.buttons || []) {
        buttonsById.set(b.id, { button: b, displayType: g.displayType || "icon" });
      }
    }
  }

  // ── 画像差し込み (skeleton → 本物) ──

  /// card 内の thumb div に **写真サムネ** を背景画像として直接セット。
  /// background-size: cover で 16:10 領域を埋める (cover は CSS 側)。
  function attachThumb(thumbEl, ref) {
    const url = iconURL(ref, "thumb");
    thumbEl.style.backgroundImage = "url(" + JSON.stringify(url) + ")";
    // 完了検知用プローブ (load 終了で shimmer 解除)。
    const probe = new Image();
    probe.decoding = "async";
    probe.onload = () => thumbEl.classList.add("loaded");
    probe.onerror = () => thumbEl.classList.add("loaded");
    probe.src = url;
  }

  /// card 型でサムネイル無し + 画像 ref ありのとき。
  /// 元画像のアスペクト比を見て描画方法を決める:
  ///   - **正方形 (0.85–1.15)**: アプリアイコン → 60×60 中央配置 (PNG)
  ///   - **正方形でない**: イラスト/写真として cover 表示 (WebP)
  ///
  /// `icons/` フォルダにアプリ用の正方形アイコンと、参考用イラスト
  /// (横長 / 縦長) の両方が混在しているケースに対応する。サーバー側で判定
  /// すると 1 度余計なメタ取得が要るので、ここではクライアントで naturalSize を見る。
  function attachCardAuto(thumbEl, btnEl, ref) {
    const probeURL = iconURL(ref, "thumb");
    const probe = new Image();
    probe.decoding = "async";
    probe.onload = () => {
      const w = probe.naturalWidth, h = probe.naturalHeight;
      const ratio = (h > 0) ? (w / h) : 1;
      if (ratio >= 0.85 && ratio <= 1.15) {
        // 正方形 → アプリアイコン中央配置。シャープな PNG を別途要求。
        btnEl.classList.add("app-icon-card");
        const img = document.createElement("img");
        img.className = "app-icon-img";
        img.alt = "";
        img.decoding = "async";
        thumbEl.replaceChildren(img);
        img.src = iconURL(ref, "app-card");
      } else {
        // 横長 / 縦長 → 写真サムネ扱い。プローブの URL をそのまま背景に。
        thumbEl.style.backgroundImage = "url(" + JSON.stringify(probeURL) + ")";
      }
      thumbEl.classList.add("loaded");
    };
    probe.onerror = () => thumbEl.classList.add("loaded");
    probe.src = probeURL;
  }

  /// icon 領域 (icon/wide) に <img> を **先に DOM 挿入してから** src をセット。
  /// `loading="lazy"` 付き <img> は DOM 外だと画面外扱いで fetch されない仕様
  /// なので、必ず DOM に入れてから src を渡す。
  function attachIcon(iconEl, ref) {
    const img = document.createElement("img");
    img.className = "icon-img";
    img.alt = "";
    img.decoding = "async";
    // skeleton を即時止めて img を挿入 (背景 shimmer も消える)。
    iconEl.classList.remove("skeleton");
    iconEl.removeAttribute("style");
    iconEl.replaceChildren(img);
    // 挿入後に src を入れることで確実に fetch される。
    img.src = iconURL(ref, "icon");
  }

  // ── click ハンドラ ──

  async function fireButton(el, buttonId) {
    el.classList.remove("success", "failure");
    el.classList.add("firing");
    try {
      const res = await fetch("/webpanel/tools/call", {
        method: "POST",
        headers: {
          "Content-Type":  "application/json",
          "Authorization": "Bearer " + TOKEN,
        },
        body: JSON.stringify({ name: "button_press", arguments: { id: buttonId } }),
      });
      const ok = res.ok;
      el.classList.remove("firing");
      el.classList.add(ok ? "success" : "failure");
      setTimeout(() => el.classList.remove("success", "failure"), 800);
      if (!ok) {
        const text = await res.text();
        console.error("[fm-webpanel] button_press non-2xx", res.status, text);
      }
    } catch (e) {
      el.classList.remove("firing");
      el.classList.add("failure");
      setStatus("送信失敗: " + e.message, "error");
      console.error("[fm-webpanel] button_press failed", e);
      setTimeout(() => el.classList.remove("failure"), 1200);
    }
  }

  // ── 起動: SSR された skeleton を hydrate ──

  function hydrate() {
    if (!TOKEN) {
      setStatus("トークンがありません — QR を再読み込みしてください", "error");
      return;
    }
    if (!PRESET || !PRESET.groups) {
      setStatus("プリセットを読み込めませんでした", "error");
      return;
    }

    const allButtons = document.querySelectorAll("button.btn[data-id]");
    let attached = 0;
    allButtons.forEach(el => {
      const id = el.dataset.id;
      const entry = buttonsById.get(id);
      if (!entry) return;
      const { button, displayType } = entry;

      // クリック装着
      el.addEventListener("click", () => fireButton(el, id));

      // 画像差し込み
      const ref = (displayType === "card")
        ? (button.thumbnail || resolveImageRef(button))
        : resolveImageRef(button);

      if (displayType === "card") {
        if (button.cardThumbnailMode === "fit") el.classList.add("thumb-fit");
        const thumb = el.querySelector(".thumb");
        if (!thumb) { /* skip */ }
        else if (button.thumbnail) {
          attachThumb(thumb, button.thumbnail);
        } else if (ref) {
          // icon フィールドのみ → アスペクト比で自動判別 (正方形なら
          // app-icon-card、横長/縦長ならサムネ cover)。
          attachCardAuto(thumb, el, ref);
        } else {
          thumb.classList.add("loaded"); // ref 無し → shimmer 止め
        }
      } else {
        const icon = el.querySelector(".icon.skeleton");
        if (icon && ref) attachIcon(icon, ref);
      }
      attached++;
    });

    setStatus("接続済み", "ok");
    console.log("[fm-webpanel] hydrate", {
      total:    allButtons.length,
      attached: attached,
      iconSize: pickIconSize(),
      thumbSize: pickThumbSize(),
      dpr:      EFFECTIVE_DPR,
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", hydrate);
  } else {
    hydrate();
  }
})();
