export class ClipboardWatcher {
  constructor({ enabled, active, permission, readText, save, status, fingerprint, remember, lastFingerprint = null }) {
    Object.assign(this, { enabled, active, permission, readText, save, status, fingerprint, remember, lastFingerprint });
    this.busy = false; this.blocked = false; this.revision = 0; this.queue = Promise.resolve();
  }
  invalidate() { this.revision++; }
  resume() { this.blocked = false; }
  capture(text, { newCopy = false, revision = this.revision } = {}) {
    this.queue = this.queue.catch(() => {}).then(async () => {
      if (!this.enabled() || revision !== this.revision || typeof text !== 'string' || !text.trim()) return false;
      if (text.length > 10000) { this.status('Этот текст длиннее 10 000 символов и не сохранён.', false); return false; }
      const digest = await this.fingerprint(text);
      if (!this.enabled() || revision !== this.revision) return false;
      if (!newCopy && digest === this.lastFingerprint) return false;
      if (this.save(text) === false) return false;
      this.lastFingerprint = digest; this.remember(digest);
      return true;
    });
    return this.queue;
  }
  async scan({ requestAccess = false } = {}) {
    if (!this.enabled()) { this.status('Автосохранение выключено в настройках.', false); return false; }
    if (!this.active() || this.busy || (this.blocked && !requestAccess)) return false;
    this.busy = true; const revision = this.revision;
    try {
      const permission = await this.permission();
      if (permission !== 'granted' && !requestAccess) {
        this.status('Копирования в этой вкладке сохраняются автоматически. Для буфера других приложений разреши чтение браузеру.', true); return false;
      }
      if (!this.active() || !this.enabled() || revision !== this.revision) return false;
      const text = await this.readText();
      if (!this.active() || !this.enabled() || revision !== this.revision) return false;
      this.blocked = false;
      const captured = await this.capture(text, { revision });
      if (text.length <= 10000) this.status('Авто · последние 10 текстов · чтение буфера разрешено', false);
      return captured;
    } catch {
      this.blocked = true;
      this.status('Браузер не разрешил чтение. Копирования в этой вкладке продолжают сохраняться автоматически.', true);
      return false;
    } finally { this.busy = false; }
  }
}

export function installClipboardCapture({ enabled, save, status }) {
  let lastFingerprint = null;
  try { lastFingerprint = localStorage.getItem('coolboard.clipboardFingerprint.v1'); } catch { /* session-only storage */ }
  const watcher = new ClipboardWatcher({
    enabled, save, status, lastFingerprint,
    active: () => !document.hidden && document.hasFocus(),
    permission: async () => {
      if (!navigator.clipboard?.readText) return 'unavailable';
      try { return (await navigator.permissions.query({ name: 'clipboard-read' })).state; } catch { return 'prompt'; }
    },
    readText: () => navigator.clipboard.readText(),
    fingerprint: async text => [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text)))].map(byte => byte.toString(16).padStart(2, '0')).join(''),
    remember: digest => { try { localStorage.setItem('coolboard.clipboardFingerprint.v1', digest); } catch { /* session-only storage */ } }
  });
  for (const name of ['copy', 'cut']) document.addEventListener(name, event => {
    if (!enabled()) return;
    const target = event.target;
    let selected = window.getSelection()?.toString() || '';
    if ((target instanceof HTMLTextAreaElement || target instanceof HTMLInputElement) && target.type !== 'password' && target.selectionStart !== null) {
      selected = target.value.slice(target.selectionStart, target.selectionEnd);
    }
    const revision = watcher.revision;
    queueMicrotask(() => {
      const provided = event.clipboardData?.getData('text/plain') || '';
      if (event.defaultPrevented && !provided) return;
      void watcher.capture(provided || selected, { newCopy: true, revision });
    });
  });
  const wake = () => { watcher.resume(); void watcher.scan(); };
  window.addEventListener('focus', wake);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) wake(); });
  const timer = setInterval(() => { void watcher.scan(); }, 800);
  window.addEventListener('pagehide', () => clearInterval(timer), { once: true });
  return watcher;
}
