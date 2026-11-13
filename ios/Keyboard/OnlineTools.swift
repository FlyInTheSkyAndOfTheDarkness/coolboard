import UIKit
import UniformTypeIdentifiers

struct OnlineItem: Identifiable {
    let id: String
    let title: String
    let url: URL
    let thumbnail: URL?
    let source: URL
    let bytes: Int
}

enum OnlineError: LocalizedError {
    case invalid, size, message(String)
    var errorDescription: String? {
        switch self {
        case .invalid: return "Сервис вернул неподходящий ответ. Попробуй другой запрос."
        case .size: return "Для перевода — до 500 байт текста; для картинки — до 3 МБ."
        case .message(let text): return text
        }
    }
}

enum OnlineTools {
    static func json(_ base: String, _ params: [String: String]) async throws -> [String: Any] {
        var components = URLComponents(string: base)!
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.setValue("CoolBoard/0.3 (personal iOS keyboard)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 2_000_000,
              let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw OnlineError.invalid }
        return result
    }

    static func translate(_ text: String, from: String, to: String) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OnlineError.message("Введи текст для перевода.") }
        guard text.utf8.count <= 500 else { throw OnlineError.size }
        if from == to { return text }
        let result = try await json("https://api.mymemory.translated.net/get", ["q": text, "langpair": from + "|" + to])
        guard (result["responseStatus"] as? Int) == 200, result["quotaFinished"] as? Bool != true,
              let data = result["responseData"] as? [String: Any], let translated = data["translatedText"] as? String else {
            throw OnlineError.message(result["responseDetails"] as? String ?? "Перевод недоступен или исчерпан лимит сервиса.")
        }
        return translated
    }

    static func search(_ query: String, language: String) async throws -> [OnlineItem] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OnlineError.message("Введи запрос.") }
        let lang = ["kk", "ru", "en", "uk", "de", "tr", "fr", "es"].contains(language) ? language : "en"
        let data = try await json("https://\(lang).wikipedia.org/w/api.php", ["action": "query", "list": "search", "srsearch": String(query.prefix(150)), "srlimit": "8", "format": "json", "origin": "*"])
        let results = ((data["query"] as? [String: Any])?["search"] as? [[String: Any]]) ?? []
        return results.compactMap { item in
            guard let title = item["title"] as? String, let id = item["pageid"] as? Int,
                  let url = URL(string: "https://\(lang).wikipedia.org/?curid=\(id)") else { return nil }
            return OnlineItem(id: String(id), title: title, url: url, thumbnail: nil, source: url, bytes: 0)
        }
    }

    static func gifs(_ query: String) async throws -> [OnlineItem] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { throw OnlineError.message("Введи, какие GIF найти.") }
        let data = try await json("https://commons.wikimedia.org/w/api.php", ["action": "query", "generator": "search", "gsrsearch": String(term.prefix(100)) + " filemime:image/gif", "gsrnamespace": "6", "gsrlimit": "12", "prop": "imageinfo", "iiprop": "url|mime|size", "iiurlwidth": "160", "format": "json", "origin": "*"])
        let pages = ((data["query"] as? [String: Any])?["pages"] as? [String: [String: Any]]) ?? [:]
        return pages.values.compactMap { page in
            guard let info = (page["imageinfo"] as? [[String: Any]])?.first,
                  info["mime"] as? String == "image/gif", let raw = info["url"] as? String,
                  let url = URL(string: raw), url.host == "upload.wikimedia.org",
                  let source = URL(string: info["descriptionurl"] as? String ?? ""),
                  let size = info["size"] as? Int, size <= 3_000_000 else { return nil }
            return OnlineItem(id: raw, title: (page["title"] as? String ?? "GIF").replacingOccurrences(of: "File:", with: ""), url: url,
                              thumbnail: URL(string: info["thumburl"] as? String ?? raw), source: source, bytes: size)
        }.sorted { $0.title < $1.title }
    }

    static func download(_ item: OnlineItem) async throws -> Data {
        guard item.url.scheme == "https", item.url.host == "upload.wikimedia.org", item.bytes <= 3_000_000 else { throw OnlineError.size }
        let (bytes, response) = try await URLSession.shared.bytes(from: item.url)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              response.expectedContentLength <= 3_000_000 else { throw OnlineError.invalid }
        var data = Data()
        for try await byte in bytes { data.append(byte); if data.count > 3_000_000 { throw OnlineError.size } }
        guard ["GIF87a", "GIF89a"].contains(String(data: data.prefix(6), encoding: .ascii) ?? "") else { throw OnlineError.invalid }
        return data
    }
}

