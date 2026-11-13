import Foundation

/// The view and its controller share one height calculation. The system owns
/// the globe/dictation area below the extension; it isn't part of this height.
struct KeyboardMetrics {
    let size: String
    let landscape: Bool
    let letterRows: Int

    let headerHeight: CGFloat = 34
    let contentSpacing: CGFloat = 4
    let verticalPadding: CGFloat = 4
    var rowSpacing: CGFloat { landscape ? 4 : 6 }
    var keyHeight: CGFloat {
        if landscape { return size == "compact" ? 28 : size == "large" ? 36 : 32 }
        return size == "compact" ? 36 : size == "large" ? 48 : 42
    }
    var keysHeight: CGFloat {
        CGFloat(letterRows + 1) * keyHeight + CGFloat(letterRows) * rowSpacing
    }
    var typingHeight: CGFloat {
        headerHeight + contentSpacing + keysHeight + verticalPadding * 2
    }
}

struct KeyboardLanguage: Decodable, Identifiable, Sendable {
    let id: String
    let title: String
    let name: String?
    let locale: String
    let rows: [String]
}

struct KeyboardLayouts: Decodable {
    let languages: [KeyboardLanguage]
    let symbols: [[String]]

    static func load(bundle: Bundle = .main) -> KeyboardLayouts {
        guard let url = bundle.url(forResource: "layouts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let layouts = try? JSONDecoder().decode(KeyboardLayouts.self, from: data),
              !layouts.languages.isEmpty, !layouts.symbols.isEmpty else {
            // The build should always include layouts.json. Keep typing possible if it is missing.
            return KeyboardLayouts(languages: [KeyboardLanguage(id: "en", title: "ENG", name: "English", locale: "en-US", rows: ["qwertyuiop", "asdfghjkl", "zxcvbnm"])], symbols: [["1234567890", "-/:;()&@\"", ".,?!'"]])
        }
        return layouts
    }
}

struct KeyboardPreferences: Codable {
    var language = "kk"
    var enabledLanguages = ["kk", "ru", "en"]
    var theme = "gboard"
    var size = "normal"
    var numberRow = false
    var autoCap = true
    var doubleSpace = true
    var predictions = true
    var autocorrect = true
    var emojiTone = ""
    var glide = true
    var multilingual = true
    var nextWord = true
    var haptics = false
    var oneHanded = "off"
    var online = false
    var autoClipboard = true

    enum CodingKeys: String, CodingKey {
        case language, enabledLanguages, theme, size, numberRow, autoCap, doubleSpace, predictions, autocorrect, emojiTone
        case glide, multilingual, nextWord, haptics, oneHanded, online
        case autoClipboard
    }

    init() {}

    // Migrate existing installations without resetting themes or other preferences.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        language = try values.decodeIfPresent(String.self, forKey: .language) ?? "kk"
        enabledLanguages = try values.decodeIfPresent([String].self, forKey: .enabledLanguages) ?? ["kk", "ru", "en"]
        theme = try values.decodeIfPresent(String.self, forKey: .theme) ?? "gboard"
        size = try values.decodeIfPresent(String.self, forKey: .size) ?? "normal"
        numberRow = try values.decodeIfPresent(Bool.self, forKey: .numberRow) ?? false
        autoCap = try values.decodeIfPresent(Bool.self, forKey: .autoCap) ?? true
        doubleSpace = try values.decodeIfPresent(Bool.self, forKey: .doubleSpace) ?? true
        predictions = try values.decodeIfPresent(Bool.self, forKey: .predictions) ?? true
        autocorrect = try values.decodeIfPresent(Bool.self, forKey: .autocorrect) ?? true
        emojiTone = try values.decodeIfPresent(String.self, forKey: .emojiTone) ?? ""
        glide = try values.decodeIfPresent(Bool.self, forKey: .glide) ?? true
        multilingual = try values.decodeIfPresent(Bool.self, forKey: .multilingual) ?? true
        nextWord = try values.decodeIfPresent(Bool.self, forKey: .nextWord) ?? true
        haptics = try values.decodeIfPresent(Bool.self, forKey: .haptics) ?? false
        oneHanded = try values.decodeIfPresent(String.self, forKey: .oneHanded) ?? "off"
        online = try values.decodeIfPresent(Bool.self, forKey: .online) ?? false
        autoClipboard = try values.decodeIfPresent(Bool.self, forKey: .autoClipboard) ?? true
    }

    mutating func normalize(languages: [KeyboardLanguage]) {
        let valid = Set(languages.map(\.id))
        var seen = Set<String>()
        enabledLanguages = enabledLanguages.filter { valid.contains($0) && seen.insert($0).inserted }
        if enabledLanguages.isEmpty, let first = languages.first { enabledLanguages = [first.id] }
        if !enabledLanguages.contains(language) { language = enabledLanguages.first ?? "en" }
        if !["gboard", "graphite", "paper", "ocean", "rose", "photo"].contains(theme) { theme = "gboard" }
        if !["compact", "normal", "large"].contains(size) { size = "normal" }
        if !["", "🏻", "🏼", "🏽", "🏾", "🏿"].contains(emojiTone) { emojiTone = "" }
        if !["off", "left", "right"].contains(oneHanded) { oneHanded = "off" }
    }
}
