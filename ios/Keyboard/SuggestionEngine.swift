import UIKit

@MainActor
final class SuggestionEngine {
    let prediction = LocalPredictionEngine()
    private let checker = UITextChecker()
    private let lexicons: [String: WordLexicon]
    private let available = UITextChecker.availableLanguages

    init() {
        lexicons = Bundle.main.url(forResource: "lexicon", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([String: WordLexicon].self, from: $0) } ?? [:]
    }

    private func systemLanguage(_ language: KeyboardLanguage) -> String? {
        let locale = language.locale.replacingOccurrences(of: "-", with: "_")
        return available.first { $0 == locale } ?? available.first { $0.replacingOccurrences(of: "-", with: "_").split(separator: "_").first.map(String.init) == language.id }
    }

    func suggestions(word: String, language: KeyboardLanguage, personal: [String]) -> [String] {
        var result = TextInputRules.suggestions(for: word, lexicon: lexicons[language.id], personalWords: personal, locale: language.locale)
        result += prediction.completions(word: word, language: language.id)
        guard word.count >= 2 else { return [] }
        if let code = systemLanguage(language) {
            let range = NSRange(location: 0, length: word.utf16.count)
            let misspelled = checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false, language: code)
            if misspelled.location != NSNotFound {
                result += checker.guesses(forWordRange: range, in: word, language: code) ?? []
            }
            result += checker.completions(forPartialWordRange: range, in: word, language: code) ?? []
        }
        var seen = Set<String>()
        return result.map { TextInputRules.preservingCase($0, original: word, locale: language.locale) }
            .filter { $0 != word && seen.insert($0).inserted }.prefix(3).map { $0 }
    }

    func automaticCorrection(word: String, language: KeyboardLanguage, personal: [String]) -> String? {
        let locale = Locale(identifier: language.locale)
        let lower = word.lowercased(with: locale)
        guard word.count >= 3, word.count <= 32,
              word != word.uppercased(with: locale),
              !personal.contains(where: { $0.lowercased(with: locale) == lower }) else { return nil }
        if let fix = lexicons[language.id]?.corrections[lower] {
            return TextInputRules.preservingCase(fix, original: word, locale: language.locale)
        }
        guard word.count >= 4, let code = systemLanguage(language) else { return nil }
        let range = NSRange(location: 0, length: word.utf16.count)
        guard checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false, language: code).location != NSNotFound,
              let guess = checker.guesses(forWordRange: range, in: word, language: code)?.first,
              guess.first?.lowercased() == lower.first?.lowercased(),
              TextInputRules.distance(lower, guess.lowercased(with: locale)) == 1 else { return nil }
        return TextInputRules.preservingCase(guess, original: word, locale: language.locale)
    }
}
