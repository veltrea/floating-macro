# Changelog

**Read this in other languages:** [日本語](CHANGELOG.ja.md)

## v0.16.6 (2026-05-21)

### Bug fix — ACP / LAN server port conflict and zombie listeners

- ACP (for local AI agents) and LAN remote (for tablets) used to share the same port and the same server instance. Split into independent ports with independent instances.
- ACP now always binds to 127.0.0.1:17430 (loopback only), LAN to 0.0.0.0:17431 (anyInterface).
- Fixed a bug where toggling LAN exposure on/off would also drop the ACP connection.
- Fixed a race condition where `stop()` did not wait for completion, leaving the old listener holding the port while the new one fell back to a different port and went zombie. (Added a completion handler.)

### Improvement — Server safety hardening

- Added a re-entrancy guard to `start()` (checks `isRunning`).
- Added a 30-second health check timer that auto-restarts the listener if it dies (up to 3 retries).
- Split the Combine pipeline into ACP and LAN sides so unrelated config changes no longer trigger needless restarts.
- Added `lanPort` field to `ControlAPIConfig` (default port+1 = 17431, configurable in Settings UI).

### Resolved — Text-input buttons becoming unresponsive after long uptime

- Users reported text-input buttons (`CGEvent.post`-based key injection) becoming unresponsive after the app had been running for a while.
- Investigation traced this back to zombie listeners holding onto resources as an indirect cause.
- After applying the ACP / LAN split and the `stop()` race fix above, the issue did not reproduce in overnight soak tests.

## v0.16.5 (2026-05-17)

### Bug fix — Text readability with custom background color in dark mode

- Fixed an issue where enabling dark mode while a panel had a custom background color made SwiftUI text (`Color.primary`) unreadable against the background.
- Solved by measuring custom background luminance (ITU-R BT.709) and forcing the window appearance to `.darkAqua` for dark backgrounds and `.aqua` for light ones.
- When no custom background color is set (system default), `appearance = nil` is restored so it follows system settings.

### Feature — Panel / Settings window snapshot API

- `GET /panel/snapshot?id=<panelId>` — returns the current panel render as a PNG (no Screen Recording permission needed; uses `NSView.cacheDisplay` entirely in-process).
- `GET /settings/snapshot` — returns the Settings window render as a PNG.
- AI agents can now inspect what a panel looks like while operating it.

### Added — AI integration manual (advanced)

- Added `manual/manual-ai-examples.md`. Walks through operating FloatingMacro from Claude Code / Cursor / Gemini CLI with screenshots.

### Improvement — Moved published docs from `docs/` to `manual/`

- Separated internal documents (`docs/`) from public user manuals (`manual/`).
- Updated the `publish-public.sh` whitelist from `docs` to `manual`.

### Improvement — DMG-based distribution

- Added a mechanism in `release.sh` to wrap `.app` into a DMG and attach it to GitHub Releases.
- The DMG bundles `CLAUDE.md` (AI integration guide).

### Bug fix — Version string inconsistencies

- Info.plist, `SystemPrompt.version`, and README.md were still showing 0.16.3 instead of 0.16.5. Fixed.

### Refactor — Externalized connection prompts and quickStart

- Moved the AI integration window's connection prompts (hardcoded strings) into `connectionPrompt` templates in `agent_prompts.json`.
- Moved the `quickStart` array into the same JSON, keeping `SystemPrompt.swift` fallbacks in place.
- Widened the type of `bundledPrompts` from `[String: String]` to `[String: Any]` to handle both strings and arrays uniformly.

## v0.16.4 (2026-05-11)

### Improvement — Reorganized context menus

- Restructured the menu bar icon's right-click menu to a consistent order: most-used (visibility / preset / panel) → settings (edit / opacity) → AI → system → quit.
- Bound `⌘,` to "Edit…" (per macOS convention), and removed the shortcut from "Open Settings Folder".
- Moved "About FloatingMacro" into the system block and removed the separator just before "Quit" for a tighter grouping.
- Removed the Scroll Debug menu item (developer-only feature stripped from the distribution build).

### Improvement — Unified button / group context menus to standard order

- Button right-click: Cut → Copy → Paste → Duplicate → ── → Edit… → Add New Button → ── → Delete.
- Group header right-click: Cut → Copy → Paste → Duplicate → ── → Edit… → Paste Button → ── → Delete.
- Added Cut / Paste (Group) / Duplicate to groups (enables moving groups across panels).
- Added Cut to buttons (enables moving buttons across panels).
- Routed all hardcoded strings through localization keys.

### Removed — Scroll Debug window

- Deleted `ScrollDebugWindow.swift`.
- Removed the 0.3-second debug sampling timer and related properties from `PanelScrollView`.

### Improvement — Button editor image selection and preview overhaul

- Merged icon and thumbnail into a single image field (`icon`). Thumbnail is fully removed from Settings UI, API, copy-paste, and the Web Panel.
- Backward compatibility for existing presets: the JSON decoder detects legacy `thumbnail` keys and maps them to `icon` automatically.
- Renamed "Select Icon" → "Select Image" and "Clear Icon" → "Clear".
- Exclusive control between emoji (iconText) and image (icon): setting one auto-clears the other.
- Fixed a bug where the preview did not refresh after image selection (added `IconLoader` cache invalidation and a SwiftUI redraw counter `iconGeneration`).
- The preview now matches actual panel rendering by showing the right `MacroButtonView` based on the parent group's layout type (icon / wide / card / grid).

### Improvement — Layout switching preview in button editor

- Embedded a layout switcher tab (icon / wide / card / grid) in the button editor that swaps only the preview (does not change group settings immediately).
- When the preview layout differs from the actual group setting, an "Apply to Group" button shows up for explicit propagation.

### Bug fix — Mini icons multiplying per window count

- Fixed a bug where restoring from the docked state created multiple panel windows, causing mini icons to multiply.
- On restore, only the selected panel is now shown.

### Bug fix — Column count selector usability

- Changed the group's column count selector from a Stepper to a dropdown (clearer value range, prevents invalid input).

### Feature — About window

- Added "About FloatingMacro" to the context menu.
- Implemented an About window showing build hash, branch, and build timestamp.
- The build script auto-generates `BuildInfo.generated.swift` to embed build info into the binary.

## v0.16.3 (2026-05-09)

### Improvement — Localization foundation for Control API tool definitions

- Externalized all 50 tools' descriptions and ~70 parameter descriptions into a JSON resource file (`tool_descriptions.json`).
  - Swift code keeps only fallback strings; at runtime, bilingual (Japanese/English) text is loaded from JSON.
  - Implemented with the same pattern as `agent_prompts.json` (Bundle.module + fallback).
- Made the ACP manifest (`ACPManifest.swift`) bilingual: agent description, tool_invocation_format, and agentSummary.
- Made 7 endpoint table entries and `helpTool.description` in SystemPrompt bilingual.
- Fixed 12 hardcoded dialog strings in `ButtonView.swift` to go through `L()` / `L_()` (referencing existing Localizable.strings keys).

## v0.16.2 (2026-05-09)

### Internal refactoring

- Split 5 oversized source files (8,022 lines total) into 28 files organized by responsibility. Largest file shrunk from 2,235 to 778 lines.
  - `ControlHandlers.swift` (2,235 lines) → main + 6 extensions: WebPanel / Panel / Settings / Preset / ButtonGroup / ACP
  - `App.swift` (1,736 lines) → main + ContentHostView extraction + 3 extensions: ContextMenu / Dock / LANBonjour
  - `SettingsDetail.swift` (1,676 lines) → split into ButtonEditor / GroupEditor / MacroStep / KeyRecorders
  - `PresetManager.swift` (1,194 lines) → main + 5 extensions: PresetIO / ExternalRequest / PanelOps / Editing / ImportExecute
  - `SettingsView.swift` (1,181 lines) → split into SecuritySettingsView / SettingsSidebar / PresetReorderSheet / RowDropDelegate
- No changes to the public interface. Smoke-tested (`/ping` `/state` `/preset/list`).

## v0.16.1 (2026-05-09)

### Bug fix

- Fixed an issue where, in card layout, cards with different label line counts did not align their top edges (text area is now fixed-height).

## v0.16.0 (2026-05-09)

### Feature — Grid display type

- Added a `grid` display type to ButtonGroup (Finder / Launchpad-style icon grid).
- Now selectable from 4 types alongside icon (horizontal list), wide (wide cells), and card (gallery).
- Useful for launcher presets where you want app or file icons displayed large.

### Feature — Column count for card/grid

