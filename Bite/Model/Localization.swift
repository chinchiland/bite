import Foundation

/// The app's words in the reader's language, from Localizable.xcstrings. The models use these
/// instead of SwiftUI's automatic lookup because they also build on Linux for the logic tests,
/// where there is no catalog and the English key comes back unchanged.
func tr(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// A phrase with one value in it: the catalog holds "%@ kcal over" and this fills in the value.
func tr(_ key: String, _ value: String) -> String {
    NSLocalizedString(key, comment: "").replacingOccurrences(of: "%@", with: value)
}

/// The reader's language as the two letter code the bundled data is keyed by: "fr", "es" or "en".
enum AppLanguage {
    static let supported = ["en", "fr", "es"]

    static var current: String {
        let preferred = Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first ?? "en"
        let code = String(preferred.prefix(2)).lowercased()
        return supported.contains(code) ? code : "en"
    }
}
