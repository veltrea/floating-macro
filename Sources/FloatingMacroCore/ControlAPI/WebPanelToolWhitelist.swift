import Foundation

/// White list of tools callable from Web Panel (P5-12 / P5-13).
///
/// Why a White List Approach?
/// The Web Panel can be accessed via LAN from Safari on smartphones/tablets.
/// The `/tools/call` is for destructive operations including file overwriting and removal of presets, etc., so it should be used with caution.
/// When considering scenarios where a normal Bearer token leaks in some way,
/// In the route of "**LAN public mode × ephemeral token**", destructive operations are **from the very beginning**.
/// Make sure you can't call it safely.
///
/// Included tools / Excluded tools
/// include: read (ping / get_state / panel_list / preset_list /
/// and the execution of the button to be pressed by the user (button_press) and,
/// Preset switch (`preset_switch`).
/// exclude: `*_add` / `*_update` / `*_delete` type config changes,
/// `run_action` (any keystroke/command execution), `settings_*` (Mac side)
/// Window operations, AI integration, log references, etc.
///
/// Load map-like positioning
/// At the initial stage where it just works, expand the whitelist as needed. For example:
/// If there are requests to remotely adjust the panel position, use `panel_move` or `panel_resize`.
/// Adding a judgment may be possible.
public enum WebPanelToolWhitelist {

    /// Collection of names of tools callable from Web Panel.
    public static let allowed: Set<String> = [
        // Discovery & state
        "ping",
        "help",
        "manifest",
        "get_state",

        // Panel discovery (exclude write-system panel_create / panel_close)
        "panel_list",

        // Exclude mutate-series preset_create, rename, and delete from Preset switching category/type.
        "preset_list",
        "preset_current",
        "preset_get",     // Phase 5: Read presets for each Web Panel
        "preset_switch",

        // Button Press - Main Purpose of Web Panel
        "button_press",
    ]

    /// Determines whether the name is included in allowed.
    public static func isAllowed(_ name: String) -> Bool {
        return allowed.contains(name)
    }
}
