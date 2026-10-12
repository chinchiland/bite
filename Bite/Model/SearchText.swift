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

    /// True when the term starts the word, or nearly: in a term of four letters or more, one
    /// letter wrong, missing, added or swapped with the next, so "chiken" starts "chicken".
    /// The first letter has to be right, which keeps "beef" away from "reef".
    static func nearlyStarts(_ word: String, with term: String) -> Bool {
        if word.hasPrefix(term) { return true }
        let term = Array(term), word = Array(word)
        guard term.count >= 4, term.first == word.first else { return false }
        return [term.count, term.count + 1, term.count - 1].contains { length in
            length <= word.count && withinOneEdit(term, Array(word[..<length]))
        }
    }

    /// One substitution, insertion, deletion or swap of neighbours at most.
    static func withinOneEdit(_ a: [Character], _ b: [Character]) -> Bool {
        let (short, long) = a.count <= b.count ? (a, b) : (b, a)
        guard long.count - short.count <= 1 else { return false }
        var i = 0
        while i < short.count, short[i] == long[i] { i += 1 }
        if i == long.count { return true }
        if short.count < long.count { return short[i...].elementsEqual(long[(i + 1)...]) }
        if short[(i + 1)...].elementsEqual(long[(i + 1)...]) { return true }
        return i + 1 < short.count && short[i] == long[i + 1] && short[i + 1] == long[i]
            && short[(i + 2)...].elementsEqual(long[(i + 2)...])
    }
}
