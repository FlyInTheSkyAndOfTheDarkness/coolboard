import SwiftUI
import UIKit

struct ExtraKeyboardPanel: View {
    @ObservedObject var model: KeyboardModel
    private let phrases = ["Сәлем!", "Рақмет!", "Керемет!", "Привет!", "Спасибо!", "Обнимаю", "OK!", "Супер!"]
    private let kaomoji = ["¯\\_(ツ)_/¯", "(╯°□°)╯︵ ┻━┻", "(づ｡◕‿‿◕｡)づ", "ಠ_ಠ", "ʕ•ᴥ•ʔ", "(•̀ᴗ•́)و", "♡", ":-)", ":-D"]

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button("‹ Клавиатура") { model.searchTarget = nil; model.panel = "keys" }
                Spacer()
                Text(title).fontWeight(.semibold)
            }.font(.system(size: 12)).padding(.horizontal, 5)
            ScrollView {
                if model.panel == "tools" { hub }
                else if model.panel == "stickers" { stickers }
                else if model.panel == "voice" { voice }
                else { online }
            }
        }.buttonStyle(.plain).font(.system(size: 13))
    }
    private var title: String {
        switch model.panel {
        case "gifs": return "GIF · Wikimedia"
        case "translate": return "Перевод · MyMemory"
        case "web": return "Поиск · Wikipedia"
        case "stickers": return "Стикеры и смайлики"
        case "voice": return "Голосовой ввод"
        default: return "Все инструменты"
        }
    }
    private var hub: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                tile("arrow.triangle.path", "Перевод") { model.openTool("translate") }
                tile("photo.on.rectangle", "GIF") { model.openTool("gifs") }
                tile("sparkles.rectangle.stack", "Стикеры") { model.openTool("stickers") }
                tile("magnifyingglass", "Поиск") { model.openTool("web") }
                tile("mic", "Голос") { model.openTool("voice") }
                tile("doc.on.clipboard", "Буфер") { model.panel = "clips" }
                tile("arrow.left", "Курсор ←") { model.moveCursor(-1) }
                tile("arrow.right", "Курсор →") { model.moveCursor(1) }
                tile("delete.left", "Удалить слово") { model.deletePreviousWord() }
                tile("arrow.uturn.backward", "Отмена вставки") { model.undoLastInsertion() }
                tile("doc.on.doc", "Копировать") { model.copySelectedText() }
                tile("text.badge.plus", "Сохранить") { model.saveSelection() }
                tile("gearshape", "Настройки") { model.panel = "settings" }
            }
            Picker("Одной рукой", selection: $model.preferences.oneHanded) {
                Text("Обычно").tag("off"); Text("Слева").tag("left"); Text("Справа").tag("right")
            }.pickerStyle(.segmented).onChange(of: model.preferences.oneHanded) { _ in model.savePreferences() }
        }.padding(4)
    }
    private func tile(_ image: String, _ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) { Image(systemName: image).font(.system(size: 20)); Text(text).font(.system(size: 10)).lineLimit(1) }
                .frame(maxWidth: .infinity).frame(height: 64)
                .background(Color(model.palette.special)).cornerRadius(8)
        }
    }
    private var stickers: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Нажми стикер, затем выбери «Вставить» в чате.").font(.system(size: 11)).foregroundColor(Color(model.palette.muted))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                ForEach(phrases, id: \.self) { phrase in
                    Button { model.copySticker(phrase) } label: {
                        Text(phrase).font(.system(size: 17, weight: .bold)).frame(maxWidth: .infinity).frame(height: 54)
                            .foregroundColor(.white).background(Color.blue).cornerRadius(18)
                    }
                }
            }
            Text("Текстовые смайлики").fontWeight(.semibold)
            ForEach(kaomoji, id: \.self) { text in Button(text) { model.insert(text) }.padding(5) }
            HStack { Text("Свои GIF и картинки").fontWeight(.semibold); Spacer(); Button("＋ Из буфера") { model.importMedia() } }
            ForEach(model.savedMedia) { item in
                HStack {
                    if let image = UIImage(contentsOfFile: MediaLibrary.directory.appendingPathComponent(item.filename).path) {
                        Image(uiImage: image).resizable().scaledToFit().frame(width: 70, height: 50)
                    }
                    Button(item.type.contains("gif") ? "Скопировать GIF" : "Скопировать картинку") { model.copyMedia(item) }
                    Spacer()
                    Button { model.removeMedia(item) } label: { Image(systemName: "trash") }.accessibilityLabel("Удалить картинку")
                }
            }
        }.padding(5)
    }
    private var voice: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "mic.circle").font(.system(size: 38))
            Text("Запись доступна в приложении CoolBoard") .font(.system(size: 16, weight: .semibold))
            Text("iOS не даёт расширению клавиатуры доступ к микрофону. Открой CoolBoard → «Голос», запиши текст, скопируй результат и вернись в чат. В буфере клавиатуры можно сохранить его для повторной вставки.")
            Text("Или переключись через 🌐 на клавиатуру Apple и используй системную диктовку.")
        }.padding(8)
    }
    private var online: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.preferences.online {
                Text("Запрос отправляется MyMemory для перевода или Wikimedia для поиска и GIF. Набираемый текст автоматически не отправляется.").font(.system(size: 12))
                Button("Включить онлайн-функции") { model.preferences.online = true; model.savePreferences() }
                    .padding(10).background(Color(model.palette.special)).cornerRadius(7)
            }
            Button(model.toolsQuery.isEmpty ? "⌕ Ввести запрос" : model.toolsQuery) { model.startSearch(model.panel) }
                .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading).padding(10)
                .background(Color(model.palette.special)).cornerRadius(7)
            if model.panel == "translate" {
                Picker("Перевести на", selection: $model.translationTarget) {
                    ForEach(model.layouts.languages) { language in Text(language.name ?? language.title).tag(language.id) }
                }
            } else if model.panel == "web" {
                Text("Здесь — результаты Wikipedia. Полный поиск Google и Google Translate доступны через экран «Поиск» приложения CoolBoard.")
                    .font(.system(size: 10)).foregroundColor(Color(model.palette.muted))
            }
            HStack {
                Button("Из выделенного") {
                    model.toolsQuery = model.controller?.textDocumentProxy.selectedText ?? ""
                }
                Spacer()
                Button(model.panel == "translate" ? "Перевести" : "Найти") { model.runOnlineTool() }
                    .disabled(model.toolsLoading)
            }
            if model.toolsLoading { ProgressView() }
            if let error = model.toolsError { Text(error).font(.system(size: 11)).foregroundColor(Color(model.palette.muted)) }
            if let result = model.toolsResult {
                Text(result).textSelection(.enabled).padding(8)
                Button("Вставить перевод") { model.insert(result); model.panel = "keys" }
            }
            ForEach(model.toolsItems) { item in
                HStack {
                    if model.panel == "gifs" {
                        AsyncImage(url: item.thumbnail) { image in image.resizable().scaledToFit() } placeholder: { ProgressView() }
                            .frame(width: 80, height: 60)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title).font(.system(size: 12)).lineLimit(2)
                        if model.panel == "gifs" {
                            Button("Скопировать GIF") { model.copyGIF(item) }
                            Button("Вставить ссылку на источник") { model.insert(item.source.absoluteString) }.font(.system(size: 10))
                        } else { Button("Вставить ссылку") { model.insert(item.title + " " + item.url.absoluteString) } }
                    }
                }.padding(7).frame(maxWidth: .infinity, alignment: .leading).background(Color(model.palette.special)).cornerRadius(8)
            }
        }.padding(5)
    }
}

struct LetterFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
