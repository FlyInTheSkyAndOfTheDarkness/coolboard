import UIKit
import SwiftUI

final class KeyboardViewController: UIInputViewController {
    private var model: KeyboardModel!
    private var heightConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        model = KeyboardModel(controller: self)
        let host = UIHostingController(rootView: KeyboardView(model: model))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        host.didMove(toParent: self)
        let constraint = view.heightAnchor.constraint(equalToConstant: model.height)
        constraint.priority = .defaultHigh
        constraint.isActive = true
        heightConstraint = constraint
        primaryLanguage = model.language.locale
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.resetComposition()
        model.refreshContext()
        updateHeight()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        model.clipboardMonitor.start()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateHeight()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        model?.clipboardMonitor.stop()
        model?.toolsTask?.cancel()
        model?.toolsLoading = false
        model?.gliding = false
        model?.glidePoints = []
    }

    override func textDidChange(_ textInput: UITextInput?) {
        model?.refreshContext()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        model?.refreshContext()
    }

    func updateHeight() {
        guard let model else { return }
        let height = model.height + view.safeAreaInsets.bottom
        if heightConstraint?.constant != height { heightConstraint?.constant = height }
        view.backgroundColor = model.palette.background
    }
}

@MainActor
final class KeyboardModel: ObservableObject {
    weak var controller: KeyboardViewController?
    let layouts: KeyboardLayouts
    @Published var preferences: KeyboardPreferences
    @Published var library: ClipLibrary
    @Published var clipboardStatus = "Авто · последние 10 текстов"
    @Published var clipboardNeedsRetry = false
    @Published var clipSection = "history"
    lazy var clipboardMonitor = ClipboardMonitor(model: self)
    @Published var panel = "keys"
    @Published var search = ""
    @Published var message: String?
    @Published var symbolPage = -1
    @Published var shiftOverride: Bool?
    @Published var caps = false
    @Published var context = ""
    @Published var suggestions: [String] = []
    @Published var searchTarget: String?
    @Published var emojiQuery = ""
    @Published var emojiCategory = "smileys"
    @Published var recentEmoji: [String]
    @Published var personalWords: [String: [String]]
    @Published private(set) var undo: CorrectionUndo?
    var lastInsertion: InsertionUndo?
    @Published var glidePoints: [CGPoint] = []
    @Published var glideOptions: [String] = []
    @Published var toolsQuery = ""
    @Published var toolsResult: String?
    @Published var toolsItems: [OnlineItem] = []
    @Published var toolsLoading = false
    @Published var toolsError: String?
    @Published var translationTarget = "en"
    @Published var savedMedia: [SavedMedia] = MediaLibrary.load()
    @Published var backgroundData: Data? = try? Data(contentsOf: MediaLibrary.directory.appendingPathComponent("background.jpg"))
    var gliding = false
    var glideBefore: String?
    var glideAfter: String?
    var glideDocument: UUID?
    var glideInserted: String?
    var toolsTask: Task<Void, Never>?
    var toolsGeneration = UUID()
    let emoji: EmojiCatalog
    private let suggestionEngine = SuggestionEngine()
    private var suggestionTask: Task<Void, Never>?
    private var suggestionWord: String?
    private var suggestionDocument: UUID?
    private var composingWord: String?
    private var composingDocument: UUID?
    private var lastShift = Date.distantPast
    private var lastSpace = Date.distantPast
    private var noticeTask: Task<Void, Never>?
    private let storage = UserDefaults.standard

