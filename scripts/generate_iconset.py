#!/usr/bin/env python3
"""Generate macOS .iconset from source icon with transparency + drop shadow."""

import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

REPO = Path(__file__).resolve().parent.parent
SRC = REPO / "assets" / "icons" / "stitch-hero-v2-512.png"
ICONSET = REPO / "build" / "AppIcon.iconset"

SIZES = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

SHADOW_RADIUS = 14
SHADOW_OFFSET_Y = 6
SHADOW_COLOR = (0, 0, 0, 90)
BG_TOLERANCE = 30


def detect_background_mask(img_array: np.ndarray, tolerance: int) -> np.ndarray:
    """Flood-fill from all four corners to find the background region."""
    h, w = img_array.shape[:2]
    visited = np.zeros((h, w), dtype=bool)
    is_bg = np.zeros((h, w), dtype=bool)

    corners = [(0, 0), (0, w - 1), (h - 1, 0), (h - 1, w - 1)]
    corner_colors = [img_array[cy, cx].astype(float) for cy, cx in corners]

    queue = deque()
    for (cy, cx), ref_color in zip(corners, corner_colors):
        if not visited[cy, cx]:
            queue.append((cy, cx, ref_color))
            visited[cy, cx] = True
            is_bg[cy, cx] = True

    while queue:
        y, x, ref = queue.popleft()
        for dy, dx in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not visited[ny, nx]:
                visited[ny, nx] = True
                pixel = img_array[ny, nx].astype(float)
                diff = np.sqrt(np.sum((pixel - ref) ** 2))
                if diff < tolerance:
                    is_bg[ny, nx] = True
                    queue.append((ny, nx, pixel * 0.05 + ref * 0.95))

    return is_bg


def add_shadow(icon_rgba: Image.Image, radius: int, offset_y: int) -> Image.Image:
    """Add drop shadow beneath the icon."""
    w, h = icon_rgba.size
    pad = radius * 3
    canvas_w = w + pad * 2
    canvas_h = h + pad * 2

    shadow = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    shadow_layer = Image.new("RGBA", (w, h), SHADOW_COLOR)
    shadow_layer.putalpha(icon_rgba.getchannel("A"))
    shadow.paste(shadow_layer, (pad, pad + offset_y))

    shadow = shadow.filter(ImageFilter.GaussianBlur(radius))

    shadow.paste(icon_rgba, (pad, pad), icon_rgba)

    return shadow.crop((pad, pad, pad + w, pad + h))


def process(src_path: Path, output_dir: Path) -> None:
    src = Image.open(src_path).convert("RGB")

    work_size = 1024
    src_up = src.resize((work_size, work_size), Image.LANCZOS)
    arr = np.array(src_up)

    print("Detecting background via flood-fill...")
    bg_mask = detect_background_mask(arr, BG_TOLERANCE)

    alpha = np.where(bg_mask, 0, 255).astype(np.uint8)
    alpha_img = Image.fromarray(alpha, "L")
    alpha_img = alpha_img.filter(ImageFilter.GaussianBlur(1.0))

    rgba = src_up.convert("RGBA")
    rgba.putalpha(alpha_img)

    icon_with_shadow = add_shadow(rgba, SHADOW_RADIUS, SHADOW_OFFSET_Y)

    output_dir.mkdir(parents=True, exist_ok=True)

    for filename, px in SIZES:
        resized = icon_with_shadow.resize((px, px), Image.LANCZOS)
        out_path = output_dir / filename
        resized.save(out_path, "PNG")
        print(f"  {filename} ({px}x{px})")

    preview = output_dir / "icon_512x512.png"
    print(f"\nDone. Preview: {preview}")


if __name__ == "__main__":
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else SRC
    out = Path(sys.argv[2]) if len(sys.argv) > 2 else ICONSET
    print(f"Source: {src}")
    print(f"Output: {out}")
    process(src, out)
