import SwiftUI
import UIKit

struct KeyboardPalette {
    let background: UIColor
    let key: UIColor
    let special: UIColor
    let text: UIColor
    let accent: UIColor
    let onAccent: UIColor
    let muted: UIColor

    static func named(_ name: String) -> KeyboardPalette {
        let colors: [UInt32]
        switch name {
        case "gboard": colors = [0xd4d7de, 0xffffff, 0xb7bdc8, 0x202124, 0x4285f4, 0xffffff, 0x626872]
        case "paper": colors = [0xdadfd5, 0xffffff, 0xc0c9b8, 0x2d3528, 0x667d4b, 0xffffff, 0x505e45]
        case "ocean": colors = [0x192e3d, 0x304a5e, 0x243d4d, 0xedf7fc, 0xa4d9ed, 0x1b3442, 0xaac2d0]
        case "rose": colors = [0x3b2d36, 0x59434f, 0x48353f, 0xfff0f5, 0xebc4d4, 0x432d39, 0xd0b6c3]
        default: colors = [0x262c2a, 0x414844, 0x343b37, 0xf0f1eb, 0xd5e8ac, 0x283020, 0xb1bbab]
        }
        func color(_ i: Int) -> UIColor {
            let hex = colors[i]
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
        return KeyboardPalette(background: color(0), key: color(1), special: color(2), text: color(3), accent: color(4), onAccent: color(5), muted: color(6))
    }
}

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel
    @State private var letterFrames: [String: CGRect] = [:]

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: model.preferences.oneHanded == "right" ? .leading : .trailing) {
                keyboardContent
                    .frame(width: model.preferences.oneHanded == "off" ? geometry.size.width : geometry.size.width * 0.84)
                    .frame(maxWidth: .infinity, alignment: model.preferences.oneHanded == "right" ? .trailing : .leading)
                if model.preferences.oneHanded != "off" {
                    Button { model.preferences.oneHanded = "off"; model.savePreferences() } label: {
                        Image(systemName: model.preferences.oneHanded == "right" ? "chevron.left" : "chevron.right")
                            .frame(width: geometry.size.width * 0.15, height: 70)
                    }.buttonStyle(.plain).foregroundColor(Color(model.palette.muted)).accessibilityLabel("Обычная ширина клавиатуры")
                }
            }.background(Color(model.palette.background))
        }
        .ignoresSafeArea(.keyboard)
    }

    private var keyboardContent: some View {
        VStack(spacing: model.metrics.contentSpacing) {
            toolbar
            if model.panel == "clips" { clips }
            else if model.panel == "emoji" { emojiPanel }
            else if model.panel == "settings" { settings }
            else if ["tools", "translate", "gifs", "web", "stickers", "voice"].contains(model.panel) { ExtraKeyboardPanel(model: model) }
            else { keys }
        }
        .padding(.horizontal, 5).padding(.vertical, model.metrics.verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            if model.preferences.theme == "photo", let data = model.backgroundData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill().overlay(Color.black.opacity(0.4)).clipped()
            } else { Color(model.palette.background) }
        }
        .foregroundColor(Color(model.palette.text))
        .tint(Color(model.palette.accent))
        .environment(\.colorScheme, ["gboard", "paper"].contains(model.preferences.theme) ? .light : .dark)
        .overlay(alignment: .top) {
            if let message = model.message {
                Text(message).font(.system(size: 11)).lineLimit(2)
                    .padding(8).background(Color(model.palette.special)).cornerRadius(8)
                    .padding(.horizontal, 12).offset(y: model.metrics.headerHeight + 8)
                    .allowsHitTesting(false)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            tool("square.grid.2x2", "Все инструменты", active: model.panel == "tools") { model.openTool("tools") }
            if model.panel == "keys" {
                predictionBar.frame(maxWidth: .infinity)
            } else {
                Button { model.searchTarget = nil; model.panel = "keys" } label: {
                    Image(systemName: "keyboard").frame(maxWidth: .infinity, minHeight: 30)
                }.buttonStyle(.plain).accessibilityLabel("К клавиатуре")
            }
            Button("Т9") { model.preferences.autocorrect.toggle(); model.savePreferences() }
                .font(.system(size: 12, weight: .semibold)).frame(width: 28, height: 34)
                .foregroundColor(Color(model.preferences.autocorrect ? model.palette.accent : model.palette.muted))
                .accessibilityLabel("Т9: автокоррекция")
                .accessibilityValue(model.preferences.autocorrect ? "Включена" : "Выключена")
                .buttonStyle(.plain)
            tool("doc.on.clipboard", "История: \(model.library.history.count) из 10", active: model.panel == "clips") { model.panel = "clips" }
            tool("gearshape", "Настройки", active: model.panel == "settings") { model.panel = "settings" }
        }
        .frame(height: model.metrics.headerHeight)
    }

    @ViewBuilder private var predictionBar: some View {
        if let target = model.searchTarget {
            HStack {
                Text("Поиск: " + (target == "emoji" ? model.emojiQuery : target == "clips" ? model.search : model.toolsQuery))
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                Button("Готово") { model.searchTarget = nil; model.panel = target }
            }.font(.system(size: 12)).frame(height: 30).padding(.horizontal, 6)
        } else if !model.glideOptions.isEmpty {
            HStack {
                ForEach(model.glideOptions, id: \.self) { word in
                    Button(word) { model.chooseSuggestion(word) }.frame(maxWidth: .infinity).accessibilityLabel("Подсказка: " + word)
                }
            }.font(.system(size: 14)).frame(height: 30).buttonStyle(.plain)
        } else if model.canUndo, let undo = model.undo {
            Button("↶ Вернуть «\(undo.original)»") { model.undoCorrection() }
                .font(.system(size: 12)).frame(maxWidth: .infinity).frame(height: 30)
                .buttonStyle(.plain).foregroundColor(Color(model.palette.accent))
        } else if model.preferences.predictions {
            HStack(spacing: 4) {
                if model.suggestions.isEmpty {
                    Text(model.activeWord ?? "")
                        .font(.system(size: 12)).foregroundColor(Color(model.palette.muted))
                        .lineLimit(1).frame(maxWidth: .infinity)
                } else {
                    ForEach(model.suggestions, id: \.self) { suggestion in
                        Button(suggestion) { model.chooseSuggestion(suggestion) }
                            .font(.system(size: 14)).lineLimit(1).minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity).frame(height: 30)
                            .buttonStyle(.plain).accessibilityLabel("Подсказка: " + suggestion)
                    }
                }
            }.frame(height: 30)
                .contextMenu { Button("Запомнить слово") { model.rememberWord() } }
        } else {
            Color.clear.frame(height: 30)
        }
    }

    private func tool(_ image: String, _ label: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: image).font(.system(size: 17)).frame(minWidth: 22, minHeight: 34) }
            .buttonStyle(.plain)
            .foregroundColor(Color(active ? model.palette.accent : model.palette.muted))
            .accessibilityLabel(label)
    }

    private func key(_ text: String, systemImage: String? = nil, label: String? = nil, width: CGFloat? = nil, special: Bool = false, accent: Bool = false, kazakh: Bool = false, hint: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let systemImage { Image(systemName: systemImage) }
                else { Text(text) }
            }
                .font(.system(size: systemImage != nil ? 18 : special ? 14 : 21, weight: .regular))
                .minimumScaleFactor(0.55).lineLimit(1)
                .frame(maxWidth: width == nil ? .infinity : nil)
                .frame(width: width, height: model.keyHeight)
                .contentShape(Rectangle())
                .overlay(alignment: .topTrailing) {
                    if let hint { Text(hint).font(.system(size: 8)).foregroundColor(Color(model.palette.muted)).padding(3) }
                }
        }
        .buttonStyle(KeyboardKeyStyle(background: Color(accent ? model.palette.accent : special || kazakh ? model.palette.special : model.palette.key)))
        .foregroundColor(Color(accent ? model.palette.onAccent : kazakh && model.preferences.theme != "gboard" ? model.palette.accent : model.palette.text))
        .accessibilityLabel(label ?? text)
    }

    private var keys: some View {
        GeometryReader { geometry in
            keyboardRows(width: geometry.size.width)
        }
        .frame(height: model.metrics.keysHeight)
    }

    private var mainLetterRow: String {
        ["kk", "fr", "es"].contains(model.language.id) ? model.language.rows[1] : model.language.rows[0]
    }

    private func keyboardRows(width: CGFloat) -> some View {
        VStack(spacing: model.metrics.rowSpacing) {
            ForEach(Array(model.rows.enumerated()), id: \.offset) { item in
                letterRow(item.element, last: item.offset == model.rows.count - 1, width: width)
            }
            if model.rows.count < model.metrics.letterRows { Spacer(minLength: 0) }
            bottomKeys
        }
        .frame(height: model.metrics.keysHeight)
        .coordinateSpace(name: "letters")
        .onPreferenceChange(LetterFramesKey.self) { letterFrames = $0 }
        .simultaneousGesture(glideGesture)
        .overlay { glideTrail }
    }

    private func letterRow(_ row: String, last: Bool, width: CGFloat) -> some View {
        let columns = model.symbolPage < 0 ? mainLetterRow.count : 10
        let standardWidth = max(10, (width - CGFloat(columns - 1) * 4) / CGFloat(columns))
        let sideWidth = max(28, min(44, standardWidth * 1.2))
        let availableWidth = width - (last ? sideWidth * 2 + 8 : 0)
        let letterWidth = min(standardWidth, (availableWidth - CGFloat(row.count - 1) * 4) / CGFloat(row.count))
        return HStack(spacing: 4) {
            if last { shiftKey(width: sideWidth) }
            ForEach(Array(row.enumerated()), id: \.offset) { item in
                characterKey(String(item.element), index: item.offset, row: row, width: letterWidth)
            }
            if last {
                RepeatDeleteKey(palette: model.palette) { model.delete() }
                    .frame(width: sideWidth, height: model.keyHeight)
            }
        }.frame(maxWidth: .infinity)
    }

    private func shiftKey(width: CGFloat) -> some View {
        let title = model.symbolPage == 0 ? "#+=" : "123"
        let icon = model.symbolPage < 0 ? (model.caps ? "capslock.fill" : model.upper ? "shift.fill" : "shift") : nil
        return key(title, systemImage: icon, label: "Shift", width: width, special: true, accent: model.symbolPage < 0 && model.upper) { model.shift() }
    }

    private func characterKey(_ text: String, index: Int, row: String, width: CGFloat) -> some View {
        let showHint = model.symbolPage < 0 && row == mainLetterRow && !model.preferences.numberRow && index < 10
        let hint = showHint ? String((index + 1) % 10) : nil
        let title = model.symbolPage < 0 && model.upper ? text.uppercased(with: Locale(identifier: model.language.locale)) : text
        let kazakh = model.symbolPage < 0 && model.language.id == "kk" && row == model.language.rows[0]
        return key(title, width: width, kazakh: kazakh, hint: hint) { model.typeCharacter(text) }
            .background(GeometryReader { geometry in
                Color.clear.preference(key: LetterFramesKey.self, value: text.first?.isLetter == true ? [text: geometry.frame(in: .named("letters"))] : [:])
            })
            .contextMenu {
                if let hint { Button(hint) { model.insert(hint) } }
            }
    }

    private var bottomKeys: some View {
        HStack(spacing: 4) {
            key(model.symbolPage < 0 ? "123" : "ABC", label: "Буквы и символы", width: 38, special: true) {
                model.symbolPage = model.symbolPage < 0 ? 0 : -1
                model.controller?.updateHeight()
            }
            key("", systemImage: "globe", label: "Сменить язык", width: 32, special: true) { model.nextLanguage() }
                .contextMenu {
                    ForEach(model.layouts.languages.filter { model.preferences.enabledLanguages.contains($0.id) }) { language in
                        Button(language.name ?? language.title) { model.selectLanguage(language.id) }
                    }
                    Button("Настроить языки") { model.panel = "settings" }
                    Button("Следующая системная клавиатура") { model.controller?.advanceToNextInputMode() }
                }
            key("", systemImage: "face.smiling", label: "Эмодзи", width: 32, special: true) { model.searchTarget = nil; model.panel = "emoji" }
            CursorSpaceKey(title: model.language.name ?? model.language.title, palette: model.palette,
                           insert: { model.insert(" ", space: true) }, move: { model.moveCursor($0) })
                .frame(maxWidth: .infinity).frame(height: model.keyHeight)
            key(".", width: 28, special: true) { model.insert(".") }
            key("", systemImage: "arrow.turn.down.left", label: "Ввод", width: 44, special: true, accent: true) { model.insert("\n") }
        }
    }

    private var glideGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .named("letters"))
            .onChanged { value in
                guard model.preferences.glide, model.symbolPage < 0, model.searchTarget == nil,
                      letterFrames.values.contains(where: { $0.contains(value.startLocation) }) else { return }
                if !model.gliding { model.beginGlide(at: value.startLocation) }
                if model.glidePoints.count < 256 { model.glidePoints.append(value.location) }
            }
            .onEnded { _ in
                if model.gliding { model.finishGlide(centers: letterFrames.mapValues { CGPoint(x: $0.midX, y: $0.midY) }) }
            }
    }

    private var glideTrail: some View {
        Path { path in
            if let first = model.glidePoints.first {
                path.move(to: first)
                for point in model.glidePoints.dropFirst() { path.addLine(to: point) }
            }
        }
        .stroke(Color(model.palette.accent).opacity(0.7), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        .allowsHitTesting(false)
    }

    private var clips: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("История · \(model.library.history.count)/10").font(.system(size: 13, weight: .semibold))
                Spacer()
                if model.clipboardNeedsRetry {
                    Button("Повторить доступ") { model.clipboardMonitor.retryAccess() }.font(.system(size: 11)).buttonStyle(.plain)
                }
            }
            Text(model.clipboardStatus).font(.system(size: 10)).foregroundColor(Color(model.palette.muted)).lineLimit(3)
            Picker("Раздел буфера", selection: $model.clipSection) {
                Text("Последние 10").tag("history")
                Text("Закреплённые").tag("favorites")
            }.pickerStyle(.segmented)
            Button(model.search.isEmpty ? "⌕ Найти фрагмент" : "⌕ " + model.search) { model.startSearch("clips") }
                .font(.system(size: 12)).buttonStyle(.plain)
                .contextMenu { Button("Сбросить поиск") { model.search = "" } }
            ScrollView {
                LazyVStack(spacing: 7) {
                    if model.library.filtered(model.search, favoritesOnly: model.clipSection == "favorites").isEmpty {
                        Text(model.clipSection == "favorites" ? "Здесь будут закреплённые фразы.\nОни хранятся отдельно от последних 10 копирований." : "Скопируй текст и открой CoolBoard.\nТекущий текст подхватится автоматически.\nНажми на запись, чтобы вставить её.")
                            .font(.system(size: 13)).multilineTextAlignment(.center)
                            .foregroundColor(Color(model.palette.muted)).frame(maxWidth: .infinity).padding(.top, 25)
                    }
                    ForEach(model.library.filtered(model.search, favoritesOnly: model.clipSection == "favorites")) { clip in
                        HStack(spacing: 5) {
                            Button { model.insert(clip.text); model.panel = "keys" } label: {
                                Text(clip.text).font(.system(size: 14)).lineLimit(4)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(9)
                            }.buttonStyle(.plain)
                            Button {
                                if !model.library.togglePin(clip.id) { model.notice("Можно закрепить до 100 фраз.") }
                                model.saveLibrary()
                            } label: {
                                Image(systemName: clip.pinned ? "star.fill" : "star").frame(width: 28, height: 40)
                            }.accessibilityLabel(clip.pinned ? "Открепить" : "Закрепить")
                                .foregroundColor(Color(model.palette.accent))
                            Button {
                                model.library.remove(clip.id); model.saveLibrary()
                            } label: {
                                Image(systemName: "xmark").frame(width: 26, height: 40)
                            }.accessibilityLabel("Удалить фрагмент")
                                .foregroundColor(Color(model.palette.muted))
                        }.buttonStyle(.plain).background(Color(model.palette.special)).cornerRadius(8)
                    }
                }
            }
            HStack {
                Button("⌨ К клавиатуре") { model.panel = "keys" }
                Spacer()
                if let controller = model.controller { SystemGlobeKey(controller: controller, palette: model.palette).frame(width: 34, height: 32) }
            }.font(.system(size: 12)).buttonStyle(.plain)
        }.padding(.horizontal, 5).frame(maxHeight: .infinity)
    }

    private var emojiPanel: some View {
        VStack(spacing: 8) {
            HStack {
                Button(model.emojiQuery.isEmpty ? "⌕ Найти эмодзи" : "⌕ " + model.emojiQuery) { model.startSearch("emoji") }
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                if !model.emojiQuery.isEmpty {
                    Button { model.emojiQuery = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel("Очистить поиск эмодзи")
                }
                Menu {
                    ForEach(["", "🏻", "🏼", "🏽", "🏾", "🏿"], id: \.self) { tone in
                        Button(tone.isEmpty ? "Стандартный" : "Оттенок " + tone) { model.preferences.emojiTone = tone; model.savePreferences() }
                    }
                } label: { Text(model.preferences.emojiTone.isEmpty ? "✋" : "✋" + model.preferences.emojiTone).font(.system(size: 23)) }
                    .accessibilityLabel("Оттенок кожи")
            }.font(.system(size: 12)).buttonStyle(.plain).padding(.horizontal, 5)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    emojiCategory("recent", icon: "🕘", label: "Недавние")
                    ForEach(model.emoji.categories) { category in
                        emojiCategory(category.id, icon: category.icon, label: category.title)
                    }
                }.padding(.horizontal, 5)
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 4) {
                    ForEach(model.visibleEmoji) { emoji in
                        Button { model.insertEmoji(emoji.displayed(tone: model.preferences.emojiTone)) } label: {
                            Text(emoji.displayed(tone: model.preferences.emojiTone))
                                .font(.system(size: 28)).frame(maxWidth: .infinity).frame(height: 39)
                        }.buttonStyle(.plain).accessibilityLabel(emoji.keywords.isEmpty ? emoji.name : emoji.keywords)
                            .contextMenu {
                                Button(emoji.text) { model.insertEmoji(emoji.text) }
                                ForEach(emoji.variants, id: \.self) { variant in
                                    Button(variant) { model.insertEmoji(variant) }
                                }
                            }
                    }
                }
                if model.visibleEmoji.isEmpty {
                    Text(model.emojiCategory == "recent" && model.emojiQuery.isEmpty ? "Здесь появятся недавно использованные эмодзи" : "Ничего не найдено")
                        .font(.system(size: 12)).foregroundColor(Color(model.palette.muted)).padding(20)
                }
            }.id(model.emojiCategory + model.emojiQuery)
            HStack {
                Button("АБВ") { model.panel = "keys" }
                if let controller = model.controller { SystemGlobeKey(controller: controller, palette: model.palette).frame(width: 32, height: 32) }
                Spacer()
                Text("Системные эмодзи iPhone").font(.system(size: 10)).foregroundColor(Color(model.palette.muted))
                Spacer()
                RepeatDeleteKey(palette: model.palette) { model.delete() }.frame(width: 37, height: 32)
            }.font(.system(size: 12)).buttonStyle(.plain).padding(.horizontal, 5)
        }.padding(.top, 3)
    }

    private func emojiCategory(_ id: String, icon: String, label: String) -> some View {
        Button { model.emojiCategory = id; model.emojiQuery = "" } label: {
            Text(icon).font(.system(size: 20)).frame(width: 31, height: 31)
                .background(Color(model.emojiCategory == id ? model.palette.special : model.palette.background)).cornerRadius(6)
        }.buttonStyle(.plain).accessibilityLabel(label)
    }

    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Сделай своей").font(.system(size: 15, weight: .semibold))
                HStack(spacing: 14) {
                    ForEach([("gboard", "Gboard · светлая"), ("graphite", "Графит"), ("paper", "Бумага"), ("ocean", "Океан"), ("rose", "Роза")], id: \.0) { theme, name in
                        Button {
                            model.preferences.theme = theme; model.savePreferences()
                        } label: {
                            Circle().fill(Color(KeyboardPalette.named(theme).key)).frame(width: 32, height: 32)
                                .overlay { Circle().stroke(Color(model.preferences.theme == theme ? model.palette.accent : model.palette.muted), lineWidth: model.preferences.theme == theme ? 3 : 1) }
                        }.buttonStyle(.plain).accessibilityLabel(name)
                    }
                }
                Picker("Размер", selection: $model.preferences.size) {
                    Text("Меньше").tag("compact")
                    Text("Обычный").tag("normal")
                    Text("Больше").tag("large")
                }.pickerStyle(.segmented)
                Toggle("Цифры отдельным рядом", isOn: $model.preferences.numberRow)
                Toggle("Заглавная в начале", isOn: $model.preferences.autoCap)
                Toggle("Двойной пробел → точка", isOn: $model.preferences.doubleSpace)
                Toggle("Т9: автокоррекция", isOn: $model.preferences.autocorrect)
                Toggle("Подсказки слов", isOn: $model.preferences.predictions)
                Toggle("Автосохранение последних 10 копирований", isOn: $model.preferences.autoClipboard)
                Toggle("Свайп-набор слов", isOn: $model.preferences.glide)
                Toggle("Подсказки следующего слова", isOn: $model.preferences.nextWord)
                Toggle("Смешанный ввод языков", isOn: $model.preferences.multilingual)
                Toggle("Виброотклик (нужен полный доступ)", isOn: $model.preferences.haptics)
                Toggle("Онлайн-перевод, поиск и GIF", isOn: $model.preferences.online)
                Picker("Одной рукой", selection: $model.preferences.oneHanded) {
                    Text("Выкл.").tag("off"); Text("Слева").tag("left"); Text("Справа").tag("right")
                }.pickerStyle(.segmented)
                Button("Фотофоновая тема из буфера") { model.setPhotoBackground() }
                Text("Языки").font(.system(size: 14, weight: .semibold)).padding(.top, 4)
                ForEach(model.layouts.languages) { language in
                    Toggle(language.name ?? language.title, isOn: Binding(
                        get: { model.preferences.enabledLanguages.contains(language.id) },
                        set: { model.setLanguageEnabled(language.id, enabled: $0) }
                    ))
                }
                Text("Оставь хотя бы один язык. Удерживай кнопку языка на клавиатуре для быстрого выбора.")
                    .font(.system(size: 10)).foregroundColor(Color(model.palette.muted))
                Button("Удалить незакреплённые фрагменты", role: .destructive) {
                    model.library.clearUnpinned(); model.saveLibrary()
                }.buttonStyle(.plain)
                Button("Очистить историю копирований", role: .destructive) { model.library.clearHistory(); model.saveLibrary() }.buttonStyle(.plain)
                HStack {
                    Button("⌨ К клавиатуре") { model.panel = "keys" }
                    Spacer()
                    if let controller = model.controller { SystemGlobeKey(controller: controller, palette: model.palette).frame(width: 34, height: 32) }
                }.buttonStyle(.plain)
            }.font(.system(size: 12)).padding(7)
        }
        .onChange(of: model.preferences.size) { _ in model.savePreferences() }
        .onChange(of: model.preferences.numberRow) { _ in model.savePreferences() }
        .onChange(of: model.preferences.autoCap) { _ in model.savePreferences() }
        .onChange(of: model.preferences.doubleSpace) { _ in model.savePreferences() }
        .onChange(of: model.preferences.autocorrect) { _ in model.savePreferences() }
        .onChange(of: model.preferences.predictions) { _ in model.savePreferences() }
        .onChange(of: model.preferences.autoClipboard) { _ in model.savePreferences() }
        .onChange(of: model.preferences.glide) { _ in model.savePreferences() }
        .onChange(of: model.preferences.nextWord) { _ in model.savePreferences() }
        .onChange(of: model.preferences.multilingual) { _ in model.savePreferences() }
        .onChange(of: model.preferences.haptics) { _ in model.savePreferences() }
        .onChange(of: model.preferences.online) { _ in model.savePreferences() }
        .onChange(of: model.preferences.oneHanded) { _ in model.savePreferences() }
    }
}