    init(controller: KeyboardViewController) {
        self.controller = controller
        let loadedLayouts = KeyboardLayouts.load()
        layouts = loadedLayouts
        let prefs = UserDefaults.standard.data(forKey: "preferences")
        var restored = prefs.flatMap { try? JSONDecoder().decode(KeyboardPreferences.self, from: $0) } ?? KeyboardPreferences()
        restored.normalize(languages: loadedLayouts.languages)
        preferences = restored
        let data = UserDefaults.standard.data(forKey: "clips")
        let clips = data.flatMap { try? JSONDecoder().decode([SavedClip].self, from: $0) } ?? []
        let migratedLibrary = ClipLibrary(clips: clips)
        library = migratedLibrary
        if let encoded = try? JSONEncoder().encode(migratedLibrary.clips) { UserDefaults.standard.set(encoded, forKey: "clips") }
        personalWords = UserDefaults.standard.data(forKey: "personalWords")
            .flatMap { try? JSONDecoder().decode([String: [String]].self, from: $0) } ?? [:]
        recentEmoji = Array((UserDefaults.standard.stringArray(forKey: "recentEmoji") ?? []).prefix(32))
        emoji = Bundle.main.url(forResource: "emoji", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(EmojiCatalog.self, from: $0) }
            ?? EmojiCatalog(version: "16.0", sequenceCount: 0, categories: [])
    }

    struct CorrectionUndo {
        let original: String
        let replacement: String
        let delimiter: String
        let before: String
        let after: String?
        let document: UUID
    }
    struct InsertionUndo {
        let inserted: String
        let removed: String
        let before: String
        let after: String?
        let document: UUID
    }

    var language: KeyboardLanguage { layouts.languages.first { $0.id == preferences.language } ?? layouts.languages[0] }
    var palette: KeyboardPalette { KeyboardPalette.named(preferences.theme) }
    var localPrediction: LocalPredictionEngine { suggestionEngine.prediction }
    var keyHeight: CGFloat { preferences.size == "compact" ? 36 : preferences.size == "large" ? 52 : 44 }
    var rows: [String] {
        if symbolPage >= 0 { return layouts.symbols[min(symbolPage, layouts.symbols.count - 1)] }
        return (preferences.numberRow ? ["1234567890"] : []) + language.rows
    }
    var height: CGFloat { max(320, 54 + CGFloat(rows.count + 1) * (keyHeight + 6) + 42) + (message == nil ? 0 : 45) + (preferences.predictions || searchTarget != nil || undo != nil ? 36 : 0) }
    var automaticUpper: Bool {
        guard preferences.autoCap, searchTarget == nil else { return false }
        let trait = controller?.textDocumentProxy.autocapitalizationType ?? .sentences
        if trait == .none { return false }
        if trait == .allCharacters { return true }
        if trait == .words { return context.isEmpty || context.last?.isWhitespace == true }
        return context.isEmpty || context.range(of: "[.!?\\n][ \\t]*$", options: .regularExpression) != nil
    }
    var upper: Bool { caps || (shiftOverride ?? automaticUpper) }

