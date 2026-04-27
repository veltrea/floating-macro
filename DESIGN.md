# FloatingMacro — Design System

Source: Stitch project [`AI Floating Command Hub`](https://stitch.withgoogle.com/)
(`projects/10891283718675711699`, title: *AI Floating Command Hub*, updated 2026-04-15)

This file follows the convention in CLAUDE.md — it is **reserved for design-system
content only** (colors, typography, components, motion rules), not software specs.
Software specifications live in [`SPEC.md`](SPEC.md).

---

## 1. Creative North Star

**"The Ethereal Command"** — a high-performance macOS utility that bridges
invisible background processes with powerful, tangible control. We move away
from a flat web-app look and lean into a **Native High-End Editorial** aesthetic.

The system is characterized by:

- **Vibrant Glassmorphism** — macOS-native vibrancy (`backdrop-blur`) as a
  structural element, not a gimmick.
- **Intentional Asymmetry** — floating elements with varying container heights
  that disrupt column-based grids to signal modularity.
- **Tonal Depth** — harsh lines replaced by overlapping sheets of varying slate
  and deep-blue tones.
- **High-Contrast Utility** — a dark, professional "Slate" environment combined
  with a vibrant "Electric Purple" AI accent for instantaneous focus.

---

## 2. Colors

Palette engineered for professional focus: deep midnight blues as foundation,
AI-driven purples for action.

### Tonal Foundation (dark mode baseline)

| Token | Hex | Role |
|---|---|---|
| `background` | `#0b1326` | Primary canvas |
| `surface` / `surface_dim` | `#0b1326` | Base-level panels |
| `surface_container_lowest` | `#060e20` | Deeply recessed utility areas |
| `surface_container_low` | `#131b2e` | Slightly recessed container |
| `surface_container` | `#171f33` | Standard component background |
| `surface_container_high` | `#222a3d` | Lifted content |
| `surface_container_highest` | `#2d3449` | Maximum lift |
| `surface_bright` | `#31394d` | Brightest surface (active list row) |

### Foreground & Text

| Token | Hex | Role |
|---|---|---|
| `on_surface` | `#dae2fd` | **Primary text (never pure white)** |
| `on_surface_variant` | `#c6c6cd` | Secondary text |
| `outline` | `#909097` | Outline for accessibility |
| `outline_variant` | `#45464d` | Ghost border at 15% opacity |

### Primary / Secondary

| Token | Hex | Role |
|---|---|---|
| `primary` | `#bec6e0` | Main action button fill |
| `on_primary` | `#283044` | Text on primary |
| `primary_container` | `#0f172a` | Container for primary accents |
| `secondary` | `#b9c7e0` | Secondary accents |
| `secondary_container` | `#3c4a5e` | Secondary button background |

### AI / Tertiary — Electric Purple

| Token | Hex | Role |
|---|---|---|
| `tertiary` | `#ddb7ff` | **AI / intelligence accent** |
| `tertiary_container` | `#270048` | Active AI-state background |
| `on_tertiary` | `#490080` | Text on tertiary |

### Status / Error

| Token | Hex |
|---|---|
| `error` | `#ffb4ab` |
| `on_error` | `#690005` |
| `error_container` | `#93000a` |

**Core design rules**

- **No-Line Rule** — 1px solid borders for sectioning are **strictly prohibited**.
  Define boundaries through shifts in surface containers (e.g., a
  `surface_container_high` card on a `surface` background).
- **Glass & Gradient Rule** — floating interface elements must use semi-transparent
  `surface_variant` with a **20–30px backdrop blur**. Main action buttons may use
  a subtle vertical gradient from `primary` (`#bec6e0`) to `on_primary_container`
  (`#798098`) to add physical soul.

---

## 3. Typography — Inter

Inter is used throughout as a high-performance cross-environment alternative to
SF Pro. Editorial hierarchy with a tool-like restraint.

| Step | Usage | Tracking |
|---|---|---|
| `display-lg / md / sm` | Landing moments, empty-state headers | tight (-2%) |
| `headline-lg / md / sm` | Major section headers (use sparingly) | normal |
| `title-lg / md / sm` | **Workhorse** for panel labels, settings | normal |
| `body-lg / md / sm` | Utility text (`body-md` = 0.875rem standard) | normal |
| `label-md / sm` | Micro-labels, metadata, uppercase-ready | +2% loose |

**Editorial tip**: use `tertiary` text color for a small `Label` next to a
`headline-sm` title — this produces a sophisticated, curated feel.

---

## 4. Elevation & Depth

Hierarchy is conveyed through **Tonal Layering** instead of structural lines.

- **Layering Principle** — depth by stacking surface-containers. A
  `surface_container_lowest` button inside a `surface_container_high` card
  creates a "punched-in" effect.
- **Ambient Shadow** — for floating buttons and detached panels:
  - `box-shadow: 0px 12px 32px rgba(6, 14, 32, 0.4);`
  - Shadow color is derived from `surface_container_lowest` to look like
    natural ambient occlusion.
- **Ghost Border Fallback** — if accessibility requires a border, use
  `outline_variant` (`#45464d`) at **15% opacity**. It should be felt, not seen.
- **Glassmorphism** — all floating menus use `surface_bright` at **80% opacity**
  with a `saturate(180%) blur(20px)` backdrop filter.

---

## 5. Components

### Buttons

| Variant | Background | Text | Radius |
|---|---|---|---|
| Primary | solid `primary` (`#bec6e0`) | `on_primary` (`#283044`) | `md` (0.375rem) |
| Secondary | `secondary_container` | `on_secondary_container` | `md` (0.375rem) |
| **AI Action** | gradient `tertiary` → `on_tertiary_fixed_variant` | `on_tertiary` | `md` |

The AI Action variant is reserved for "Pro" / intelligence-driven triggers.

### Input Fields

- **Base** — `surface_container_highest` background, no border.
- **Focus** — a 2px **Ghost Border** using `tertiary` at 40% opacity plus a
  subtle glow.
- **Layout** — labels are `label-md`, placed 4px above the input, never inside.

### Cards & Lists

- **No dividers.** Use 16–24px vertical padding to separate items.
- **Active state** — change the background of a list row to `surface_bright`
  (instead of adding a border).

### The "Floating" Controller (= FloatingMacro panel itself)

- **Style** — `surface_container_high` at **70% opacity**.
- **Edges** — `xl` roundedness (`0.75rem` / 12px) for a "hardware" feel.
- **Shadows** — Ambient Shadow spec above, to lift significantly off the
  background wallpaper.
- **Content** — groups separate by tonal shift only; no dividers.

### Button (inside the floating controller)

- 12px radius, not 6px
- Background = inherit from group container, active/hover = `surface_bright`
- Emoji iconText aligned to the **tertiary** color when the button represents
  an AI action

---

## 6. Do / Don't

### Do

- Use vertical white space to imply grouping.
- Use `tertiary` (Electric Purple) as a **high-energy indicator** for active AI
  processes or shortcuts.
- Nest containers (`low` inside `high`) to create functional areas.
- Use Inter Medium for `title-sm` to ensure legibility on dark backgrounds.
- Tint all shadows with the background hue.

### Don't

- **Don't** use 100% white text. Use `on_surface` (`#dae2fd`) for a softer,
  premium feel that reduces eye strain.
- **Don't** use standard 1px `#000000` shadows — they look cheap.
- **Don't** use grid-lines or dividers between list items. Trust the spacing
  and tonal shifts.
- **Don't** use sharp corners. Minimum radius for any interactive element is
  `DEFAULT` (`0.25rem`).

---

## 7. Mapping — Stitch is a reference, not a blueprint

**Primary design direction**: follow **macOS native conventions**. The Stitch
document in this file is a *reference dictionary* — we pull from it only when
it adds value that native conventions can't already provide (icon art, an AI
accent, a specific color token). We do **not** wholesale replace SwiftUI /
AppKit defaults, because Apple's defaults already do the heavy lifting for
"feels like a Mac app".

