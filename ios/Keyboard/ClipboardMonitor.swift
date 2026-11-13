import UIKit
import CryptoKit

/// Observes only while this keyboard is on screen. iOS exposes the current item,
/// not a system-wide copy history or events from a suspended extension.
@MainActor
final class ClipboardMonitor {
    private weak var model: KeyboardModel?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var visible = false
    private var reading = false
    private var blocked = false
    private var lastChange: Int?
    private var hadFullAccess = false
    private var lastFingerprint = UserDefaults.standard.string(forKey: "clipboard.lastFingerprint.v1")

    init(model: KeyboardModel) { self.model = model }

    func start() {
        stop()
        visible = true
        for name in [UIPasteboard.changedNotification, UIPasteboard.removedNotification, UIApplication.didBecomeActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.scan() }
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scan() }
        }
        scan()
    }

    func stop() {
        visible = false
        timer?.invalidate(); timer = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
    }

    func preferenceChanged() { if visible { scan() } }
    func retryAccess() { blocked = false; lastChange = nil; if visible { scan(force: true) } }
    func historyDidChange() {
        if let model, model.preferences.autoClipboard, hadFullAccess, !blocked {
            status("Авто · последние \(model.library.history.count)/10 текстов")
        }
    }

    private func status(_ text: String, retry: Bool = false) {
        guard let model else { return }
        if model.clipboardStatus != text { model.clipboardStatus = text }
        if model.clipboardNeedsRetry != retry { model.clipboardNeedsRetry = retry }
    }

    func scan(force: Bool = false) {
        guard visible, !reading, let model else { return }
        guard model.preferences.autoClipboard else { status("Автосохранение выключено в настройках."); return }
        guard model.controller?.hasFullAccess == true else {
            hadFullAccess = false; blocked = false
            status("Для автосохранения включи «Полный доступ» для CoolBoard."); return
        }
        if !hadFullAccess { hadFullAccess = true; lastChange = nil; blocked = false }
        guard !blocked else { return }
        let pasteboard = UIPasteboard.general
        let count = pasteboard.changeCount
        guard force || lastChange != count else { return }
        let changedInThisSession = lastChange != nil && lastChange != count
        lastChange = count
        guard pasteboard.hasStrings else { status("Авто · последние \(model.library.history.count)/10 текстов"); return }
        reading = true
        defer { reading = false }
        guard let text = pasteboard.string else {
            blocked = true
            status("Не удалось прочитать буфер. Разреши вставку для CoolBoard в iOS и повтори доступ.", retry: true); return
        }
        guard visible, model.preferences.autoClipboard, model.controller?.hasFullAccess == true else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard text.utf16.count <= 10000 else { status("Этот текст длиннее 10 000 символов и не сохранён."); return }
        let fingerprint = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        // Reopening the keyboard must not resurrect an item the user deleted.
        // An actual new copy event may move identical text back to the top.
        guard changedInThisSession || fingerprint != lastFingerprint else {
            status("Авто · последние \(model.library.history.count)/10 текстов"); return
        }
        do {
            try model.library.add(text)
            model.saveLibrary()
            lastFingerprint = fingerprint
            UserDefaults.standard.set(fingerprint, forKey: "clipboard.lastFingerprint.v1")
            status("Авто · последние \(model.library.history.count)/10 текстов")
        } catch { status(error.localizedDescription) }
    }

    deinit {
        timer?.invalidate()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}