    func refreshContext() {
        context = controller?.textDocumentProxy.documentContextBeforeInput ?? ""
        if !canUndo { undo = nil }
        suggestionTask?.cancel()
        guard preferences.predictions, searchTarget == nil else { suggestions = []; return }
        guard let word = activeWord else {
            suggestions = preferences.nextWord ? localPrediction.next(context: context, language: language.id) : []
            suggestionWord = nil; suggestionDocument = controller?.textDocumentProxy.documentIdentifier
            return
        }
        if suggestionWord != word || suggestionDocument != controller?.textDocumentProxy.documentIdentifier { suggestions = [] }
        let language = self.language
        suggestionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled, let self, self.activeWord == word else { return }
            var words = self.suggestionEngine.suggestions(word: word, language: language, personal: self.personalWords[language.id] ?? [])
            if self.preferences.multilingual {
                for other in self.layouts.languages where other.id != language.id && self.preferences.enabledLanguages.contains(other.id) {
                    words += self.localPrediction.completions(word: word, language: other.id)
                }
            }
            self.suggestions = Array(NSOrderedSet(array: words).array.compactMap { $0 as? String }.prefix(3))
            self.suggestionWord = word
            self.suggestionDocument = self.controller?.textDocumentProxy.documentIdentifier
        }
    }

    var activeWord: String? {
        guard let proxy = controller?.textDocumentProxy, let before = proxy.documentContextBeforeInput else { return nil }
        return TextInputRules.currentWord(before: before, after: proxy.documentContextAfterInput ?? "", hasSelection: !(proxy.selectedText ?? "").isEmpty)
    }

    var canUndo: Bool {
        guard let undo, let proxy = controller?.textDocumentProxy else { return false }
        return proxy.documentIdentifier == undo.document && proxy.documentContextBeforeInput == undo.before
            && proxy.documentContextAfterInput == undo.after && (proxy.selectedText ?? "").isEmpty
    }

    func resetComposition() { composingWord = nil; composingDocument = nil; undo = nil; lastSpace = .distantPast; lastShift = .distantPast }

    func undoCorrection(keepDelimiter: Bool = true) {
        guard canUndo, let undo, let proxy = controller?.textDocumentProxy else { self.undo = nil; return }
        self.undo = nil
        for _ in undo.replacement + undo.delimiter { proxy.deleteBackward() }
        proxy.insertText(undo.original + (keepDelimiter ? undo.delimiter : ""))
        composingWord = nil; lastSpace = .distantPast; refreshContext()
    }

    func chooseSuggestion(_ suggestion: String) {
        if glideOptions.contains(suggestion) { replaceGlide(suggestion); return }
        if activeWord == nil, suggestions.contains(suggestion), suggestionWord == nil {
            insert(suggestion + " "); return
        }
        guard suggestions.contains(suggestion), let word = activeWord, word == suggestionWord,
              let proxy = controller?.textDocumentProxy, proxy.documentIdentifier == suggestionDocument else { return }
        resetComposition()
        for _ in word { proxy.deleteBackward() }
        proxy.insertText(suggestion + " ")
        refreshContext()
    }

    func rememberWord() {
        guard let word = activeWord else { return }
        var words = personalWords[language.id] ?? []
        if !words.contains(word) { words.insert(word, at: 0) }
        personalWords[language.id] = Array(words.prefix(500))
        if let data = try? JSONEncoder().encode(personalWords) { storage.set(data, forKey: "personalWords") }
        refreshContext(); notice("«\(word)» добавлено в твой словарь.")
    }

    func notice(_ text: String) {
        noticeTask?.cancel()
        message = text
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }

    func savePreferences() {
        do { storage.set(try JSONEncoder().encode(preferences), forKey: "preferences") }
        catch { notice("Не удалось сохранить настройки.") }
        controller?.primaryLanguage = language.locale
        controller?.updateHeight()
        refreshContext()
        clipboardMonitor.preferenceChanged()
    }

    func saveLibrary() {
        do { storage.set(try JSONEncoder().encode(library.clips), forKey: "clips") }
        catch { notice("Не удалось сохранить фрагменты.") }
        clipboardMonitor.historyDidChange()
    }

    func insert(_ text: String, space: Bool = false) {
        lastShift = .distantPast
        glideOptions = []; glideInserted = nil
        if preferences.haptics && controller?.hasFullAccess == true { UISelectionFeedbackGenerator().selectionChanged() }
        if let target = searchTarget {
            if text == "\n" { searchTarget = nil; panel = target }
            else if target == "emoji" { emojiQuery += text }
            else if target == "clips" { search += text }
            else { toolsQuery += text }
            return
        }
        guard let proxy = controller?.textDocumentProxy else { return }
        undo = nil
        let before = proxy.documentContextBeforeInput ?? ""
        let removedSelection = proxy.selectedText ?? ""
        let isBoundary = text == " " || text == "\n" || [".", ",", "!", "?", ";", ":"].contains(text)
        if preferences.autocorrect, isBoundary, proxy.autocorrectionType != .no,
           ![UIKeyboardType.emailAddress, .URL, .asciiCapable, .numbersAndPunctuation, .numberPad, .decimalPad].contains(proxy.keyboardType ?? .default),
           let word = activeWord, word == composingWord, composingDocument == proxy.documentIdentifier,
           !(preferences.multilingual && preferences.enabledLanguages.contains(where: { $0 != language.id && localPrediction.words(language: $0).contains(word.lowercased()) })),
           let fix = suggestionEngine.automaticCorrection(word: word, language: language, personal: personalWords[language.id] ?? []) {
            for _ in word { proxy.deleteBackward() }
            proxy.insertText(fix + text)
            if let actual = proxy.documentContextBeforeInput, actual.hasSuffix(fix + text) {
                undo = CorrectionUndo(original: word, replacement: fix, delimiter: text, before: actual, after: proxy.documentContextAfterInput, document: proxy.documentIdentifier)
            }
            composingWord = nil; lastSpace = space ? Date() : .distantPast
            shiftOverride = nil; refreshContext(); return
        }
        let isDoubleSpace = space && preferences.doubleSpace && Date().timeIntervalSince(lastSpace) < 0.4
            && proxy.selectedText == nil && before.range(of: "[\\p{L}\\p{N}] $", options: .regularExpression) != nil
        if isDoubleSpace {
            proxy.deleteBackward(); proxy.insertText(". "); lastSpace = .distantPast
        } else {
            proxy.insertText(text); lastSpace = space ? Date() : .distantPast
        }
        let inserted = isDoubleSpace ? ". " : text
        if let actual = proxy.documentContextBeforeInput, actual.hasSuffix(inserted), !inserted.isEmpty {
            lastInsertion = InsertionUndo(inserted: inserted, removed: isDoubleSpace ? " " : removedSelection,
                                          before: actual, after: proxy.documentContextAfterInput, document: proxy.documentIdentifier)
        }
        shiftOverride = nil
        composingWord = nil
        refreshContext()
    }

    func typeCharacter(_ char: String) {
        guard !gliding else { return }
        let oldWord = activeWord
        let previous = composingWord
        let previousDocument = composingDocument
        let text = symbolPage < 0 && upper ? char.uppercased(with: Locale(identifier: language.locale)) : char
        insert(text)
        if searchTarget == nil, char.first?.isLetter == true, let proxy = controller?.textDocumentProxy,
           oldWord == nil || (oldWord == previous && previousDocument == proxy.documentIdentifier) {
            composingWord = activeWord; composingDocument = proxy.documentIdentifier
        }
    }

    func delete() {
        lastShift = .distantPast
        if let target = searchTarget {
            if target == "emoji" { if !emojiQuery.isEmpty { emojiQuery.removeLast() } }
            else if target == "clips" { if !search.isEmpty { search.removeLast() } }
            else if !toolsQuery.isEmpty { toolsQuery.removeLast() }
            return
        }
        if canUndo { undoCorrection(keepDelimiter: false); return }
        let wasComposing = composingWord == activeWord && composingDocument == controller?.textDocumentProxy.documentIdentifier
        controller?.textDocumentProxy.deleteBackward()
        shiftOverride = nil; lastSpace = .distantPast; refreshContext()
        composingWord = wasComposing ? activeWord : nil
    }

    func shift() {
        if symbolPage >= 0 { symbolPage = (symbolPage + 1) % layouts.symbols.count; return }
        if Date().timeIntervalSince(lastShift) < 0.3 {
            caps.toggle(); shiftOverride = nil; lastShift = .distantPast
        } else {
            let wasUpper = upper
            caps = false; shiftOverride = !wasUpper; lastShift = Date()
        }
    }

    func nextLanguage() {
        let languages = preferences.enabledLanguages
        let index = languages.firstIndex(of: preferences.language) ?? 0
        selectLanguage(languages[(index + 1) % languages.count])
    }

    func selectLanguage(_ id: String) {
        guard preferences.enabledLanguages.contains(id) else { return }
        preferences.language = id
        resetComposition()
        caps = false; shiftOverride = nil; symbolPage = -1; savePreferences()
    }

    func moveCursor(_ offset: Int) {
        resetComposition()
        controller?.textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
        lastSpace = .distantPast; shiftOverride = nil; refreshContext()
    }

    func setLanguageEnabled(_ id: String, enabled: Bool) {
        if enabled {
            if !preferences.enabledLanguages.contains(id) { preferences.enabledLanguages.append(id) }
        } else {
            guard preferences.enabledLanguages.count > 1 else { notice("Оставь хотя бы один язык."); return }
            preferences.enabledLanguages.removeAll { $0 == id }
        }
        preferences.normalize(languages: layouts.languages)
        resetComposition(); caps = false; shiftOverride = nil; symbolPage = -1; savePreferences()
    }

    func startSearch(_ target: String) {
        resetComposition(); searchTarget = target; panel = "keys"; suggestions = []; symbolPage = -1
    }

    func beginGlide(at point: CGPoint) {
        guard preferences.glide, symbolPage < 0, searchTarget == nil else { return }
        gliding = true; glidePoints = [point]
        glideBefore = controller?.textDocumentProxy.documentContextBeforeInput
        glideAfter = controller?.textDocumentProxy.documentContextAfterInput
        glideDocument = controller?.textDocumentProxy.documentIdentifier
    }

    func finishGlide(centers: [String: CGPoint]) {
        defer { glidePoints = []; DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in self?.gliding = false } }
        guard gliding, let proxy = controller?.textDocumentProxy,
              proxy.documentIdentifier == glideDocument, proxy.documentContextBeforeInput == glideBefore,
              proxy.documentContextAfterInput == glideAfter, (proxy.selectedText ?? "").isEmpty else { return }
        let words = (personalWords[language.id] ?? []) + localPrediction.words(language: language.id)
        let options = GlideDecoder.rank(trace: glidePoints.map { TracePoint(x: Double($0.x), y: Double($0.y)) },
                                        centers: centers.mapValues { TracePoint(x: Double($0.x), y: Double($0.y)) }, words: words)
        guard let chosen = options.first else { notice("Не удалось распознать жест. Попробуй ещё раз."); return }
        let text = caps ? chosen.uppercased(with: Locale(identifier: language.locale)) : upper ? String(chosen.prefix(1)).uppercased(with: Locale(identifier: language.locale)) + chosen.dropFirst() : chosen
        insert(text + " ")
        glideOptions = options; glideInserted = text
        glideBefore = proxy.documentContextBeforeInput; glideAfter = proxy.documentContextAfterInput; glideDocument = proxy.documentIdentifier
    }

    func replaceGlide(_ word: String) {
        guard let proxy = controller?.textDocumentProxy, let inserted = glideInserted,
              glideOptions.contains(word), proxy.documentIdentifier == glideDocument,
              proxy.documentContextBeforeInput == glideBefore, proxy.documentContextAfterInput == glideAfter else { glideOptions = []; return }
        for _ in inserted + " " { proxy.deleteBackward() }
        proxy.insertText(word + " ")
        glideInserted = word; glideBefore = proxy.documentContextBeforeInput; refreshContext()
    }

    func insertEmoji(_ text: String) {
        resetComposition(); insert(text)
        recentEmoji.removeAll { $0 == text }; recentEmoji.insert(text, at: 0)
        recentEmoji = Array(recentEmoji.prefix(32)); storage.set(recentEmoji, forKey: "recentEmoji")
    }

    var visibleEmoji: [EmojiEntry] {
        let all = emoji.categories.flatMap(\.entries)
        if !emojiQuery.isEmpty {
            return all.filter { $0.name.localizedCaseInsensitiveContains(emojiQuery) || $0.keywords.localizedCaseInsensitiveContains(emojiQuery) || $0.text == emojiQuery }
        }
        if emojiCategory == "recent" {
            return recentEmoji.map { EmojiEntry(text: $0, name: $0, keywords: "", variants: []) }
        }
        return emoji.categories.first { $0.id == emojiCategory }?.entries ?? []
    }

    func addClip(_ text: String) {
        do { try library.add(text); saveLibrary(); notice("Фрагмент сохранён.") }
        catch { notice(error.localizedDescription) }
    }

    func saveSelection() {
        guard let text = controller?.textDocumentProxy.selectedText, !text.isEmpty else {
            notice("Сначала выдели текст в приложении."); return
        }
        addClip(text)
    }
}