### What we take from Stitch

| Stitch element | Why we take it |
|---|---|
| **App icon** (metallic bezel + purple spark) | Dock / Finder wants a distinctive brand icon. The native SwiftUI can't give us that. → see §8 |
| **AI accent color (Electric Purple `#ddb7ff`)** | Useful as a *per-button* highlight for AI-driven actions. Use it sparingly — only where the user explicitly opts in via `backgroundColor`. |
| **Icon / spark motif** for menu bar template | A distinct shape instead of a generic SF Symbol. |

### What we deliberately do NOT take from Stitch

| Stitch element | Why we keep native |
|---|---|
| Inter font | SF (system font) is what makes things feel Mac-native. Keep `system(...)`. |
| Glassmorphism with 20–30px backdrop blur | Overpowered for a small utility panel. `NSPanel` default + `.hudWindow` style (if wanted) is already the Mac way. |
| `#0b1326` slate background everywhere | `NSColor.windowBackgroundColor` auto-adapts to Dark/Light and respects user preference. Do not hardcode. |
| Ambient shadow `0 12 32 rgba(6,14,32,0.4)` | macOS renders its own window shadow; stacking a custom shadow looks off. |
| 12px hardware-feel corners | Default panel corners are already tuned by AppKit. Do not override. |
| Replace `Divider()` with tonal shifts | Native `Divider()` is the Mac way. Keep it. |
| Replace system accent with tertiary | Users set their accent color in System Settings. Respect it. |

### Rule of thumb

> **If a change requires overriding a default SwiftUI / AppKit behavior,
> question whether it's worth it.** The current "just native parts composed
> together" look is liked — don't erase it.

---

## 8. Bundled icon pack — Lucide (ISC)

