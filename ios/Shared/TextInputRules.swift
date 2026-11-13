import Foundation

struct WordLexicon: Decodable {
    let words: [String]
    let corrections: [String: String]
}

enum TextInputRules {
    static func currentWord(before: String, after: String = "", hasSelection: Bool = false) -> String? {
        guard !hasSelection else { return nil }
        if let first = after.first, first.isLetter || first.isNumber || first == "'" || first == "’" { return nil }
        guard let range = before.range(of: "[\\p{L}\\p{M}]+(?:['’][\\p{L}\\p{M}]+)*$", options: .regularExpression) else { return nil }
        if let previous = before[..<range.lowerBound].last,
           previous.isLetter || previous.isNumber || "@#/_\\.:-'’".contains(previous) { return nil }
        let word = String(before[range])
        return word.count <= 64 ? word : nil
    }

    static func preservingCase(_ suggestion: String, original: String, locale: String) -> String {
        let language = Locale(identifier: locale)
        if original == original.uppercased(with: language) { return suggestion.uppercased(with: language) }
        if original.first?.isUppercase == true {
            return String(suggestion.prefix(1)).uppercased(with: language) + suggestion.dropFirst()
        }
        return suggestion
    }

    // Optimal string alignment distance: insertion, deletion, replacement, adjacent transposition.
    static func distance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs), b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var rows = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { rows[i][0] = i }
        for j in 0...b.count { rows[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                rows[i][j] = min(rows[i - 1][j] + 1, rows[i][j - 1] + 1, rows[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                if i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1] {
                    rows[i][j] = min(rows[i][j], rows[i - 2][j - 2] + 1)
                }
            }
        }
        return rows[a.count][b.count]
    }

    static func suggestions(for word: String, lexicon: WordLexicon?, personalWords: [String], locale: String) -> [String] {
        let language = Locale(identifier: locale)
        let lower = word.lowercased(with: language)
        guard lower.count >= 2 else { return [] }
        let words = personalWords + (lexicon?.words ?? [])
        var result: [String] = []
        if !personalWords.contains(where: { $0.lowercased(with: language) == lower }), let fix = lexicon?.corrections[lower] {
            result.append(fix)
        }
        result += words.filter { $0.lowercased(with: language).hasPrefix(lower) && $0.lowercased(with: language) != lower }
        if lower.count >= 3 {
            result += words.filter { abs($0.count - lower.count) <= 1 && distance(lower, $0.lowercased(with: language)) == 1 }
        }
        var seen = Set<String>()
        return result.map { preservingCase($0, original: word, locale: locale) }
            .filter { $0 != word && seen.insert($0).inserted }.prefix(3).map { $0 }
    }
}

struct EmojiEntry: Decodable, Identifiable {
    let text: String
    let name: String
    let keywords: String
    let variants: [String]
    var id: String { text }

    func displayed(tone: String) -> String {
        guard !tone.isEmpty else { return text }
        return variants.first { variant in
            let tones = variant.unicodeScalars.filter { (0x1F3FB...0x1F3FF).contains($0.value) }
            return !tones.isEmpty && tones.allSatisfy { String($0) == tone }
        } ?? text
    }
}

struct EmojiCategory: Decodable, Identifiable {
    let id: String
    let title: String
    let icon: String
    let entries: [EmojiEntry]
}

struct EmojiCatalog: Decodable {
    let version: String
    let sequenceCount: Int
    let categories: [EmojiCategory]
}
