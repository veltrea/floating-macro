# Third-Party Licenses

FloatingMacro bundles and links against the following third-party components.
All are compatible with this project's MIT license.

---

## Lucide Icons (bundled)

Roughly 1700 SVG icons are shipped in
`Sources/FloatingMacroApp/Resources/lucide/` and loaded at runtime via
`Bundle.module`.

- Source: <https://lucide.dev>
- Repository: <https://github.com/lucide-icons/lucide>
- License: **ISC**
- Full license text: `Sources/FloatingMacroApp/Resources/lucide/LICENSE`

The ISC license grants permission to use, copy, modify, and distribute the
icons provided the copyright notice and the permission notice are preserved.
We comply by shipping the upstream `LICENSE` file unmodified alongside the
icons.

---

## SF Symbols (runtime-only, not bundled)

FloatingMacro renders [SF Symbols](https://developer.apple.com/sf-symbols/) at
runtime using Apple's system API
(`NSImage(systemSymbolName:accessibilityDescription:)`). The glyph data itself
is **not** bundled; it lives inside macOS. Only identifier strings (e.g.
`star.fill`) are referenced in source.

Apple's SF Symbols license restricts SF Symbols to Apple-platform
applications. FloatingMacro is a macOS-only application and therefore
complies.

---

## Swift standard library / AppKit / Foundation / Network.framework / SwiftUI

Provided by macOS itself. Used under Apple's standard SDK terms.
