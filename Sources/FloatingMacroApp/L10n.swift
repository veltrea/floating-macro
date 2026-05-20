import Foundation

/// Shorthand for localized strings from the app module bundle.
/// `String(localized:bundle:)` requires `bundle: .module` in SwiftPM
/// executable targets, so this wrapper keeps call sites clean.
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}

/// Localized format-string helper. The .strings template uses `%@` /
/// `%d` placeholders; arguments are substituted via `String(format:)`.
func L_(_ key: String.LocalizationValue, _ args: CVarArg...) -> String {
    let template = String(localized: key, bundle: .module)
    return String(format: template, arguments: args)
}