struct KeyboardKeyStyle: ButtonStyle {
    let background: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(background.opacity(configuration.isPressed ? 0.65 : 1))
            .cornerRadius(6).shadow(color: .black.opacity(0.15), radius: 0, y: 1)
            .offset(y: configuration.isPressed ? 1 : 0)
    }
}

struct SystemGlobeKey: UIViewRepresentable {
    let controller: UIInputViewController
    let palette: KeyboardPalette
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "globe"), for: .normal)
        button.accessibilityLabel = "Другая системная клавиатура"
        button.addTarget(controller, action: #selector(UIInputViewController.handleInputModeList(from:with:)), for: .allTouchEvents)
        return button
    }
    func updateUIView(_ uiView: UIButton, context: Context) {
        uiView.backgroundColor = palette.special; uiView.tintColor = palette.text; uiView.layer.cornerRadius = 6
    }
}

struct CursorSpaceKey: UIViewRepresentable {
    let title: String
    let palette: KeyboardPalette
    let insert: () -> Void
    let move: (Int) -> Void

    func makeUIView(context: Context) -> CursorSpaceButton { CursorSpaceButton(frame: .zero) }
    func updateUIView(_ button: CursorSpaceButton, context: Context) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(palette.text, for: .normal)
        button.backgroundColor = palette.key
        button.insert = insert; button.move = move
    }
}