- Added a `columns` property per group (`auto` / `1` / `2` / `3`).
- `auto` is responsive based on minimum cell width (equivalent to CSS Grid's `minmax`); fixed values (1/2/3) override explicitly.
- Ignored for icon / wide layouts (which use list display).

### Feature — Icon size selection

- Icon display size for icon / grid layouts can now be picked from 4 levels (small 16pt / medium 32pt / large 48pt / xlarge 64pt).
- Per-group `iconSize` property.

### Feature — Label visibility toggle

- Added a `showLabels` property for icon / grid layouts.
- Switches between compact (icon only) and labeled (icon + label) display.

### Feature — Multilingual support (English / Japanese)

- The UI now auto-switches between Japanese and English based on macOS language settings.
- Localized across the entire settings screen, context menus, confirmation dialogs, etc.
- 335 translation keys cover both languages.

### Improvement — Separated preset storage locations

- Moved user-authored presets to `~/Documents/FloatingMacro/presets/`.
- Bundled seed presets remain in `~/Library/Application Support/FloatingMacro/presets/`, with copy-on-write to the user side on edit.
- Plays nicer with backups and cloud sync (iCloud Documents, etc.).
- `FLOATINGMACRO_USER_DIR` environment variable can override the user directory (for testing and custom layouts).

### Documentation — Bundled basic manual

- Added `docs/manual-basic.md`, a basic usage manual with screenshots.
- Covers setup examples for major presets (Claude Code / Logic Pro / MidJourney / note hashtags).

### Bug fix — Scroll broken in card/grid display

- Fixed an issue where vertical scrolling stopped working in card/grid views with thumbnails when item count was high, hiding some buttons.
- Replaced the internal `LazyVGrid` of card/grid with the MIT-licensed [WaterfallGrid](https://github.com/paololeonardi/WaterfallGrid) so the scroll region is correctly calculated even for cells with irregular heights.

### Bug fix — Header clipped with long preset names

- Fixed an issue where long preset names pushed both the title text on the left and the icons on the right out of the panel header.
- Released the horizontal anchoring on the Menu label so long preset names truncate with an ellipsis instead.

## v0.15.1 (2026-05-07)

### Bug fix — Dock bar orientation detection

- Fixed an issue where docking a panel near a screen corner produced a horizontal dock bar even when the panel was close to a left/right edge.
- Added an `edge` field to `DockBarPosition` to remember the orientation during drag-to-move.
- On re-dock, the saved orientation is now preferred, eliminating mismatches between custom position and orientation.
- Fixed a bug in `EdgeDetector.nearestEdge` where the distance could go negative if the panel center was outside `visibleFrame`, selecting an unintended edge (added clamping).

## v0.15.0 (2026-05-07)

### Feature — Panel background color customization

- Panel background color is now customizable per preset (`WindowConfig.backgroundColor` stores `#RRGGBB` hex).
- The floating panel's right-click menu "Background Color ▸" lets you pick a preset color or specify a custom one via `NSColorPanel`.
- Added a color picker to the Settings panel tab as well.
- Control API: added `panel_background_color` tool.

### Feature — Dock transition animation

- Added a slide animation to the panel-to-dock-bar transition.
- A rectangular overlay with an accent-colored border slides from the panel position to the dock destination while fading out — visual feedback for the move.

### Feature — Dock bar interaction improvements

- Dock bars can now be moved freely by dragging.
- The dragged position persists across app restarts (stored in `PanelConfig.dockBarPosition`).
- The custom position is preserved on expand → re-dock (the `dockBarPosition` is not cleared on undock).
- The bar is clamped to keep all its edges inside the visible screen area while being dragged.
- Restoring the panel is now done with a double-click (prevents accidental expansion from misclicks).
- Added "Reset Position" for the currently docked bar to the right-click "Panel ▸" menu.
- Added "Gather Dock Bars" at the bottom of the right-click "Panel ▸" menu (clears custom positions for all bars and returns them to auto layout — a rescue operation).

### Feature — Control API

- `panel_reset_dock_position` `{id}`: clears the custom position of a specific bar.
- `panel_gather_dock_bars`: clears custom positions for all bars at once (rescue for bars that went off-screen).

### Bug fix

- × button now collapses to a circular icon, while the yellow button uses Edge Dock — each has a distinct purpose.
- Fixed layout calculation for new dock bars to include not-yet-visible bars in the position computation.

## v0.14.0 (2026-05-06)

Visual expansion roadmap **Phase 3.5 — Dock-to-edge minimization**. Adds a UI for storing the panel as a thin bar at a screen edge.

### Feature — Dock to edge

- On × button press, the panel is stored as a thin bar (`EdgeDockBar`) at the nearest screen edge.
- The bar shows the preset's icon and display name; left-click expands, right-click opens a menu.
- Added a "Dock to Edge ▸" submenu (Left / Right / Top / Bottom) to the menu bar.
- For docked panels, the menu shows "Expand" and "Move to Another Edge ▸".
- When multiple bars share the same edge, they are centered (no overlap).
- Panels in the docked state are restored as `EdgeDockBar` at launch.

### Feature — Control API

- `panel_dock` `{id, edge?}`: docks a panel to a screen edge. `edge` defaults to auto-detection.
- `panel_undock` `{id}`: expands a docked panel.
- Changed `minimizedToEdge` to `dockedEdge` (null or left/right/top/bottom) in `panel_list` responses.

### Data model changes

- `PanelConfig.minimizedToEdge: Bool` → `PanelConfig.dockedEdge: DockEdge?` (type change).
- Legacy JSON (`minimizedToEdge: true`) is automatically migrated to `dockedEdge: .right`.
- Added a new `DockEdge` enum (left/right/top/bottom).

### Tests

- `EdgeDetectorTests` (6 cases): nearest-edge detection.
- `EdgeDockLayoutTests` (7 cases): bar position calculation.
- Updated existing tests to use `dockedEdge` and added 3 legacy migration test cases.
- All 445 tests pass.

## v0.13.1 (2026-05-06)

### Bug fix

- Fixed an issue where switching the card thumbnail display mode (full / crop) in Settings UI did not take effect.

## v0.13.0 (2026-05-06)

Visual expansion roadmap **Phase 5 — Multi-device**. Lets you use phones and tablets on the same Wi-Fi as control surfaces for FloatingMacro. See the Phase 5 chapter of [docs/plans/visual-expansion-roadmap.md](docs/plans/visual-expansion-roadmap.md) for details.

### Feature — LAN exposure mode

Added a `ControlAPIConfig.lanExposureEnabled` toggle. When enabled, the HTTP server's bind scope is widened from `127.0.0.1` to `0.0.0.0`, making it accessible from devices on the same LAN. Authentication uses an ephemeral LAN token that expires on restart; the persistent Bearer token is never exposed to the LAN.

### Feature — Web Panel

The `/webpanel` route serves a mobile-browser panel UI via SSR + HTML/CSS/JS. Button list, group collapse, and action execution work via touch from mobile Safari/Chrome. Auto-detects card / icon-card layout; achieves instant first paint via critical CSS inlining + skeleton.

### Feature — QR / Bonjour / mDNS

Show the panel URL as a QR code from the menu bar's "📱 Send to Device..." or the QR button in the top-right of each floating panel. Just scan with a phone camera to connect instantly. Advertises `_floatingmacro._tcp.` over Bonjour for zero-config discovery from compatible clients.

### Feature — WebP delivery

Introduced libwebp (via SwiftPM, BSD-3 licensed) to encode and serve button thumbnails as WebP. Transfer size is roughly 1/100 of the original PNG. macOS ImageIO only supports WebP decode, so encoding uses libwebp directly.

### Improvement — Parallelism and speed

Implemented per-connection independent queues + a main-thread bypass fast path. Resolved an issue where parallel image fetches from iPhone were being serialized. App Nap suppression keeps response latency low in the background.

### Feature — `preset_get` tool

`preset_get { name }` — read-only access to any non-active preset (the "specify-any" version of `preset_current`).

### Tests

All 421 tests pass (+62 added in Phase 5).

---

## v0.12.0 (2026-05-05)

Visual expansion roadmap **Phase 3 — Multi-panel**. Expands a single floating panel into "multiple independent floating panels." Each panel can show a different preset, and adding / switching / removing can be done uniformly by user, AI, or Settings. See the Phase 3 chapter of [docs/plans/visual-expansion-roadmap.md](docs/plans/visual-expansion-roadmap.md) for details.

### Feature — Simultaneous display of multiple floating panels

Added `AppConfig.panels: [PanelConfig]`. A `PanelConfig` holds a persistent id, preset name, window shape (position / size / opacity), visibility state, and "docked-to-edge" flag.

Legacy v1 format (`activePreset` + single `window`) is automatically migrated by the decoder into a single `PanelConfig` and written back, so existing user config files are not broken. During the migration period, the legacy `activePreset` / `window` fields continue to be written in sync with `panels[0]`, keeping older code paths that still reference them working.

### Feature — Menu bar "Panels" submenu

Added a **"Panels" submenu** to the status bar / mini icon right-click menu.

- "Add New Panel": creates a new window with the same preset as the primary panel.
- Click on each panel name to toggle visibility (with checkmark state).
- When there are 2+ panels, "↳ Close ⋯" lets you delete individually (the last panel cannot be deleted, per Core-side guard).

### Feature — Settings "Panels" tab

Added a **"Panels" tab** to the Settings window. Each panel row shows:

- Preset displayName + current position / size
- Persistent id (truncated) — for reference when using Control API
- Preset switch menu
- Delete button (disabled for the last panel)

### Feature — Control API: panel_* tools

Added 5 tools for controlling multiple panels from AI:

- `panel_list` — returns id / presetName / displayName / visible / window shape for all panels.
- `panel_create` — adds a new panel (presetName required; x/y/width/height/opacity optional).
- `panel_close` — closes and deletes the panel with the given id (the last one is rejected).
- `panel_show` — orderFront for the given id (expands from mini icon if collapsed).
- `panel_hide` — orderOut for the given id.

Existing `window_*` tools are marked "DEPRECATED: prefer panel_*" and re-targeted to operate on the primary panel (`panels[0]`). They continue to work for backward compatibility, but new AI integration code should use `panel_*`.

### Feature — Control API: full panel control with id (Phase 3.6)

Added 4 tools to **operate the multi-panel system from AI by specifying id**, introduced in Phase 3. Users who have difficulty with mouse/trackpad drag operations can now complete layout changes via natural-language instructions ("move the top-right panel to the bottom-left", "expand the Claude Code panel to fill the right half of the screen", etc.).

- `panel_move` `{id, x, y}` — moves the specified panel to absolute coordinates.
- `panel_resize` `{id, width, height}` — resizes (clamped to min 120×80).
- `panel_opacity` `{id, opacity}` — sets opacity (clamped to [0.25, 1.0]).
- `panel_set_preset` `{id, presetName}` — switches the preset shown by that panel.

All changes persist to `config.json` and survive restarts. The Control API dispatch is a thin layer on top of the pure functions (`AppConfig.updatingPanelFrame` / `updatingPanelOpacity` / `settingPanelPreset`) already introduced in Phase 3 stage 2A.

### Internal refactor — PanelManager and reconcile sink

Added a `PanelManager` class that manages multiple NSWindows by id. Replaces the singular `panel` / `miniIcon` fields in `AppDelegate` and encapsulates the `floatingPanelWantsCollapse` notification subscription.

`AppDelegate` watches `PresetManager.$appConfig.panels` via a Combine sink and automatically calls `PanelManager.openNew` / `close` on add/remove — a **reconcile** mechanism. This unifies NSWindow creation/destruction whether the panel is operated via the menu bar, Settings, or Control API.

### Feature — `PresetManager.loadedPresets` multi-preset cache

Added `@Published var loadedPresets: [String: Preset]` so that all panels re-render reactively even when each shows a different preset. `preset(named:)` loads from disk and caches; `panelPreset(forPanelID:)` is a convenience getter.

`switchPanelPreset(panelID:to:)` lets you switch just one panel's preset. Switching the primary panel also auto-syncs the legacy `activePreset` and the edit target `currentPreset`.

## v0.11.0 (2026-05-04)

Visual expansion roadmap **Phase 2 — Expressive expansion**. Foundation for evolving from a "panel of icons" into a "panel for a specific purpose": group-level display types, thumbnails, and state feedback. See the Phase 2 chapter of [docs/plans/visual-expansion-roadmap.md](docs/plans/visual-expansion-roadmap.md) for details.

### Feature — Group display types (icon / wide / card)

Added `ButtonGroup.displayType` so each group can pick from 3 rendering styles.

- **icon (default)**: existing small icon + label. Compact use; preserves prior behavior.
- **wide**: full-width, large-icon + label-centric horizontal cells. For long titles or visibility-focused buttons.
- **card**: thumbnail + title in a 2-column grid. For prompt galleries (Midjourney, etc.).

Added a segmented picker for display type in the Settings group editor. In Control API, controllable via `displayType` on `group_add` / `group_update`. For backward compatibility, existing preset JSON missing the field is auto-loaded as `icon`, and `displayType=icon` is not written on encode.

### Feature — Thumbnail images (`ButtonDefinition.thumbnail`)

Added a `thumbnail` field to hold the large image used by the card type. Added a "Thumbnail" input + file picker + preview frame to the button editor. The save convention `presets/<name>/images/<button-id>.{ext}` is provided via `IconAssetSaver.saveThumbnail` / `imagesDirectory(presetName:)`. Phase 4 (AI image generation) is built on this same path.

### UI improvement — Refreshed editor icon / thumbnail fields into DnD zones

Replaced the text-path inputs for "Icon" and "Thumbnail" in the button / group editor with **visual DnD zones** (`ImageDropZone`). Empty: dotted border + SF Symbol + guidance. With image / emoji: preview. While dragging over: feedback with accent-color border. Clicking opens `NSOpenPanel`, providing a fallback for keyboard users and users who can't drag.

### UI improvement — Removed hardcoded list from app icon picker; unified Launchpad-style

Rewrote the app icon picker sheet (`AppIconPicker`) used in Settings. The old implementation listed a **hardcoded bundle id list + 4-genre categorization** via `AppIconCatalog`, so apps not in the list never showed up as candidates. The new implementation recursively lists installed `.app`s via `FileSystemAppListProvider` and shows them in the same Launchpad-style grid (sharing `AppGridCell`) as `AppLauncherPickerSheet`. Bundle ID search continues to work. `AppIconCatalog.swift` was removed.

### Feature — Seed preset "MidJourney Prompt Gallery"

A bundled example combining the card display type with the `appendMode` of the `text` action: `midjourney-gallery`. Press cards in the order "style → pose → outfit → background", and fragments are concatenated into the clipboard; the final `Cmd+V` lands in Discord. Works even without thumbnails set, falling back to emoji.

### Wording — Renamed seed preset "♿ Accessibility" to "⏻ Power & Lock"

The label "Accessibility" was hard for both target users (gaze-input / Switch Control users) and non-target users to parse intent from, and the ♿ emoji had the side effect of being misread as a "color vision / low vision palette preset." Renamed to `⏻ Power & Lock` based on the contents (screen lock / sleep / restart / force quit / etc.), with the explanation of the target audience kept in the preset memo. The internal `name` (= filename) remains `accessibility` to respect existing user edits.

### Feature — State feedback indicator

Added a border-color animation on button press (in-progress = yellow, success = green for 1 second). Since actions are currently fire-and-forget, this is a lightweight "pressed = success" implementation; failure (red) display will be wired up after we sort out the return value of `executeButton`. Feedback also fires after going through a confirmation dialog.

### Bug fix — `applyPatch` passes through confirm / thumbnail

Fixed an existing bug where the Settings "Confirm before run" toggle was not being saved (`applyPatch` was not passing the confirm fields to `updateButton`). The Phase 2 `thumbnail` is now passed through the same route.

### Control API changes

- `group_add` / `group_update`: accept `displayType` (`icon` | `wide` | `card`).
- `button_add` / `button_update`: accept `thumbnail` (absolute or relative path; null to clear).
- Backward compatibility of existing tools is preserved. Behavior when the field is absent is unchanged.

### Version

Bumped Info.plist `CFBundleShortVersionString` to `0.11.0` and `CFBundleVersion` to `19`. `SystemPrompt.version` synced. All 317 tests pass.

## v0.10.6 (2026-05-04)

Finishing touches on the app picker UI introduced in v0.10.5, plus internal test stabilization. No feature additions — just visual polish and backstage tweaks.

### UI improvement — Reworked app picker into Launchpad-style grid

Restructured the "Add from app…" sheet from a **list + right-side preview panel** to a **Launchpad-style grid**. Each cell shows an icon and app name. Single-click selects; double-click (or the "Add" button) adds immediately. The selected app's bundle id is shown compactly in the footer; the separate preview panel was removed.

- Cell size 96px, 8–9 columns in `LazyVGrid`. Sheet size grew from 640×500 to 880×620.
- Because of `LazyVGrid`, off-screen cells don't trigger icon extraction (the design assumes prewarm cache at launch).
- Per-cell async loadIcon reuses the cascade (cache → ImageIO → NSWorkspace) and `IconContentValidator` from v0.10.5.

### Bug fix — AppIconCache mtime comparison with tolerance

The mtime written via `setAttributes(.modificationDate:)` and read back via `attributesOfItem` ends up with nanosecond-order error due to APFS sub-second precision truncation and clock jitter. A naive `cached >= app` comparison flagged this jitter as "app updated" and invalidated the cache, making `testDiskCachePromotesToMemoryAcrossInstances` flaky. Fixed `get()` / `contains()` to treat differences within 1.0 second as the same generation via `mtimeStillValid(cached:app:)`.

### Test fix — Updated default preset expectations in ConfigIOTests

Updated the expected first-button id in `testWriteDefaultConfigCreatesConfigAndDefaultPreset` to match the current default preset (`btn-ai-copy-prompt`).

### Version

Bumped Info.plist `CFBundleShortVersionString` to `0.10.6` and `CFBundleVersion` to `18`. `SystemPrompt.version` synced.

## v0.10.5 (2026-05-03)

Visual expansion roadmap Phase 1.5. Tackles the "AppKit-dependent code is untestable" wall found in Phase 1, and complements the DnD-only path for adding apps. See the Phase 1.5 chapter of [docs/plans/visual-expansion-roadmap.md](docs/plans/visual-expansion-roadmap.md) for details.

### Feature — "Add from app…" picker in Settings

Added a **"Add from app…"** button next to "Add Button" in the button editor tab. Lists `.app`s under `/Applications` / `/System/Applications` / `~/Applications`, with search → select → add as a launch button. A parallel addition path to DnD. Completes via keyboard alone, also serving as an alternative for users for whom mouse-dragging is a burden.

- Search targets both app name and Bundle ID (substring, case-insensitive).
- Async icon extraction for the selected app's icon, displayed as preview (does not block the UI thread).
- Double-click / Enter adds immediately. If the same Bundle ID exists in multiple roots, the first found is kept (`Applications` → `System/Applications` → `~/Applications` order).
- Shares the exact same Core logic (`AppEntryResolver` + `IconAssetSaver`) as DnD; the added button has a `launch` action with the bundle id as target.

### Architecture — Icon extraction cascade design

App icon extraction is composed as a 2-tier cascade:

1. **Direct `.icns` reading with ImageIO** (Foundation-only, ms-order, AppKit-independent) — covers traditional apps (Calculator / Slack / VS Code / etc.) fast.
2. **`NSWorkspace.shared.icon(forFile:)`** (AppKit, community standard) — rescues Catalyst / modern apps like UTM (Assets.car-only) or Books (empty .icns placeholder).

Both are positioned as primary paths: if the upper path succeeds, use it; otherwise fall through. The underlying design principle is "graphics / Quick Look-class OS APIs are volatile, but long-lived APIs like `ImageIO` / `CoreGraphics` / `NSWorkspace.icon` are stable" (see memory `feedback_prefer_foundation_over_gui_apis`). NSWorkspace depends on AppKit, but it has been a stable API since macOS 10.0, and the community standard is `NSWorkspace.icon(forFile:)` (orchetect's Gist, etc.).

- The originally considered `qlmanage`-based path was confirmed in `scripts/spikes/qlmanage-pipe-spike/` to cause **a fatal 20-second hang against Calculator.app** (Quick Look daemon problem, not resolved by daemon restart) → rejected.
- ImageIO fetches Calculator / Slack / VS Code in 3–9ms, Foundation-only.
- NSWorkspace depends on AppKit but is contained in the UI layer (`FloatingMacroApp/Settings/NSWorkspaceIconFallback.swift`), keeping Core pure.
- An async version (`Task.detached` + `Task.checkCancellation`) is also provided so the UI doesn't stall.
- Moved `PanelDropHandler` (DnD receiver) onto Core logic; the remaining AppKit dependency is just the NSAlert confirmation dialog — resolves the Phase 1 P1-12 "DnD button-creation is E2E-untestable" issue.

### Feature — Content inspection and auto-repair loop

Cases exist in reality (e.g., Books.app) where the `.icns` file itself exists but **all representations are fully transparent (`alpha=0`, `RGB=0`)** — empty placeholders Apple left when going Catalyst. ImageIO treats these as "success" and returns a 460-byte empty PNG, so PNG byte size alone cannot distinguish them. Added `IconContentValidator` to Core that **inspects content at the pixel level** and integrates it into each stage of the extraction path:

- `IconContentValidator.hasMeaningfulContent(pngData:)` — decode via `CGImageSource` → expand to RGBA 8bit array → early-return true on the first pixel with `alpha > 8` or `max(R,G,B) > 8`. Normal icons exit the loop within a few pixels, so it's light.
- Auto-repair loop: `AppIconPrewarmer` runs the validator at each step of the "existing cache → ImageIO → NSWorkspace" cascade. Empty PNGs (from thin `.icns`) are rejected by the validator even if cached, falling through to the next stage → NSWorkspace pulls the correct icon and overwrites the cache.
- Raised the priority of launch-time prewarm from `.background` to `.utility` so prewarm completes within 30–60 seconds of launch. Real-device verification confirmed Books self-heals from `460 bytes → 337 KB`.

### Feature — Icon cache and background pre-caching

Like Finder / Dock / Launchpad, app icon retrieval is covered by a **two-stage cache (memory + disk)**, with all `/Applications` apps pre-extracted in the background at launch. So when adding apps via the app picker or DnD, the icon shows "the instant" you pick.

- Disk cache: `~/Library/Caches/FloatingMacro/AppIcons/<bundleId>.png`, with file mtime aligned to app mtime. Re-extracts automatically when an app is updated.
- Memory cache: thread-safe via actor, consistent across simultaneous Picker / DnD operations.
- Background pre-caching: started from `applicationDidFinishLaunching` via `Task.detached(priority: .background)`, parallelism 4, doesn't get in the UI's way.
- Cascade: ImageIO (Foundation, ms-order) → NSWorkspace (AppKit, rescues Assets.car-only apps); successful result is cached.
- Both AppLauncherPickerSheet and PanelDropHandler reference the cache, so a disk cache hit on selection means immediate display / immediate add.

### Feature — Support for UTM and other Assets.car-only modern apps

Modern SwiftUI apps like UTM ship `Assets.car` only, without `.icns` under `Contents/Resources/`. ImageIO direct read can't fetch these, so an **`NSWorkspace.shared.icon(forFile:)` fallback** was added at the UI layer (`FloatingMacroApp`). NSWorkspace is Apple's long-lived API (since 10.0) and internally resolves Assets.car. Core stays Foundation + ImageIO only; AppKit dependency is contained in the UI layer.

### New in Core

- `FloatingMacroCore/Icons/ImageIOIconExtractor.swift` — direct `.icns` read producing PNG of the app icon (sync + async).
- `FloatingMacroCore/Apps/AppEntry.swift` — pure data of app info (URL / displayName / bundleIdentifier).
- `FloatingMacroCore/Apps/AppEntryResolver.swift` — `.app` URL → `AppEntry` (direct Info.plist read, no `Bundle(url:)` for lightness).
- `FloatingMacroCore/Apps/AppListProvider.swift` — enumeration of `/Applications` etc., Bundle ID dedup, sort by displayName.
- `FloatingMacroCore/Apps/AppDropClassifier.swift` — classification of DnD URLs (`.app` / file / folder), works with AppEntryResolver.
- `FloatingMacroCore/Apps/IconAssetSaver.swift` — PNG save under preset and save-path computation. With `applicationSupportDirectory:` override, tests can write to a temp directory.
- `FloatingMacroCore/Apps/AppIconCache.swift` — actor-based memory + disk two-stage cache. Cache invalidation by app mtime comparison; lightweight hit check via `contains()`.
- `FloatingMacroCore/Apps/AppIconPrewarmer.swift` — parallel prewarm implementation. At each stage, runs through `IconContentValidator` to cache only "icons with content" — an auto-repair loop. NSWorkspace fallback is received as a closure so AppKit isn't pulled into Core.
- `FloatingMacroCore/Icons/IconContentValidator.swift` — PNG bytes / CGImage content inspection (alpha and RGB pixel walk, early return for lightness).

### New in App layer

- `FloatingMacroApp/Settings/NSWorkspaceIconFallback.swift` — Assets.car-only app rescue; AppKit dependency is contained here.
- `FloatingMacroApp/Settings/AppLauncherPickerSheet.swift` — app picker UI (search, async preview, cache reference).

### Test coverage

Added **46 unit tests** across Phase 1.5 to `FloatingMacroCoreTests` (ImageIO 5, AppEntryResolver 7, FileSystemAppListProvider 7, AppDropClassifier 6, IconAssetSaver 4, AppIconCache 6, AppIconPrewarmer 3, IconContentValidator 8). Stub `.app`s are dynamically generated in tests as fixtures; real-environment Calculator.app / Slack.app / Books.app use XCTSkip as fallback. The case where the validator rejects Books's empty `.icns` placeholder is also covered by real-environment tests.

### Verification spike

Added `scripts/spikes/qlmanage-pipe-spike/`. Compares 4 qlmanage patterns (anti-pattern / null device / readabilityHandler / background readToEnd) with the ImageIO direct-read pattern. Kept for future reference when revisiting "can we use qlmanage after all?".

### Version

Bumped Info.plist `CFBundleShortVersionString` to `0.10.5` and `CFBundleVersion` to `17`. `SystemPrompt.version` synced.

## v0.10.0 (2026-05-03)

Visual expansion roadmap Phase 1. The first step of staged expansion toward Stream Deck / prompt gallery / multi-device support. See [docs/plans/visual-expansion-roadmap.md](docs/plans/visual-expansion-roadmap.md) for details.

### Feature — "Append mode (prompt builder)" for the text action

Added `appendMode: Bool` to `Action.text`. When ON, pressing the button **concatenates `content` to the end of the current clipboard** without pasting. Aimed at use cases like Midjourney where **prompt fragments** like style, pose, and outfit are held in separate buttons, and the desired combination is stacked by clicking, then pasted manually with Cmd+V at the end.

- A new **"Append Mode (Prompt Builder)"** checkbox is placed right below "Paste Text" in the button editor.
- In append mode, the `restoreClipboard` flag is ignored (to keep the concatenated state).
- No separator is inserted (the caller controls it by including e.g. `", "` in content. Midjourney uses comma separation; free-form text uses space; etc. — varies per use).
- Control API: added `appendMode` to the inputSchema of the `text` action. Can be set in a single request from AI via `button_add`.
- Data backward compatibility: existing preset JSON without `appendMode` loads fine (default false). On save, the key itself is omitted from JSON when `appendMode=false`.

### Feature — Drag & drop onto the floating panel to create buttons

**Dropping an app (`.app`) or file / folder from Finder onto the floating panel auto-creates a launch button**. An improvement aimed at the Stream Deck-level entry bar.

- Dropping a `.app` → creates a `launch` button with the resolved bundle id. The label is the app name; tooltip is `app name (com.example.bundleid)`.
- Dropping a file / folder → creates a `launch` button holding the absolute path. The label is the file name.
- Icons are auto-extracted via `NSWorkspace.icon(forFile:)` and saved as 64×64 PNG to `~/Library/Application Support/FloatingMacro/presets/<name>/icons/<button-id>.png`. Button creation continues even if extraction fails (emoji fallback).
- A confirmation dialog "Add N items to group ○○" is shown before bulk registration.
- Added to the first group of the current preset. If no group exists, a "Launcher" group is auto-created.
- Supports simultaneous drop of multiple items.
- While dragging, the panel shows an **accent-colored thick border** as visual feedback.

### Version

Bumped Info.plist `CFBundleShortVersionString` to `0.10.0` and `CFBundleVersion` to `16`. `SystemPrompt.version` synced.

## v0.9.3 (2026-05-03)

Diff from v0.9.2. Fixes a bug where special key settings in the button editor UI weren't applied, plus a major upgrade to the `fm-test-target` harness that covers key/text auto-verification.

### Bug fix — Shortcut key button's type indicator did not follow

In the button editor panel, even after switching to the "key" segment and selecting a special key (Delete / arrows / Tab / etc.), the type indicator in the upper right stayed at `text`. Unless the explicit "Enable this key" button was pressed, it was saved and handled as a text action. Fixed.

After the fix, the moment the key field is filled (by the key recorder button / "Special Key…" menu / manual input), `actionType` auto-promotes to `key` and the indicator switches accordingly. Same applies when a combo is injected via the external API (`externalKeyComboRequest`).

### Development infrastructure — `fm-test-target` and `text_inject_e2e.sh` verification upgrade

Major upgrade to the E2E harness that verifies "did text / key-action actually reach the target app" via the actual artifact rather than logs. Significantly widens the regression detection net.

- **Added `/selection` endpoint**: returns NSTextView's `selectedRange` (location + length) as JSON. Lets you quantitatively confirm effects of arrow keys / Cmd+A / etc.
- **Visible caret**: `VisibleCaretTextView` subclass draws the insertion point as a 4px-thick red bar. Cursor position is visually verifiable in screenshot reviews.
- **Visible key event log**: bottom half of the test app instantly displays every keyDown as `[ms] kc=N mods=⌘⌥⌃⇧ chars="x" name=Delete`.
- **3-axis verification in `text_inject_e2e.sh`**: for each key case, asserts (1) keyDown arrived, (2) result text matches expectation, (3) selection range is at the intended position, all at once.
- **Auto-screenshots**: at each case completion, saves PNG to `/tmp/fm-test-screens/<timestamp>/`. Foundation for post-hoc review of UI anomalies (e.g., dropdown position drift).
- **Added verification cases**: delete / tab / return / left arrow / down arrow / cmd+A — 6 cases. With pre-paste seed text, so it pushes into "did the special key really get processed as an editor operation?".
- **Fixed test-infrastructure bugs**: fixed a bug where `osa_set_clipboard`'s bash here-string was appending a trailing `\n` (causing pre-text "hi" to become "hi\n" in clipboard, shifting all selection assertions by +1). Also added a sentinel `X` to `target_text` to avoid bash's `$(...)` trailing newline stripping.

### Feature — Auto-distribution from a public preset collection

On first launch, after copying the 7 bundled seed presets to the user folder, fetch the `index.json` of the [veltrea/floating-macro-preset](https://github.com/veltrea/floating-macro-preset) repository in the background, and for IDs listed in `defaults`, overwrite with the latest version from GitHub. If there's no network or fetch fails, the bundled version stays in place, so behavior does not regress. No UI surface changes (a `seedInstalled=true` flag in config prevents re-runs).

- `PresetCatalogClient` (Core new): a read-only client that fetches `index.json` and individual preset JSON from `https://raw.githubusercontent.com/veltrea/floating-macro-preset/main/`. 5-second default timeout, swappable via `FLOATINGMACRO_PRESET_CATALOG_URL` env var.
- Added `SeedPresetInstaller.refreshFromCatalog()`: fetches index → fetches each `default` in order → overwrites via savePreset. Best-effort: one failure doesn't affect others.
- `PresetManager.installSeedPresetsIfNeeded()`: runs the above refresh once on a background queue after bundled install.

### Feature — Per-button "Confirm before run"

Added **per-button confirmation dialogs**. A guard against one-click accidental firing of irreversible operations like restart / shutdown. For gaze-input or Switch Control users, this is "a safety net for misclicks"; for AI-driven automation, it's "a safety valve that forces a final human confirmation".

- A **"Confirm Before Run"** section is added right below "Tooltip" in the button editor. With the checkbox ON, a confirmation dialog intervenes before execution.
- Text written in "Confirmation Message" is shown in the dialog body (empty falls back to "This operation will be executed." or "This operation cannot be undone." auto-display).
- With **"Destructive Operation"** ON, the dialog's **"Execute" button becomes red destructive style**. Intended for operations that cannot be undone like restart / shutdown.
- The default button is fixed to Cancel side. Prevents accidental firing via Return key or gaze dwell.
- On button duplication (context menu "Duplicate" or group duplication), the confirm settings are copied along. The safety mechanism doesn't disappear in the copy.

Data model: added 3 fields to `ButtonDefinition`: `confirm: Bool` / `confirmMessage: String?` / `confirmDestructive: Bool`. Backward compatibility: existing preset JSON without these 3 keys loads normally (default no confirm). When confirm is OFF, `confirmMessage` and `confirmDestructive` are normalized on save (no leftover data lingers in files).

Control API: added `confirm` / `confirmMessage` / `confirmDestructive` to `button_add` / `button_update` inputSchema. AI can also set all in a single request. `button_update` accepts `confirmMessage: null` to clear, `confirm: true/false` to toggle ON/OFF.

Use cases: guard against gaze-input users accidentally firing "Restart" / "Shutdown" / "Log Out" / "Session-killing shell commands". Also usable as a **final human confirmation** for buttons intended to be fired via `button_press` from AI (e.g., just before important mass operations).

### Feature — Seed preset "♿ Accessibility"

Added the `♿ Accessibility` preset as seed. For users who use the persistent panel via gaze input / Switch Control / voice operation, this turns hard-to-press multi-finger combos and power operations into single buttons.

7 buttons:

- **Lock / Sleep**: screen lock (`ctrl+cmd+q`) / sleep (`pmset sleepnow`) / display off (`pmset displaysleepnow`).
- **Power (with confirmation)**: restart / shutdown / log out — all with confirmation dialog + red destructive style, executed via `osascript`.
- **Emergency**: Force Quit dialog (`cmd+option+esc`) — terminates frozen apps via the Force Quit list.

Note: On first press of restart / shutdown / log out, macOS shows a one-time "Allow FloatingMacro to control System Events?" dialog → must be allowed for practical use (noted in the preset memo).

Added `SeedPresetInstallerTests` as regression coverage: verifies all bundled seeds decode as `Preset`, that destructive operations (restart / shutdown / log out) have `confirm + confirmDestructive`, and conversely that low-risk operations (screen lock / sleep / Force Quit dialog) do not have `confirm`.

## v0.9.2 (2026-05-02)

Diff from v0.9.1. Fixes the issue where special keys like Delete or arrow keys could not be registered in the "Shortcut Key" action.

### Bug fix — Special keys couldn't be registered

The old UI was designed to **type the key name into a TextField**, which had the following problems:

- The hint text only mentioned "a–z / 0–9 / space / return / esc / etc.", giving the user no way to know that supported keys included `delete` `left` `right` `up` `down` `home` `end` `pageup` `pagedown` `forwarddelete` `f1`–`f20` (the `KeyCombo` parser itself supported them from the start).
- Even if the user knew the key name, they couldn't **physically press the key** to register it: pressing Delete with the TextField focused just deletes characters; pressing arrow keys just moves the caret. It's an unergonomic "type the key name" UX.

### Feature — Key recorder button and special-key dropdown

Added 2 input-assist UIs to both the button editor and the macro step editor row:

- ⌨ **"Press a key to record" button**: enters record mode, absorbing the next 1 key via `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` (returning nil consumes the event so e.g. the recorded Delete doesn't affect other fields). Captures modifier keys (cmd/shift/option/ctrl) and base key simultaneously and reflects them into the existing toggles + text field. Esc alone cancels recording.
- 📋 **"Special Key…" pulldown**: pick from Delete / Forward Delete / 4 arrows / Home / End / Page Up/Down / Return / Tab / Space / Escape / F1–F20 and inject into `baseKey`. Alternative for situations where keyboard operation is difficult.

Hint text also updated to "a–z / 0–9 / arrows / Delete / F1– / etc.". For macro step rows (type=key), provided derived components (`ComboKeyRecorderButton` / `ComboSpecialKeyMenu`) that write directly to the combo string, placed as compact icon buttons.

### Control API extension — Discover special keys from ACP too

Just giving the UI the special key list still means AI has to memorize which key names are usable. To fix this, a canonical catalog now lives in Core and is fetchable from ACP.

- Added `list_key_codes` tool (GET `/key-codes`): returns `modifiers` / `modifierAliases` / `specialKeys` (name + label) / `functionKeys` / `keyAliases` / `examples` / `notes` in one call. Intended for scenarios where AI "doesn't remember the special-key name" or "wants to show the user a picker".
- Updated `settings_set_key_combo` description: explicitly lists special keys (delete, forwarddelete, arrows, home/end, pageup/pagedown, return, tab, space, escape, f1-f20) and adds guidance toward `list_key_codes`.
- Added discoverable static catalogs (`specialKeys`, `functionKeys`, `modifierNames`, `modifierAliases`, `keyAliases`) to `KeyCombo` (Core). The Settings UI's `KeyNameLookup.specialKeys` is also synthesized from this catalog, resolving the duplicated maintenance.

### Internal additions

- Added `KeyNameLookup` enum: forward-lookup from virtual key code → key name understood by the KeyCombo parser (key-capture only). The list data itself references `KeyCombo.specialKeys` / `functionKeys`.
- `KeyCombo.keyCodeMap` was left untouched (already had sufficient coverage).

## v0.9.1 (2026-05-02)

Diff from v0.8. Added per-preset memo functionality. You can now leave a note about "what to check before using this preset".

### Feature — Per-preset memo

- Added a `memo: String?` field to the `Preset` struct. Stores a free-form memo for the entire preset (backward compatible: existing JSON without the `memo` key works fine).
- Added a **collapsible memo block** to the top of the floating panel. Drawn only for presets with a memo set; collapsed by default with a single-line preview next to the title; click to expand to full text (yellow background makes it obvious it's a memo).
- Added a **memo edit TextEditor** to the Settings window sidebar (just below preset selection). Multi-line input, character count display; edits are saved to disk instantly.
- Use cases: leave behind **prerequisites you tend to forget over time** like "Studio One Pro preset → set F1–F12 to standard function keys in OS settings" or "AI preset → bring target app to front before pressing".

### Control API extension — Read/write memo from ACP too

- Added `memo` to `preset_create` inputSchema (lets you create a preset and write a memo simultaneously).
- Extended `preset_rename` to behave like `preset_update` (tool name kept for compatibility). Can optionally update both `displayName` and `memo`. `memo: ""` clears the memo.
- Added `memo` to the `GET /state` response (returns the memo of the currently active preset).
- `GET /preset/current` / `preset_export` automatically include memo via the Preset struct's Codable.

### System prompt

- Added a **"Preset Memo (Leave Prerequisites)"** section to the `agent_prompts.json` normal mode. Encourages AI to suggest and fill in a memo when creating a preset.

### Bundled presets

- Added memo examples to the `logic-pro` and `midjourney` seed presets (function key setup / clipboard overwrite warnings, etc.).

## v0.8 (2026-05-02)

Diff from v0.7. Structural fix for the Accessibility permission flow bug, and lets users adjust preset ordering.

### Bug fix — Eradicated infinite loop in Accessibility permission dialog

- Removed the behavior of auto-invoking `tccutil reset` at launch (it was the cause: macOS Sequoia's TCC daemon spawns an OS permission dialog when it detects an "AX-using process without a TCC entry," and this collides with our `prompt: true` call, double-queueing the permission request and causing the dialog to loop infinitely).
- Launch-time `AXIsProcessTrustedWithOptions(prompt: true)` is now called only when launched via the `--prompt-accessibility` argument (called only in a new process self-restarted by the [Repair] button).
- Removed our own 0.8-second fallback `openSystemPreferences()` and the "Almost done!" NSAlert (they competed with OS dialog buttons for focus, leaving them unresponsive, and the 3-windows-at-once chaos was just confusing).
- Result: post-rebuild normal launch only shows a badge notification; the user pressing [Repair] makes the OS dialog appear **exactly once**; the badge disappears within 3 seconds of granting permission. A simple flow.

Detailed background and the Sequoia trap list are summarized in `/Volumes/DISK/dev/knowledge/macos_accessibility_permission.md` (outside this machine, see the repository's SPEC.md).

### Feature — User-configurable preset ordering

- Added **"Reorder…"** to the `…` menu on each preset row in the editor and to the **right-click context menu on the floating panel's preset name**. A DnD sheet lets you change the order.
- Order is saved in a new `presetOrder` field in `config.json`. Escapes the old behavior of fixed alphabetical ordering.
- Presets added externally (e.g., Finder drop) are auto-appended to the end in alphabetical order; missing entries self-heal.
- Control API: added `preset_reorder {ids: [String]}` (`/preset/reorder`). The `/preset/list` response order also follows the saved order.

## v0.7 (2026-05-02)

Diff from v0.6. The "Button Edit" screen evolved into a **unified editor for multiple object types**, so its name, navigation, and editing experience were all overhauled.

### Feature — DnD reordering in the editor's left pane

- **Buttons**: reorder within the same group / move to a different group, by dropping on rows or headers.
- **Groups**: reorder by dropping header to header.
- Landing point highlighting: groups with a border, buttons with a top line.
- Removed the old group right-click menu (edit/delete) and consolidated into the "select on the left → edit on the right" flow.
- Added a `PresetManager.reorderGroups` wrapper.

Implementation memo: SwiftUI `Button` consumed downward gestures, so rows were replaced with `HStack + onTapGesture` to attach `.onDrag/.onDrop` directly. `performDrop` is async (synchronous `DispatchGroup.wait` + `main.sync` froze the main thread when a drop was canceled midway).

### Improvement — Editor access and UI wording cleanup

- **Renamed window from "Button Edit" to "Edit"** (tabs and menus included). The screen actually edits groups, presets, and security too, so the name was aligned with reality.
- **Unified group-add UI with button-add** — one-click "New Group" creation. The pencil button on the group row renames later.
- **Unified preset / group right-click menus to "Edit…" / "Delete…"**. The preset "Edit…" now opens the edit window (the old "Rename Preset" NSAlert was removed).
- **Added a pencil icon to the left of the floating panel's gear (AI connection)**, making access to the edit window explicit.

### Feature — Group / button duplication, repositioned delete button

- **Right-click** the group / button rows in the editor left pane → **"Duplicate"** to duplicate. The copy is inserted next to the original; the label becomes "○○ Copy" with a fresh id.
- Added `PresetManager.duplicateGroup(id:)` (also duplicates inner buttons with fresh ids).
- **Moved the delete button from the top of the right pane to the left of the save button at the bottom** (both ButtonEditor and GroupEditor).
- Placed "Add Group" / "Add Button" at the bottom-right side-by-side in an HStack.

## v0.6 (2026-05-01)

Cumulative changes from v0.5 (DMG distribution version) through here.

> **Note — Partial loss of commit history**
>
> This cycle was caught in Claude server outages, and some commits were lost. **Added features and officially changed areas are exhaustively recorded based on the source code**, but the trial-and-error changes made during the process (intermediate commits and diff stacks) could not be retained. For CHANGELOG reference there is no issue, but please note that for some periods the "why this implementation" details cannot be traced via `git log`.

### Change — Control API token storage moved from Keychain to file

We previously stored the Control API authentication token in the macOS Keychain. This release moves the **primary token storage to `~/Library/Application Support/FloatingMacro/control_api_token` (mode 0600)**. The Keychain remains as a mirror for `security find-generic-password ...` CLI compatibility.

Why we made this change, honestly:

- **The way it was introduced wasn't great** — Keychain is originally a mechanism for "users to actively allow trust relationships between tools," but the implementation at the time failed to communicate that intent to users, resulting in a UX that felt like "a magic spell for Accessibility settings."
- **The security benefit wasn't materializing either** — Control API is loopback (127.0.0.1) only, reachable only from processes with the same user privileges. Against reads from another process running under the same user, Keychain ACL and file mode 0600 offer essentially equivalent defense. The added security gain from Keychain was nearly zero.
- **It was just adding overhead to debug / test work** — with ad-hoc signing, every rebuild changes the binary hash, and Keychain ACL treats the new binary as a "different app", prompting for a password on every read. Contrary to intent, this was a blocker for both users and test agents.

Overall it was in a state of **"the introduction wasn't paying off, and it was just adding overhead"**, so we made the call to retire Keychain-based token management for now. The **active authentication step** for AI ⇄ FloatingMacro will be re-designed at a different layer (e.g., per-client pairing in the AI integration window, visibility and revoke for permitted clients).

Token retrieval is now possible via either of the following (file route is recommended — no password prompt):

```bash
# Recommended
cat ~/Library/Application\ Support/FloatingMacro/control_api_token

# Compatibility (via Keychain mirror)
security find-generic-password -s FloatingMacro -a ControlAPIToken -w
```

### Improvement — Cleanup of the Accessibility repair flow

Revised the dialog behavior and user experience for re-granting permissions.

- **Removed our own NSAlert and unified into the OS's `prompt:true` dialog** — our own NSAlert had no effect on TCC; it was just decoration.
- **Added a 0.8-second fallback `openSystemPreferences()`** — for cases on Sequoia and later where the OS dialog's "Open System Settings" button doesn't work, opens System Settings ourselves as insurance.
- **Changed the Repair button to self-restart** — `NSWorkspace.openApplication` restarts with the `--prompt-accessibility` argument → the new process calls `prompt:true` from a clean AX cache state. Avoids cases where old entries + stale TRUE blocked addition to the list.
- **Changed `accessibilityTrusted` initial value to false** — prevents accidents where the warning banner disappears due to stale TRUE cache right after launch (3-second polling catches up to the real value quickly).
- **Changed `AccessibilityChecker.openSystemPreferences()` to route through `/usr/bin/open`** — handles cases where `NSWorkspace.shared.open(url)` silently fails when System Settings isn't running. Falls back to `NSWorkspace` on failure. Also added execution logging for diagnosability.
- **Resolved double-fire of TCC reset** — removed the launch-time `tccutil reset` in `scripts/rebuild-and-relaunch.sh` and unified to the single-shot reset in the app's `BinaryIdentity`. Eliminated possible competition with System Settings behavior.

### Feature — Right-click menu on mini icon

Right-clicking the mini icon when the floating window is collapsed shows the same menu as the menu bar (show/hide toggle, preset switch, opacity, button edit, AI mode, AI connect, open settings folder, reload, quit). Operate directly from the mini icon without reaching for the status bar icon.

### Feature — Right-click menu on group headers

- **Added "Delete Group..." (destructive) to GroupView's contextMenu** — safe delete via confirmation dialog.
- **Added "Add New Group" to the panel body's contextMenu** — group addition is now possible by right-clicking on blank space.
- **Expanded ScrollView hit-test area to fill** — wrapped in `GeometryReader` so that the contextMenu responds even in blank areas when there are few buttons.

### Other

- Bumped `Info.plist`'s `CFBundleVersion` to 7 (sync with the build-number auto-bump in `scripts/release.sh`).
- Updated related docs (README, npm/README, docs/mcp/*, agent_prompts.json, SystemPrompt.swift, scripts/*.sh) to follow the new token storage location.

## v0.5 (2026-04-29)

### New feature — Automatic recovery for Accessibility permission

There was a problem where macOS would **silently disable Accessibility permission** triggered by rebuilds, updates, or time passing. The app's logs would say "Text injected" but not a single character would land in the target app — a mysterious failure mode caused by TCC re-verification of the ad-hoc-signed + `com.apple.provenance` xattr combination. This release adds **auto-detection + one-click recovery**.

- **Auto-reset on launch via binary ID comparison**
  - At launch, SHA-256 compare with previous binary; if changed, auto-fire `tccutil reset Accessibility`.
  - State is recorded in `~/Library/Application Support/FloatingMacro/last_binary_hash.txt`.
  - Does nothing on first launch or normal re-launch (binary unchanged).
- **Permission-lost badge**
  - Always-on warning badge at the bottom of the panel (only when permission is invalid).
  - Click executes `tccutil reset` + opens System Settings in one shot → the user just needs to re-add the `.app` with `+` to recover.
- **AccessibilityChecker probe improvements**
  - Catches the `AXIsProcessTrusted` cache trap (continues to return true even when revoked) via a 2-stage approach with an AX API probe.
  - Limits the probe's counter-signal to `.apiDisabled` only (resolved a flicker bug where untrust was misdetected just because the focused app didn't respond to AX).
- **One-click "Open Accessibility Settings" button**
  - Added at the top of the default preset. Jumps directly to System Settings → Privacy & Security → Accessibility.

### New feature — GUI E2E test infrastructure

Added a harness app (`fm-test-target`) and E2E scripts so text injection behavior can be verified **automatically**.

- **fm-test-target** (`Sources/FMTestTarget/`)
  - A dedicated macOS GUI app (NSWindow + NSTextView).
  - All smart substitutions off, direct UTF-8 NSPasteboard, spin-wait to handle IME and LC_CTYPE traps.
  - Local HTTP API (`/focus` `/clear` `/text` `/events` `/quit`) for external test driving.
- **scripts/text_inject_e2e.sh**
  - Pre-execution baseline of 8 cases (paste / copy / cut / select-all / Japanese / smart-sub / long text) verifies "does the harness behave like a real text editor".
  - 7 cases (ASCII / Japanese / newlines / `/compact` / symbols / 600 characters / restoreClipboard=false) reported on 2 axes `[key✓/✗ text✓/✗]`.
  - On failure, auto-diagnoses to distinguish CGEvent.post silent drop from paste race.

### New feature — button_press via synthesized real click

The `button_press` tool now resolves each button's `accessibilityIdentifier` via AX and **actually fires a mouse click via CGEvent** at the center of its screen rect.

- The same-process SwiftUI Button's **native press visual effect** runs, so human observers can clearly see "the button was pressed".
- Can detect failure modes invisible to direct `executeButton` calls — window obscured / hit-test broken / disabled view, etc.
- The cursor physically moves to the button center → click → returns to the original position.

### New feature — Preset bundling / import / export

- **Bundled presets** (`SeedPresetInstaller`)
  - `midjourney` / `note-hashtags` are installed to the user directory on first launch.
- **API**: `preset_export` / `preset_export_bundle` / `preset_import` / `preset_install_seeds`.
- **PresetDirectoryWatcher**: detects external changes (e.g., drag from Finder) to `~/Library/Application Support/FloatingMacro/presets/` and reflects them in the UI.
- **`preset_create`**: auto-numbers as `preset-N` when name is omitted.

### Improvements

- `rebuild-and-relaunch.sh`: added a `tccutil reset` step just before launch.
- `scripts/reset_accessibility.sh`: a standalone tool that resets TCC + opens System Settings.
- `scripts/seed_install_smoke.sh`: smoke check for first-time install of bundled presets.

### Known limitations

- **Developer ID signing / notarization is unsupported**. The root issue where TCC periodically revokes trust due to the ad-hoc signing + `com.apple.provenance` combination is not resolved. This release's strategy is to "notice when broken via the badge + fix with one click" to minimize operational damage. Real distribution requires migration to Developer ID (planned for v1.0).

---

## v0.4 (2026-04-27)

### New features

- **AI integration window: expanded client support**
  - v0.3 was Claude Code only; one-click registration now extends to Cursor / Gemini CLI / VS Code / Windsurf.
  - For each client, "CLI Register" and "HTTP Register" buttons are provided as 2 separate flows.
  - Config write targets: Cursor (`~/.cursor/mcp.json`), Gemini CLI (`~/.gemini/settings.json`), VS Code / Windsurf (their respective `mcp.json`).
- **Bundled CLI (stdio) MCP server**
  - Added a thin Node.js MCP server (`floatingmacro-mcp` package) under `npm/`.
  - Bundled into the app bundle (`Contents/Resources/npm`) at DMG build time.
  - Provides a stable path that doesn't go through macOS codesign / Gatekeeper / Keychain ACL.
  - The "CLI Register" button writes a config that references this package via `npx -y file:...`.
- **ACP (Agent-Centric Protocol) manifest support**
  - Added `GET /agents` / `GET /agents/floatingmacro` / `POST /runs`.
  - AI that doesn't support MCP (plain ChatGPT, etc.) can operate via `curl` against `/tools/call`.
  - The connection prompt is copyable with Bearer embedded from the AI integration window.

### Improvements

- **API self-reported version updated**
  - `/manifest`, `/mcp` (initialize), `/.well-known/agent.json`, `/openapi.json` now return `version` updated from `0.1` to `0.4`.
  - Fixed lingering ones missed in v0.2 / v0.3 bumps.

### Documentation

- **New per-client MCP setup guides at `docs/mcp/`**
  - `setup.md` (common), `claude-code.md`, `claude-desktop.md`, `cursor.md`, `gemini-cli.md`, `acp.md`.
  - Consolidates each client's config file format, registration name rules, and troubleshooting.
- **README synced with reality**
  - Reflects required authentication; examples unified to go through `/tools/call`; recommends the AI integration window one-click registration.
- **Manifest-driven AI connection flow** organized in `CLAUDE.md`.

## v0.3 (2026-04-27)

### New features

- **Dedicated AI integration window**
  - Launched from menu bar "Connect AI..." and the ⚙ button at the top-right of the floating panel.
  - Connection prompts are copyable in one shot with Bearer token embedded (paste into Claude Code / Cursor / Gemini CLI / ChatGPT, etc., and the AI can operate FloatingMacro).
  - One-click MCP entry registration to Claude Code (`~/.claude.json`) (preserves existing `mcpServers`).
  - Inline copy ✓ buttons for endpoint URL and token-retrieval command.
  - Design decision: button editing (per-object) and AI integration (app-wide initial setup) have different granularity, so we made it an independent window instead of a Settings tab.
- **Default preset has an "AI Integration" group**
  - "Copy Connection Prompt" and "Register MCP to Claude Code" buttons are pre-included.
  - AI integration is completed via panel buttons alone, even immediately after a fresh install.
- **AI bootstrap manual bundled in DMG**
  - As `AIに渡す手順書.md` (copy of the repository's `CLAUDE.md`), placed alongside when the Finder mounts the DMG.
  - DMG users who don't see the repository can still discover the existence of and steps for AI integration.

### Improvements

- **Discovery-class endpoints exempted from auth**
  - `/manifest`, `/help`, `/.well-known/agent.json`, `/openapi.json` are exempted from Bearer authentication.
  - It's a chicken-and-egg problem: the entry point through which an AI "knows authentication is needed" must be openable without authentication.
- **`systemPrompt` fixed to match reality**
  - Removed the old phrase "no authentication" and explicitly described the Bearer token retrieval procedure and the need to go through `/tools/call`.
  - Ensures consistency as a first-action guide when AI connects.
- **Removed resize upper limit from the floating panel**
  - Old: hard cap of `maxWidth: 300, maxHeight: 600`, giving the "can shrink but can't grow" phenomenon.
  - New: changed to `.infinity`, fully tracking NSPanel's drag-resize.
- **Workaround for `pbcopy` mojibake**
  - Child processes of macOS apps launched via GUI inherit `LANG=""` / `LC_CTYPE="C"`, so UTF-8 Japanese is corrupted by `pbcopy`.
  - For the relevant `launch` actions, prepend `export LC_CTYPE=UTF-8` at the start.

### Bug fixes

- **`build-app.sh` SwiftPM resource bundle copy omission**
  - Only `FloatingMacro_FloatingMacroApp.bundle` was being copied; `FloatingMacro_FloatingMacroCore.bundle` was being dropped.
  - As a result, Core-side resources like `agent_prompts.json` weren't found via `Bundle.module` and always fell back to in-code defaults (a hard-to-notice silent bug).
  - Fixed to copy all `*.bundle`.

### Documentation

- Added a new `CLAUDE.md` at the repo root
  - A bootstrap for AI (Claude Code, etc.) to correctly operate FloatingMacro via ACP.
  - Describes the principle of going through `/tools/call`, the prohibition on direct preset JSON editing, mappings for typical requests, etc.

## v0.2 (2026-04-26)

### New features

- **Bearer token authentication added to Control API**
  - At launch, a random token is stored in Keychain; subsequently all endpoints require `Authorization: Bearer <token>`.
  - `fmcli token show` retrieves the token, which can be passed to external tools like Claude Code for integration.
  - `controlAPI.requireAuth` toggles enabled/disabled (default ON).
  - Details: [docs/auth-spec.md](docs/auth-spec.md), [docs/keychain-auth.ja.md](docs/keychain-auth.ja.md).
- **App icon refreshed**
  - Regenerated with Apple HIG-compliant squircle mask (pure formula-based boundary, no pixel artifacts).
  - Adopted a pre-transparent 1024×1024 high-resolution version.
- **Improved visibility of mini icon (when panel collapsed)**
  - Refreshed to a ⌘ symbol in brand color (`#ddb7ff`) on a purple gradient background.
  - Old: dim gray background + faint command.square.fill (low visibility).

### Improvements

- **Floating panel position persistence**
  - Saves the position to `config.json` at the moment the panel is collapsed.
  - Restores from that position on next launch (old: saved only at app termination).
- **Mini icon position persistence**
  - The position dragged is saved to `UserDefaults`.
  - On next collapse, restored from there.
- **Settings window major overhaul** (`SettingsDetail.swift` +413 lines)
  - Wrapped `NSColorWell` in `NSViewRepresentable` for instant preview.
  - UI improvements for the group editor, app icon picker, etc.

### Build / operations

- **New `scripts/rebuild-and-relaunch.sh`**: cleans SwiftPM cache completely → builds → ad-hoc signs → launches in one shot.
- **New `scripts/release.sh`**: version increment + build + DMG creation + publish to public repo + GitHub release in one pass.
- **New `scripts/generate_iconset.py`**: generates iconset with transparency + drop shadow.
- **`scripts/build-app.sh`**: switched icon source to v1 squircle (vector); also generates `@2x` (1024px) size.
- **App/Info.plist**: version updated (0.1 → 0.2).

### Tests

- Added `Tests/FloatingMacroCoreTests/AuthMiddlewareTests.swift` (unit tests for Bearer authentication middleware).
- Added `Tests/FloatingMacroCoreTests/TokenStoreTests.swift` (unit tests for Keychain TokenStore).

### Documentation

- `docs/auth-spec.md`: implementation specification for the authentication feature.
- `docs/keychain-auth.ja.md`: setup / operation guide for Keychain authentication.
- `docs/AI_PROTOCOL.md` / `docs/AI_PROTOCOL.ja.md`: updated for the authentication flow.
- `docs/manual_test.md` / `docs/manual_test.ja.md`: updated manual test procedures.

---

## v0.1 (2026-04-18)

Initial release. Basic functionality of FloatingMacro: floating panel, action execution (key / text / launch / terminal / delay / macro), preset switching, GUI editor, structured logging, HTTP Control API (REST + MCP + A2A + OpenAPI 3.1).
