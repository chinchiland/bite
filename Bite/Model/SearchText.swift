import Foundation

enum SearchText {
    /// Lowercased words without accents: "Pâtes, cuites" becomes ["pates", "cuites"].
    static func words(in text: String) -> [String] {
        text.replacingOccurrences(of: "œ", with: "oe")
            .replacingOccurrences(of: "Œ", with: "oe")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    /// True when every word of the query starts one of the words.
    static func matches(_ terms: [String], in words: [String]) -> Bool {
        terms.allSatisfy { term in words.contains { $0.hasPrefix(term) } }
    }
}