final class CursorSpaceButton: UIButton {
    var insert: (() -> Void)?
    var move: ((Int) -> Void)?
    private var dragging = false
    private var consumed: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel?.font = .systemFont(ofSize: 14)
        layer.cornerRadius = 5
        accessibilityLabel = "Пробел"
        accessibilityHint = "Свайп влево или вправо перемещает курсор"
        addTarget(self, action: #selector(touchBegan), for: .touchDown)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(panned(_:))))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func touchBegan() { dragging = false; consumed = 0 }
    @objc private func tapped() { if !dragging { insert?() } }
    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began { dragging = true }
        guard gesture.state == .began || gesture.state == .changed else { return }
        let translation = gesture.translation(in: self).x
        let steps = Int((translation - consumed) / 12)
        if steps != 0 { consumed += CGFloat(steps) * 12; move?(steps) }
    }
    override func accessibilityActivate() -> Bool { insert?(); return true }
}

struct RepeatDeleteKey: UIViewRepresentable {
    let palette: KeyboardPalette
    let action: () -> Void
    func makeUIView(context: Context) -> RepeatingDeleteButton { RepeatingDeleteButton(frame: .zero) }
    func updateUIView(_ uiView: RepeatingDeleteButton, context: Context) {
        uiView.action = action; uiView.backgroundColor = palette.special; uiView.tintColor = palette.text
    }
    static func dismantleUIView(_ uiView: RepeatingDeleteButton, coordinator: ()) { uiView.stop() }
}

final class RepeatingDeleteButton: UIButton {
    var action: (() -> Void)?
    private var delay: Timer?
    private var repeating: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setImage(UIImage(systemName: "delete.left"), for: .normal)
        layer.cornerRadius = 6
        accessibilityLabel = "Удалить символ"
        addTarget(self, action: #selector(begin), for: .touchDown)
        addTarget(self, action: #selector(stop), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func begin() {
        stop(); action?()
        delay = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.repeating = Timer.scheduledTimer(withTimeInterval: 0.075, repeats: true) { [weak self] _ in self?.action?() }
        }
    }
    @objc func stop() { delay?.invalidate(); repeating?.invalidate(); delay = nil; repeating = nil }
    override func accessibilityActivate() -> Bool { action?(); return true }
    override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { stop() } }
    deinit { delay?.invalidate(); repeating?.invalidate() }
}