FloatingMacro ships with **Lucide** (1695 open-source icons, ISC licensed) in
`Sources/FloatingMacroApp/Resources/lucide/`. Any button definition can
reference them with the `lucide:` prefix:

```json
{ "id": "b1", "label": "Save", "icon": "lucide:save", "action": {...} }
```

SF Symbols are also supported with the `sf:` prefix:

```json
{ "id": "b2", "label": "Command", "icon": "sf:command.square", "action": {...} }
```

### Priority in `IconResolver`

1. `sf:<name>` → Apple SF Symbol (via `NSImage(systemSymbolName:)`)
2. `lucide:<name>` → Bundled Lucide SVG (via `Bundle.module`)
3. `com.xxx.yyy` → macOS app by bundle id (via `NSWorkspace`)
4. Absolute path / `~/` → local image file (PNG/JPEG/SVG/ICNS/...)
5. `.app` path → app bundle icon

### License compliance

- `Resources/lucide/LICENSE` contains the ISC notice — shipped verbatim from
  upstream
- ISC requires **preservation of the copyright notice** only
- Lucide contributors are credited in §9 below

### Rendering

macOS 13+'s `NSImage(contentsOf:)` can render SVG natively. No external
SVG library is required.

## 9. App icon — tentative adoption

**Current tentative icon**: [`assets/icons/stitch-hero-512.png`](assets/icons/stitch-hero-512.png)
(512×512, sourced from Stitch screen `projects/10891283718675711699/screens/99a4601f03d6447ba8abebcf9fba75c0`).

The visual direction is locked: a metallic silver bezel ring with a deep-purple
inset button and an abstract "spark" glyph, glass highlights, slate background.
It embodies the DESIGN.md palette (`tertiary` `#ddb7ff` spark on `surface` slate).

### Still needed from Stitch

1. **1024×1024 hero** — same composition, scaled up, for the official `.icns`
   master. `sips` will down-sample to 512/256/128/64/32/16.
2. **Menu-bar template** — white-only (`#FFFFFF`) extract of just the central
   spark glyph, transparent background, 44×44 px (22 pt @2x), alpha-only
   anti-alias. macOS auto-inverts this for Dark/Light.

### Pipeline once the two above land

```
hero-1024.png → sips -z N N --out icon_<N>x<N>.png    (7 sizes)
             → iconutil -c icns AppIcon.iconset       (Finder / Dock)
template.png → Sources/FloatingMacroApp/Resources/MenuBarIcon.png
              (marked isTemplate = true at runtime)
```

## 10. Credits

FloatingMacro bundles and uses the following third-party assets:

| Asset | Source | License | Location |
|---|---|---|---|
| **Lucide** icon set (1695 icons) | https://lucide.dev | ISC | `Sources/FloatingMacroApp/Resources/lucide/` |
| **SF Symbols** (runtime reference only, not bundled) | Apple | Apple SF Symbols License | System-provided |
| Hero icon art (tentative) | Generated in Stitch (user's own project) | User-owned | `assets/icons/` |

### ISC License (Lucide)

Full text: [`Sources/FloatingMacroApp/Resources/lucide/LICENSE`](Sources/FloatingMacroApp/Resources/lucide/LICENSE)

Summary: permission to use, copy, modify, and distribute is granted provided
the copyright notice and permission notice appear in all copies. No warranty.

## 11. Stitch source reference

Full project JSON was captured at `/tmp/fm_stitch_project.json` at pull-time.
The original Stitch project ID is `projects/10891283718675711699`.

To refresh:

```
mcp__stitch__get_project projects/10891283718675711699
mcp__stitch__list_screens projects/10891283718675711699
mcp__stitch__get_screen  projects/10891283718675711699/screens/aa05b63e1a654793a84abeddc28485f7  # Button Editor
```

The project was created with Stitch's `TEXT_TO_UI_PRO` mode.

---

## 12. Implementation notes (for whoever applies this)

1. **FloatingPanel backdrop** — swap `backgroundColor` to a `NSVisualEffectView`
   backed content view with `.hudWindow`-style blur, then tint it with
   `#222a3d` at 70% opacity.
2. **Rebuild ButtonView** to honor:
   - per-button `backgroundColor` (already supported); fallback = transparent
     against the group tonal layer
   - `cornerRadius = 8` (or 12 for the panel shell)
   - hover = `surface_bright` overlay, not accent opacity
3. **Remove `Divider()`** from `ContentHostView` and rely on padding.
4. **Inter font** — ship as a resource or rely on system Inter availability.
   Fall back to `.system(design: .default)` if missing.
5. **AI-action visual** — Button that invokes an AI-related `text` action
   (detect by content prefix or new field `category: "ai"`) gets a `tertiary`
   accent outline or background tint.
6. **Menu bar icon** — the bundled `command.square` SF Symbol is fine; tint
   with `on_surface` in dark mode.
