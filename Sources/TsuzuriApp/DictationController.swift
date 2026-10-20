import AppKit
import Carbon
import Observation
import TsuzuriCore
import TsuzuriEngines

/// アプリ全体のまとめ役。キーの出来事を状態の移り変わりに通し、録音・Soniox・貼り付け・履歴をつなぐ
@Observable
final class DictationController {
    enum Phase {
        case idle
        case recording
        case finishing
    }

    private(set) var phase: Phase = .idle
    /// キーの検知が動いているか(アクセシビリティの権限が要る)
    private(set) var isListening = false
    /// キーチェーンを読み終えるまでは nil(確認の画面で待つことがある)
    private(set) var hasAPIKey: Bool?
    let hud = RecordingHUD()
    let store = AppStore()
    let dictionary: DictionaryStore
    let permissions = Permissions()

    @ObservationIgnored private var machine = HotkeyStateMachine()
    @ObservationIgnored private var keyMonitor: KeyMonitor?
    @ObservationIgnored private var run: DictationRun?
    @ObservationIgnored private var chordTimer: Task<Void, Never>?
    @ObservationIgnored private var apiKey: String?
    @ObservationIgnored private lazy var settingsWindow = SettingsWindow(controller: self)

    init() {
        dictionary = DictionaryStore(directory: store.directory)
    }

    var isReady: Bool { isListening && hasAPIKey == true && permissions.microphone == .authorized }

    var lastText: String? { DictationHistory.lastText(in: store.history) }

    var statusLine: String {
        switch phase {
        case .recording: return "録音中(右⌘で止める・Esc で取り消す)"
        case .finishing: return "文字の確定を待っています"
        case .idle:
            if !isListening { return "アクセシビリティの権限が要ります" }
            if hasAPIKey == nil { return "キーチェーンの確認を待っています" }
            if hasAPIKey == false { return "Soniox の API キーが未登録です" }
            if permissions.microphone != .authorized { return "マイクの権限が要ります" }
            if dictionary.loadError != nil { return "辞書のファイルを読めません(設定を見てください)" }
            return "待機中(右⌘で録音)"
        }
    }

    func start() {
        store.purgeOldAudio()
        reloadAPIKey()
        startListening()
        if !permissions.allGranted {
            showSettings()
        }
    }

    // MARK: キーの検知

    /// アクセシビリティの権限が付くまで、1秒ごとにキーの検知を始め直す
    private func startListening() {
        let monitor = KeyMonitor { [weak self] event in
            self?.handle(event) ?? false
        }
        if monitor.start() {
            keyMonitor = monitor
            isListening = true
            return
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.permissions.refresh()
            self?.startListening()
        }
    }

    /// キーの出来事を処理する。戻り値は、そのキーを相手のアプリに届けないか
    func handle(_ event: HotkeyStateMachine.Event) -> Bool {
        let output = machine.handle(event)
        for action in output.actions {
            perform(action)
        }
        return output.consume
    }

    private func perform(_ action: HotkeyStateMachine.Action) {
        switch action {
        case .startCapture: startCapture()
        case .connect: connect()
        case .discard, .cancel: cancel()
        case .stop: stop()
        }
    }

    // MARK: 1回の音声入力

    private func startCapture() {
        if IsSecureEventInputEnabled() {
            return abort("パスワードなどの安全な入力の間は録音しません")
        }
        guard permissions.microphone == .authorized else {
            showSettings()
            return abort("マイクの権限がありません。設定から許可してください")
        }
        guard apiKey != nil else {
            showSettings()
            return abort(hasAPIKey == nil
                ? "キーチェーンの確認を待っています。確認の画面で「許可」を押してください"
                : "Soniox の API キーが未登録です。設定で登録してください")
        }
        dictionary.reloadIfChanged()
        let run = DictationRun(hud: hud)
        do {
            try run.startCapture()
        } catch {
            return abort("録音を始められません(\(error))")
        }
        // 表示は、同時押しでないと分かってつなぐときに出す(⌘C のたびにちらつかせない)
        self.run = run
        let window = machine.settings.chordWindowSeconds
        chordTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(window))
            guard !Task.isCancelled else { return }
            _ = self?.handle(.chordWindowElapsed)
        }
    }

    private func abort(_ message: String) {
        machine.reset()
        phase = .idle
        hud.notice(message)
    }

    private func connect() {
        guard let run, let apiKey else { return }
        phase = .recording
        hud.showRecording()
        let hud = hud
        run.connect(
            apiKey: apiKey,
            terms: dictionary.hintTerms(),
            onUpdate: { assembler in
                Task { @MainActor in hud.update(assembler) }
            },
            onFailure: { message in
                hud.warning = message
            }
        )
    }

    private func cancel() {
        chordTimer?.cancel()
        run?.cancel()
        run = nil
        phase = .idle
        hud.hide()
    }

    private func stop() {
        chordTimer?.cancel()
        guard let run else { return }
        phase = .finishing
        hud.showFinishing()
        Task {
            let outcome = await run.stop()
            await complete(run, outcome)
            if self.run === run {
                self.run = nil
                phase = .idle
                _ = handle(.finished)
            }
        }
    }

    private func complete(_ run: DictationRun, _ outcome: DictationRun.Outcome) async {
        guard !run.isCancelled else { return }
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        switch outcome {
        case let .failed(message, samples):
            let audio = store.saveAudio(samples, startedAt: run.startedAt)
            store.record(HistoryEntry(date: run.startedAt, app: app, engine: "soniox", raw: "", text: "", audio: audio, error: message))
            hud.notice(audio == nil ? message : "\(message)。録音は履歴に残しました")
        case let .text(text, samples):
            let audio = store.saveAudio(samples, startedAt: run.startedAt)
            guard !text.isEmpty else {
                hud.notice("聞き取れる言葉がありませんでした")
                return
            }
            let shaped = dictionary.shaper(waObunSpacing: store.waObunSpacing).shape(text)
            store.record(HistoryEntry(date: run.startedAt, app: app, engine: "soniox", raw: text, text: shaped, audio: audio))
            dictionary.recordUsage(in: shaped)
            switch await Paster.paste(shaped) {
            case .pasted: hud.hide()
            case .clipboardOnly: hud.notice("入力欄が無いので、クリップボードに残しました")
            }
        }
    }

    // MARK: メニューと設定

    /// ⌃⌥⌘V とメニューから。直前の文字をもう一度貼る
    func pasteLast() {
        guard phase == .idle, let text = lastText else { return }
        Task {
            // メニューから選んだときは、メニューが閉じて元のアプリに戻るのを待つ
            try? await Task.sleep(for: .milliseconds(150))
            if await Paster.paste(text) == .clipboardOnly {
                hud.notice("入力欄が無いので、クリップボードに残しました")
            }
        }
    }

    func copy(_ entry: HistoryEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
    }

    func showSettings() {
        permissions.refresh()
        settingsWindow.show()
    }

    /// キーチェーンの読み出しは確認の画面で待つことがあるので、キーの検知を止めないよう別の糸で読む
    func reloadAPIKey() {
        Task {
            let key = await Task.detached { try? SonioxKeychain.load() }.value
            apiKey = key
            hasAPIKey = key != nil
        }
    }

    func saveAPIKey(_ key: String) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        try await Task.detached { try SonioxKeychain.save(trimmed) }.value
        apiKey = trimmed
        hasAPIKey = true
    }
}
