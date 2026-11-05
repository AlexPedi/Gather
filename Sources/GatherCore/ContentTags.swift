import Foundation
import NaturalLanguage

public struct TagCatalog: Codable, Sendable {
    public var names: [String]
    public init(names: [String] = []) { self.names = names }
}
public enum ContentTags {
    public static let version = 2
    // Interface chrome is poor subject evidence. This affects suggestions only, never custom tags.
    private static let noise: Set<String> = ["edit", "share", "attach", "mail", "login", "logout", "sign in", "sign out", "click", "button", "menu", "view", "screen", "screenshots", "screenshot", "oct", "date", "details", "between", "change", "stay", "vol", "curr", "employ", "home", "search", "help", "back", "next", "cancel", "save", "download", "upload", "settings", "account", "page", "tab", "more", "open", "close"]
    public static func isUseful(_ name: String) -> Bool {
        let value = key(name)
        return name.count >= 3 && name.count <= 40 && !noise.contains(value) &&
            name.rangeOfCharacter(from: .decimalDigits) == nil && !Classifier.tokens(name).isEmpty
    }
    /// Conservative English fallback when a noun lemma is unavailable; avoids blunt trailing-s removal.
    public static func nounStem(_ word: String) -> String {
        let value = key(word)
        let irregular = ["children": "child", "people": "person", "men": "man", "women": "woman", "mice": "mouse", "teeth": "tooth", "feet": "foot"]
        if let stem = irregular[value] { return stem }
        if value.count > 5 && value.hasSuffix("ies") { return String(value.dropLast(3)) + "y" }
        return value
    }
    public static func key(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    public static func normalize(_ tags: [String]) -> [String] {
        var seen: Set<String> = []
        return tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert(key($0)).inserted }
    }
    /// Derive an open vocabulary from actual words and names, never a category keyword list.
    public static func suggest(_ raw: String) -> [String] {
        let text = String(raw.prefix(30_000))
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let tagger = NLTagger(tagSchemes: [.nameTypeOrLexicalClass, .lemma])
        tagger.string = text
        var scores: [String: Int] = [:]
        var labels: [String: String] = [:]
        let stop = Classifier.tokens(text)
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameTypeOrLexicalClass,
                             options: [.omitPunctuation, .omitWhitespace, .joinNames]) { tag, range in
            guard tag == .noun || tag == .personalName || tag == .placeName || tag == .organizationName else { return true }
            let word = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard isUseful(word) else { return true }
            var label = word
            if tag == .noun {
                let lemma = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0?.rawValue
                label = nounStem(lemma ?? word).localizedCapitalized
            }
            guard isUseful(label) else { return true }
            let normalized = key(label)
            scores[normalized, default: 0] += (tag == .noun ? 2 : 4)
            labels[normalized] = label
            return true
        }
        // Token-frequency fallback if the language's lexical model is unavailable.
        if scores.isEmpty {
            for word in text.components(separatedBy: .alphanumerics.inverted) {
                let normalized = key(word)
                guard stop.contains(normalized), word.count >= 4, isUseful(word) else { continue }
                scores[normalized, default: 0] += 1; labels[normalized] = word.localizedCapitalized
            }
        }
        return scores.keys.sorted { scores[$0] == scores[$1] ? $0 < $1 : scores[$0, default: 0] > scores[$1, default: 0] }
            .prefix(6).compactMap { labels[$0] }
    }
}
