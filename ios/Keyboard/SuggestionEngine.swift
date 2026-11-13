import UIKit

@MainActor
final class SuggestionEngine {
    let prediction = LocalPredictionEngine()
    private lazy var checker = UITextChecker()
    private let lexicons: [String: WordLexicon]
    private lazy var available = UITextChecker.availableLanguages
    private let worker = LocalSuggestionWorker()
    private struct SystemResult {
        let words: [String]
        let correction: String?
    }
    private var systemCache: [String: SystemResult] = [:]

    init() {
        lexicons = Bundle.main.url(forResource: "lexicon", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([String: WordLexicon].self, from: $0) } ?? [:]
    }

    private func systemLanguage(_ language: KeyboardLanguage) -> String? {
        let locale = language.locale.replacingOccurrences(of: "-", with: "_")
        return available.first { $0 == locale } ?? available.first { $0.replacingOccurrences(of: "-", with: "_").split(separator: "_").first.map(String.init) == language.id }
    }

    func suggestions(word: String, language: KeyboardLanguage, personal: [String]) async -> [String] {
        var result = await worker.suggestions(word: word, language: language,
                                             personal: personal, lexicon: lexicons[language.id], prediction: prediction)
        guard !Task.isCancelled else { return [] }
        guard word.count >= 2 else { return [] }
        let cacheKey = language.id + ":" + word
        if let cached = systemCache[cacheKey] {
            result += cached.words
        } else if result.count < 3, let code = systemLanguage(language) {
            // UITextChecker is main-actor isolated. Consult it only after the
            // debounce and when the indexed local dictionary needs a fallback.
            let range = NSRange(location: 0, length: word.utf16.count)
            let misspelled = checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false, language: code)
            var words: [String] = []
            var correction: String?
            if misspelled.location != NSNotFound {
                let guesses = checker.guesses(forWordRange: range, in: word, language: code) ?? []
                words += guesses
                if let guess = guesses.first,
                   guess.first?.lowercased() == word.first?.lowercased(),
                   TextInputRules.distance(word.lowercased(), guess.lowercased()) == 1 { correction = guess }
            }
            words += checker.completions(forPartialWordRange: range, in: word, language: code) ?? []
            if systemCache.count >= 128 { systemCache.removeAll(keepingCapacity: true) }
            systemCache[cacheKey] = SystemResult(words: words, correction: correction)
            result += words
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
        // Space/Return must insert immediately, without a synchronous spelling
        // service round trip. Use a correction prepared during idle prediction.
        guard word.count >= 4, let guess = systemCache[language.id + ":" + word]?.correction else { return nil }
        return TextInputRules.preservingCase(guess, original: word, locale: language.locale)
    }
}

private actor LocalSuggestionWorker {
    func suggestions(word: String, language: KeyboardLanguage, personal: [String],
                     lexicon: WordLexicon?, prediction: LocalPredictionEngine) -> [String] {
        guard !Task.isCancelled else { return [] }
        return TextInputRules.suggestions(for: word, lexicon: lexicon, personalWords: personal, locale: language.locale)
            + prediction.completions(word: word, language: language.id)
    }
}

actor GlideRankingWorker {
    func rank(trace: [TracePoint], centers: [String: TracePoint], words: [String]) -> [String] {
        GlideDecoder.rank(trace: trace, centers: centers, words: words)
    }
}
