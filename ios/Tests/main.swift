import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

do {
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    let layouts = try JSONDecoder().decode(KeyboardLayouts.self, from: data)
    let kazakh = layouts.languages.first { $0.id == "kk" }!
    let keys = kazakh.rows.joined()
    for char in "әіңғүұқөһ" { expect(keys.contains(char), "Missing Kazakh letter: \(char)") }
    expect(layouts.languages.count == 8, "Expected eight language layouts")
    let oldPreferences = Data("{\"language\":\"ru\",\"theme\":\"ocean\",\"size\":\"large\",\"autoCap\":false}".utf8)
    var preferences = try JSONDecoder().decode(KeyboardPreferences.self, from: oldPreferences)
    expect(preferences.theme == "ocean" && preferences.size == "large" && !preferences.autoCap, "Preserve existing settings")
    expect(preferences.enabledLanguages == ["kk", "ru", "en"] && preferences.autocorrect && preferences.predictions, "Default new settings")
    preferences.enabledLanguages = ["de", "de", "missing"]
    preferences.normalize(languages: layouts.languages)
    expect(preferences.enabledLanguages == ["de"] && preferences.language == "de", "Normalize installed languages")
    preferences.enabledLanguages = []
    preferences.normalize(languages: layouts.languages)
    expect(preferences.enabledLanguages == ["kk"], "Protect the final language")
    expect(TextInputRules.currentWord(before: "Сәлем, превет") == "превет", "Find trailing word")
    for input in ["mail@превет", "https://превет", "test.превет", "@превет", "#превет", "id123превет"] {
        expect(TextInputRules.currentWord(before: input) == nil, "Protect identifiers: \(input)")
    }
    expect(TextInputRules.currentWord(before: "прев", after: "ет") == nil, "Protect mid-word editing")
    expect(TextInputRules.currentWord(before: "превет", hasSelection: true) == nil, "Protect selection")
    expect(TextInputRules.distance("teh", "the") == 1, "Handle transposed letters")
    expect(TextInputRules.preservingCase("привет", original: "Превет", locale: "ru-RU") == "Привет", "Keep title case")
    let lexiconData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
    let lexicons = try JSONDecoder().decode([String: WordLexicon].self, from: lexiconData)
    expect(TextInputRules.suggestions(for: "салем", lexicon: lexicons["kk"], personalWords: [], locale: "kk-KZ").first == "сәлем", "Suggest Kazakh correction")
    let emojiData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
    let emoji = try JSONDecoder().decode(EmojiCatalog.self, from: emojiData)
    let emojiEntries = emoji.categories.flatMap(\.entries)
    expect(emoji.categories.count == 9 && emoji.sequenceCount == 3781, "Decode full emoji catalog")
    let sequences = emojiEntries.flatMap { [$0.text] + $0.variants }
    expect(sequences.count == 3781 && Set(sequences).count == 3781, "Preserve all emoji sequences")
    expect(emojiEntries.first { $0.text == "👍" }?.displayed(tone: "🏽") == "👍🏽", "Preserve emoji skin tone")
    expect(sequences.contains("👨‍👩‍👧‍👦"), "Preserve joined emoji")
    let predictionData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[4]))
    let prediction = try JSONSerialization.jsonObject(with: predictionData) as! [String: Any]
    let vocabularies = prediction["languages"] as! [String: [String]]
    expect(vocabularies.count == 8 && vocabularies["kk"]!.count > 4000, "Bundle real vocabularies")
    var centers: [String: TracePoint] = [:]
    for (y, row) in ["qwertyuiop", "asdfghjkl", "zxcvbnm"].enumerated() {
        for (x, char) in row.enumerated() { centers[String(char)] = TracePoint(x: (Double(x) + Double(y) * 0.4) * 30, y: Double(y) * 45) }
    }
    let trace = GlideDecoder.resample([centers["h"]!, centers["e"]!, centers["l"]!, centers["o"]!], count: 50)
    expect(GlideDecoder.rank(trace: trace, centers: centers, words: ["help", "hello", "held", "home"]).first == "hello", "Decode a swipe, including repeated letters")
    expect(GlideDecoder.rank(trace: trace, centers: centers, words: vocabularies["en"]!).first == "hello", "Decode against the full vocabulary")
    expect(GlideDecoder.rank(trace: [centers["h"]!, centers["h"]!], centers: centers, words: ["hello"]).isEmpty, "Do not interpret a tap as a swipe")
    var library = ClipLibrary()
    try library.add("Сәлем 👋🏽")
    let firstID = library.clips[0].id
    library.togglePin(firstID)
    try library.add("Another")
    try library.add("Сәлем 👋🏽")
    expect(library.clips.count == 2, "Deduplicate copied text")
    expect(library.clips[0].id == firstID && library.clips[0].pinned, "Keep pin and identity")
    library.clearUnpinned()
    expect(library.clips.count == 1, "Keep pinned clips on clear")
    for i in 0..<12 { try library.add("item \(i)") }
    try library.add("newest")
    expect(library.history.count == 10, "Bound history to ten")
    expect(library.history.first?.text == "newest", "Newest copy first")
    expect(library.clips.contains { $0.id == firstID }, "Never evict pinned clips")
    expect(!library.history.contains { $0.id == firstID }, "Old favorite must not occupy a recent-history slot")
    expect(!library.clips.contains { $0.text == "item 0" }, "Evict oldest unpinned")
    for clip in library.clips where !clip.pinned { library.togglePin(clip.id) }
    try library.add("overflow")
    expect(library.history.count == 10 && library.history.first?.text == "overflow", "Pinned entries cannot block a new copy")
    library.clearHistory()
    expect(library.history.isEmpty && !library.favorites.isEmpty, "Clear recent history while retaining favorites")
    let oldLibrary = ClipLibrary(clips: (0..<100).map { SavedClip(text: "legacy \($0)", pinned: $0 == 99) })
    expect(oldLibrary.history.count == 10 && oldLibrary.favorites.count == 1 && oldLibrary.clips.count == 11, "Migrate old history")
    do { try library.add("  \n"); fatalError("Should reject blank") }
    catch ClipError.empty { }
    do { try library.add(String(repeating: "a", count: 10001)); fatalError("Should reject long text") }
    catch ClipError.tooLong { }
    let encoded = try JSONEncoder().encode(library.clips)
    let decoded = try JSONDecoder().decode([SavedClip].self, from: encoded)
    expect(decoded == library.clips, "Persistence round trip")
    print("Native logic checks passed")
} catch { fatalError("Unexpected test failure: \(error)") }
