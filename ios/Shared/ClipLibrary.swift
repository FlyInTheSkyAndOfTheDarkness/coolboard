import Foundation

struct SavedClip: Codable, Identifiable, Equatable {
    var id = UUID()
    let text: String
    var pinned = false
    var inHistory = true

    init(id: UUID = UUID(), text: String, pinned: Bool = false, inHistory: Bool = true) {
        self.id = id; self.text = text; self.pinned = pinned; self.inHistory = inHistory
    }
    enum CodingKeys: String, CodingKey { case id, text, pinned, inHistory }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        text = try values.decode(String.self, forKey: .text)
        pinned = try values.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        inHistory = try values.decodeIfPresent(Bool.self, forKey: .inHistory) ?? true
    }
}

enum ClipError: LocalizedError {
    case empty, tooLong
    var errorDescription: String? {
        switch self {
        case .empty: return "В буфере нет текста."
        case .tooLong: return "Максимум 10 000 символов в одном фрагменте."
        }
    }
}

struct ClipLibrary {
    static let limit = 10
    static let favoriteLimit = 100
    private(set) var clips: [SavedClip]

    init(clips: [SavedClip] = []) {
        var texts = Set<String>(), ids = Set<UUID>(), recent = 0, favorites = 0
        self.clips = clips.compactMap { original in
            guard !original.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  original.text.utf16.count <= 10000, texts.insert(original.text).inserted, ids.insert(original.id).inserted else { return nil }
            var clip = original
            if clip.pinned { favorites += 1; if favorites > Self.favoriteLimit { clip.pinned = false } }
            if clip.inHistory { recent += 1; if recent > Self.limit { clip.inHistory = false } }
            return clip.inHistory || clip.pinned ? clip : nil
        }
    }

    var history: [SavedClip] { clips.filter(\.inHistory) }
    var favorites: [SavedClip] { clips.filter(\.pinned) }

    mutating func add(_ text: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClipError.empty }
        guard text.utf16.count <= 10000 else { throw ClipError.tooLong }
        var existing = clips.first { $0.text == text } ?? SavedClip(text: text)
        existing.inHistory = true
        var next = clips.filter { $0.text != text }
        next.insert(existing, at: 0)
        clips = ClipLibrary(clips: next).clips
    }

    @discardableResult mutating func togglePin(_ id: UUID) -> Bool {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return false }
        guard clips[index].pinned || favorites.count < Self.favoriteLimit else { return false }
        clips[index].pinned.toggle()
        if !clips[index].pinned && !clips[index].inHistory { clips.remove(at: index) }
        return true
    }

    mutating func remove(_ id: UUID) { clips.removeAll { $0.id == id } }
    mutating func clearUnpinned() { clips.removeAll { !$0.pinned } }
    mutating func clearHistory() {
        clips = clips.filter(\.pinned).map { var clip = $0; clip.inHistory = false; return clip }
    }

    func filtered(_ query: String, favoritesOnly: Bool = false) -> [SavedClip] {
        (favoritesOnly ? favorites : history).filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) }
    }
}
