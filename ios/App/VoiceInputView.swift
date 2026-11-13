import SwiftUI
import UIKit
import Speech
import AVFAudio
import UniformTypeIdentifiers

@MainActor
final class VoiceInputModel: ObservableObject {
    @Published var transcript = ""
    @Published var recording = false
    @Published var requesting = false
    @Published var status = "Распознавание выполняет Apple. При наличии локальной модели используется устройство; иначе может понадобиться интернет."
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var tapInstalled = false
    private var session = UUID()

    func start(locale: String) async {
        guard !recording, !requesting else { return }
        requesting = true
        let permissionToken = session
        defer { requesting = false }
        let speech: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard session == permissionToken else { return }
        guard speech == .authorized else { status = "Разреши распознавание речи для CoolBoard в настройках iPhone."; return }
        let microphone: Bool = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard session == permissionToken else { return }
        guard microphone else { status = "Разреши доступ CoolBoard к микрофону в настройках iPhone."; return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)), recognizer.isAvailable else { status = "Распознавание этого языка сейчас недоступно у Apple."; return }
        stop(cancel: true)
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .measurement)
            try audio.setActive(true, options: .notifyOthersOnDeactivation)
            let input = engine.inputNode, format = input.outputFormat(forBus: 0)
            guard format.channelCount > 0, format.sampleRate > 0 else { throw OnlineVoiceError.unavailable }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            self.request = request
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            tapInstalled = true
            let token = UUID(); session = token; transcript = ""; recording = true
            status = recognizer.supportsOnDeviceRecognition ? "Слушаю · распознавание на устройстве" : "Слушаю · распознавание Apple онлайн"
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let finished = result?.isFinal == true
                Task { @MainActor [weak self] in
                    guard let self, self.session == token else { return }
                    if let text { self.transcript = text }
                    if let error { self.status = error.localizedDescription; self.stop(cancel: true) }
                    else if finished { self.status = "Готово. Можно скопировать текст."; self.stop(cancel: false) }
                }
            }
            engine.prepare(); try engine.start()
        } catch { stop(cancel: true); status = error.localizedDescription }
    }
    func stop(cancel: Bool) {
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        request?.endAudio(); request = nil
        if cancel { session = UUID(); recognition?.cancel(); recognition = nil }
        recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    private enum OnlineVoiceError: LocalizedError {
        case unavailable
        var errorDescription: String? { "Микрофон недоступен." }
    }
}

struct VoiceInputView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = VoiceInputModel()
    @State private var language = "ru-RU"
    var body: some View {
        Form {
            Section("Язык записи") {
                Picker("Язык", selection: $language) {
                    ForEach([("kk-KZ", "Қазақша"), ("ru-RU", "Русский"), ("en-US", "English"), ("uk-UA", "Українська"), ("de-DE", "Deutsch"), ("tr-TR", "Türkçe"), ("fr-FR", "Français"), ("es-ES", "Español")], id: \.0) { id, title in Text(title).tag(id) }
                }.disabled(model.recording || model.requesting)
                Text("Доступность языков зависит от Speech Recognition Apple на этом устройстве.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button {
                    if model.recording { model.stop(cancel: false) }
                    else { Task { await model.start(locale: language) } }
                } label: { Label(model.recording ? "Остановить запись" : "Начать запись", systemImage: model.recording ? "stop.circle.fill" : "mic.circle.fill") }
                .disabled(model.requesting)
                Text(model.status).font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $model.transcript).frame(minHeight: 180)
                Button("Скопировать текст") { UIPasteboard.general.string = model.transcript }
                    .disabled(model.transcript.isEmpty)
            }
            Section {
                Text("Вернись в чат и вставь результат. Запись начинается только по нажатию и прекращается при выходе с этого экрана. Аудиофайлы CoolBoard не сохраняет.")
            }
        }.navigationTitle("Голос").onDisappear { model.stop(cancel: true) }
            .onChange(of: scenePhase) { phase in if phase == .background { model.stop(cancel: true) } }
    }
}

struct MediaImportView: View {
    @State private var importing = false
    @State private var message = "Выбери PNG, JPEG или GIF. Затем вернись в клавиатуру → Инструменты → Стикеры → Из буфера."
    var body: some View {
        Form {
            Section {
                Button("Выбрать картинку или GIF") { importing = true }
                Text(message)
            }
        }.navigationTitle("Свои картинки")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.png, .jpeg, .gif]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 3_000_000 else { message = "Выбери файл до 3 МБ."; return }
                let data = try Data(contentsOf: url)
                guard data.count <= 3_000_000, let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) else { message = "Нужна картинка до 3 МБ."; return }
                UIPasteboard.general.setData(data, forPasteboardType: type.identifier)
                message = "Скопировано. Вернись в клавиатуру → Инструменты → Стикеры → Из буфера. Для фотофона: ⚙ → Фотофоновая тема из буфера."
            } catch { message = error.localizedDescription }
        }
    }
}