struct SavedMedia: Codable, Identifiable {
    let id: UUID
    let filename: String
    let type: String
}

enum MediaLibrary {
    static let directory: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CoolBoardMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    static func load() -> [SavedMedia] {
        UserDefaults.standard.data(forKey: "mediaLibrary").flatMap { try? JSONDecoder().decode([SavedMedia].self, from: $0) } ?? []
    }
    static func save(_ data: Data, type: String, existing: [SavedMedia]) throws -> SavedMedia {
        let bytes = existing.reduce(0) { sum, item in sum + ((try? directory.appendingPathComponent(item.filename).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        guard data.count <= 3_000_000, bytes + data.count <= 6_000_000, existing.count < 12 else { throw OnlineError.message("Библиотека: до 12 файлов и 6 МБ. Удали один из сохранённых.") }
        let id = UUID(), filename = UUID().uuidString + (type == UTType.gif.identifier ? ".gif" : ".png")
        try data.write(to: directory.appendingPathComponent(filename), options: [.atomic, .completeFileProtection])
        return SavedMedia(id: id, filename: filename, type: type)
    }
    static func persist(_ items: [SavedMedia]) { if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: "mediaLibrary") } }
}

extension KeyboardModel {
    func openTool(_ name: String) {
        toolsTask?.cancel(); toolsGeneration = UUID(); toolsLoading = false
        toolsQuery = ""; toolsResult = nil; toolsItems = []; toolsError = nil; searchTarget = nil; panel = name
    }
    func runOnlineTool() {
        guard preferences.online else { toolsError = "Включи онлайн-функции: запрос отправляется MyMemory или Wikimedia."; return }
        guard controller?.hasFullAccess == true else { toolsError = "Для сети включи «Полный доступ» в настройках CoolBoard."; return }
        let tool = panel, query = toolsQuery, lang = language.id, target = translationTarget, generation = UUID()
        toolsGeneration = generation; toolsTask?.cancel(); toolsLoading = true; toolsError = nil; toolsItems = []; toolsResult = nil
        toolsTask = Task { [weak self] in
            do {
                var text: String?, items: [OnlineItem] = []
                if tool == "translate" { text = try await OnlineTools.translate(query, from: lang, to: target) }
                else if tool == "gifs" { items = try await OnlineTools.gifs(query) }
                else { items = try await OnlineTools.search(query, language: lang) }
                guard let self, !Task.isCancelled, self.toolsGeneration == generation else { return }
                self.toolsResult = text; self.toolsItems = items; self.toolsLoading = false
                if text == nil && items.isEmpty { self.toolsError = "Ничего не найдено. Попробуй другой запрос." }
            } catch {
                guard let self, !Task.isCancelled, self.toolsGeneration == generation else { return }
                self.toolsLoading = false; self.toolsError = error.localizedDescription
            }
        }
    }
    func copyGIF(_ item: OnlineItem) {
        guard controller?.hasFullAccess == true, preferences.online else { notice("Нужны полный доступ и включённые онлайн-функции."); return }
        toolsTask?.cancel(); toolsLoading = true
        toolsTask = Task { [weak self] in
            do {
                let data = try await OnlineTools.download(item)
                guard !Task.isCancelled, let self else { return }
                UIPasteboard.general.setData(data, forPasteboardType: UTType.gif.identifier)
                self.toolsLoading = false; self.notice("GIF скопирован. Нажми «Вставить» в приложении.")
            } catch { guard !Task.isCancelled, let self else { return }; self.toolsLoading = false; self.notice(error.localizedDescription) }
        }
    }
    func importMedia() {
        guard controller?.hasFullAccess == true else { notice("Нужен полный доступ к буферу."); return }
        do {
            let pasteboard = UIPasteboard.general
            let gif = pasteboard.data(forPasteboardType: UTType.gif.identifier)
            guard let data = gif ?? pasteboard.image?.pngData() else { notice("В буфере нет GIF или картинки."); return }
            let item = try MediaLibrary.save(data, type: gif == nil ? UTType.png.identifier : UTType.gif.identifier, existing: savedMedia)
            savedMedia.insert(item, at: 0); MediaLibrary.persist(savedMedia); notice("Картинка сохранена.")
        } catch { notice(error.localizedDescription) }
    }
    func copyMedia(_ item: SavedMedia) {
        guard controller?.hasFullAccess == true else { notice("Нужен полный доступ к буферу."); return }
        guard let data = try? Data(contentsOf: MediaLibrary.directory.appendingPathComponent(item.filename)) else { notice("Файл не найден."); return }
        UIPasteboard.general.setData(data, forPasteboardType: item.type); notice("Скопировано. Выбери «Вставить» в приложении.")
    }
    func removeMedia(_ item: SavedMedia) {
        try? FileManager.default.removeItem(at: MediaLibrary.directory.appendingPathComponent(item.filename))
        savedMedia.removeAll { $0.id == item.id }; MediaLibrary.persist(savedMedia)
    }
    func copySticker(_ phrase: String) {
        guard controller?.hasFullAccess == true else { notice("Для копирования картинки нужен полный доступ."); return }
        let format = UIGraphicsImageRendererFormat(); format.opaque = false; format.scale = 2
        let image = UIGraphicsImageRenderer(size: CGSize(width: 280, height: 120), format: format).image { _ in
            UIColor(red: 0.18, green: 0.43, blue: 0.9, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 4, y: 4, width: 272, height: 112), cornerRadius: 34).fill()
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
            (phrase as NSString).draw(in: CGRect(x: 10, y: 37, width: 260, height: 60), withAttributes: [.font: UIFont.systemFont(ofSize: 30, weight: .bold), .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
        }
        if let data = image.pngData() { UIPasteboard.general.setData(data, forPasteboardType: UTType.png.identifier); notice("Стикер скопирован. Выбери «Вставить» в чате.") }
    }
    func setPhotoBackground() {
        guard controller?.hasFullAccess == true, let image = UIPasteboard.general.image else { notice("Скопируй фото и включи полный доступ."); return }
        let size = CGSize(width: 700, height: 500)
        let scaled = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        if let data = scaled.jpegData(compressionQuality: 0.65) {
            do { try data.write(to: MediaLibrary.directory.appendingPathComponent("background.jpg"), options: [.atomic, .completeFileProtection]); backgroundData = data; preferences.theme = "photo"; savePreferences() }
            catch { notice(error.localizedDescription) }
        }
    }
    func deletePreviousWord() {
        guard let proxy = controller?.textDocumentProxy, let before = proxy.documentContextBeforeInput else { return }
        resetComposition()
        if !(proxy.selectedText ?? "").isEmpty { proxy.deleteBackward(); refreshContext(); return }
        let range = before.range(of: "(?:[\\p{L}\\p{M}\\p{N}'’]+|[^\\p{L}\\p{M}\\p{N}\\s]+)\\s*$", options: .regularExpression)
            ?? before.range(of: "\\s+$", options: .regularExpression)
        if let range { for _ in before[range] { proxy.deleteBackward() } }
        refreshContext()
    }
    func copySelectedText() {
        guard controller?.hasFullAccess == true else { notice("Для копирования нужен полный доступ."); return }
        guard let text = controller?.textDocumentProxy.selectedText, !text.isEmpty else { notice("Выдели текст в приложении."); return }
        UIPasteboard.general.string = text; notice("Выделенный текст скопирован.")
    }
    func undoLastInsertion() {
        if canUndo { undoCorrection(); return }
        guard let edit = lastInsertion, let proxy = controller?.textDocumentProxy,
              proxy.documentIdentifier == edit.document, proxy.documentContextBeforeInput == edit.before,
              proxy.documentContextAfterInput == edit.after, (proxy.selectedText ?? "").isEmpty else { notice("Последнюю вставку уже нельзя отменить."); return }
        lastInsertion = nil
        for _ in edit.inserted { proxy.deleteBackward() }
        if !edit.removed.isEmpty { proxy.insertText(edit.removed) }
        resetComposition(); refreshContext()
    }
}
