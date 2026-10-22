import AppKit
import Carbon
import Observation
import TsuzuriCore
import TsuzuriEngines

/// アプリ全体のまとめ役。キーの出来事を状態の移り変わりに通し、録音・認識・整える・貼り付け・履歴をつなぐ。
/// 認識は Soniox が主で、失敗したら手元の録音を Mac 内(WhisperKit)で認識し直し、その後5分は Mac 内を使う
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
    /// 辞書の候補(段階3)
    let candidates: CandidateStore
    let local = LocalRecognizer()
    let permissions = Permissions()
    /// Soniox が失敗したあと、この時刻までは Mac 内で認識する
    private(set) var fallbackUntil: Date?
    /// 失敗のあと Mac 内を使う時間(設計書の初期値)
    static let fallbackSeconds: TimeInterval = 5 * 60

    @ObservationIgnored private var machine = HotkeyStateMachine()
    @ObservationIgnored private var keyMonitor: KeyMonitor?
    @ObservationIgnored private var run: DictationRun?
    /// いまの録音を Mac 内で認識するか(録音を始めたときに決める)
    @ObservationIgnored private var runIsLocal = false
    /// 録音中に Return が押され、貼り付けたあとに Return を送るか(段階4)
    @ObservationIgnored private var submitAfterPaste = false
    /// いまの録音で Soniox に渡したヒントの字数(費用の表示に使う)
    @ObservationIgnored private var runHintCharacters = 0
    @ObservationIgnored private var chordTimer: Task<Void, Never>?
    @ObservationIgnored private var apiKey: String?
    @ObservationIgnored private lazy var settingsWindow = SettingsWindow(controller: self)
    @ObservationIgnored private lazy var dictionaryWindow = DictionaryWindow(store: dictionary)
    @ObservationIgnored private lazy var candidateWindow = CandidateWindow(store: candidates)

    init() {
        dictionary = DictionaryStore(directory: store.directory)
        candidates = CandidateStore(directory: store.directory, dictionary: dictionary)
        machine.settings = store.hotkeySettings
        // 録音中の表示の停止ボタンは、録音キーで止めたときと同じ流れに通す
        hud.onStop = { [weak self] in _ = self?.handle(.stopButton) }
    }

    /// 録音キーと操作の方式。設定の窓で変えると、次の押下から効く
    var hotkeySettings: HotkeySettings {
        get { store.hotkeySettings }
        set {
            store.hotkeySettings = newValue
            machine.settings = newValue
            keyMonitor?.key = newValue.key
        }
    }

    var keyLabel: String { store.hotkeySettings.key.label }

    var isReady: Bool { isListening && (store.localOnly || hasAPIKey == true) && permissions.microphone == .authorized }

    /// 次の録音を Mac 内で認識するか
    var usesLocal: Bool {
        store.localOnly || (fallbackUntil.map { $0 > Date() } ?? false)
    }

    /// メニューに出す、いまの認識
    var engineLine: String {
        if store.localOnly { return "認識: Mac 内(WhisperKit)" }
        if let until = fallbackUntil, until > Date() {
            return "認識: Mac 内(Soniox の失敗のあと、\(until.formatted(date: .omitted, time: .shortened)) まで)"
        }
        return "認識: Soniox"
    }

    var lastText: String? { DictationHistory.lastText(in: store.history) }

    var statusLine: String {
        switch phase {
        case .recording: return "録音中(\(keyLabel)で止める・Return で貼って送信・Esc で取り消す)"
        case .finishing: return "文字の確定を待っています"
        case .idle:
            if !isListening { return "アクセシビリティの権限が要ります" }
            if !store.localOnly, hasAPIKey == nil { return "キーチェーンの確認を待っています" }
            if !store.localOnly, hasAPIKey == false { return "Soniox の API キーが未登録です" }
            if permissions.microphone != .authorized { return "マイクの権限が要ります" }
            if dictionary.loadError != nil { return "辞書のファイルを読めません(設定を見てください)" }
            return "待機中(\(keyLabel)で録音)"
        }
    }

    func start() {
        store.purgeOldAudio()
        reloadAPIKey()
        // 失敗したときにすぐ使えるよう、Mac 内の認識を裏で読み込んでおく
        local.prewarm()
        startListening()
        if !permissions.allGranted {
            showSettings()
        }
    }

    // MARK: キーの検知

    /// アクセシビリティの権限が付くまで、1秒ごとにキーの検知を始め直す
    private func startListening() {
        let monitor = KeyMonitor(key: store.hotkeySettings.key) { [weak self] event in
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
        case .submitAfterPaste:
            submitAfterPaste = true
            hud.willSubmit = true
        }
    }

    // MARK: 1回の音声入力

    private func startCapture() {
        guard phase == .idle else {
            // 直前の録音を認識し直している間は、新しく録らない
            machine.reset()
            return
        }
        if IsSecureEventInputEnabled() {
            return abort("パスワードなどの安全な入力の間は録音しません")
        }
        guard permissions.microphone == .authorized else {
            showSettings()
            return abort("マイクの権限がありません。設定から許可してください")
        }
        let isLocal = usesLocal
        guard isLocal || apiKey != nil else {
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
        // 表示は押した瞬間に出し、同時押し(⌘C など)と分かったら消す(設計書「録音中の表示は段階4で直す」)
        self.run = run
        runIsLocal = isLocal
        submitAfterPaste = false
        runHintCharacters = 0
        phase = .recording
        hud.theme = store.hudTheme
        hud.showRecording(engine: isLocal ? "Mac 内" : "Soniox")
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
        guard let run else { return }
        // Mac 内で認識するときは、止めてから録音をまとめて渡す(話している途中の文字は出ない)
        guard !runIsLocal, let apiKey else { return }
        let hud = hud
        let terms = dictionary.hintTerms()
        runHintCharacters = terms.reduce(0) { $0 + $1.count }
        run.connect(
            apiKey: apiKey,
            terms: terms,
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
        submitAfterPaste = false
        phase = .idle
        hud.hide()
    }

    private func stop() {
        chordTimer?.cancel()
        guard let run else { return }
        phase = .finishing
        let isLocal = runIsLocal
        hud.showFinishing(isLocal ? "Mac 内で認識しています" : "確定を待っています")
        Task {
            if isLocal {
                await recognizeLocally(run.stopRecording(), run: run, sonioxFailure: nil)
            } else {
                await complete(run, await run.stop())
            }
            if self.run === run {
                self.run = nil
                phase = .idle
                _ = handle(.finished)
            }
        }
    }

    private func complete(_ run: DictationRun, _ outcome: DictationRun.Outcome) async {
        guard !run.isCancelled else { return }
        switch outcome {
        case let .failed(message, samples):
            fallbackUntil = Date().addingTimeInterval(Self.fallbackSeconds)
            await recognizeLocally(samples, run: run, sonioxFailure: message)
        case let .text(text, samples):
            store.recordSoniox(audioSeconds: Double(samples.count) / AudioFile.sampleRate, hintCharacters: runHintCharacters)
            let audio = store.saveAudio(samples, startedAt: run.startedAt)
            await deliver(text, engine: "soniox", audio: audio, startedAt: run.startedAt)
        }
    }

    /// 手元の録音を Mac 内で認識する。Soniox の失敗のあとなら、その理由も知らせる
    private func recognizeLocally(_ samples: [Float], run: DictationRun, sonioxFailure: String?) async {
        let audio = store.saveAudio(samples, startedAt: run.startedAt)
        // 無音に近い録音を渡すと、Whisper は文を作ってしまう
        guard SpeechPresence.hasSpeech(samples) else {
            hud.notice("聞き取れる言葉がありませんでした")
            return
        }
        hud.showFinishing("Mac 内で認識しています")
        do {
            let text = try await local.transcribe(samples, terms: dictionary.hintTerms())
            guard !run.isCancelled else { return }
            await deliver(text, engine: "whisperkit", audio: audio, startedAt: run.startedAt, notice: sonioxFailure.map { "\($0)。Mac 内で認識しました" })
        } catch {
            guard !run.isCancelled else { return }
            let message = [sonioxFailure, "\(error)"].compactMap { $0 }.joined(separator: "。")
            let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            store.record(HistoryEntry(date: run.startedAt, app: app, engine: "whisperkit", raw: "", text: "", audio: audio, error: message))
            hud.notice(audio == nil ? message : "\(message)。録音は履歴に残しました")
        }
    }

    /// 整えて貼り、履歴と使われた回数を残す。貼ったあとに裏で辞書の候補を洗い出す
    private func deliver(_ text: String, engine: String, audio: String?, startedAt: Date, notice: String? = nil) async {
        guard !text.isEmpty else {
            hud.notice("聞き取れる言葉がありませんでした")
            return
        }
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let shaped = dictionary.shaper(waObunSpacing: store.waObunSpacing).shape(text)
        store.record(HistoryEntry(date: startedAt, app: app, engine: engine, raw: text, text: shaped, audio: audio))
        dictionary.recordUsage(in: shaped)
        let submit = submitAfterPaste
        submitAfterPaste = false
        switch await Paster.paste(shaped) {
        case .pasted:
            // 録音中に Return が押されていたら、貼り終えてから送る
            if submit { Paster.sendReturn() }
            if let notice { hud.notice(notice) } else { hud.hide() }
        case .clipboardOnly:
            hud.notice(submit ? "入力欄が無いので、送らずにクリップボードに残しました" : "入力欄が無いので、クリップボードに残しました")
        }
        candidates.scan(shaped, app: app)
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

    /// 音声を残した最新の履歴(認識し直しの対象)
    var lastRecording: HistoryEntry? {
        store.history.last { $0.audio != nil }
    }

    /// 直前の録音を、Soniox か Mac 内でもう一度文字にして貼る。誤った文字を選んでから使うと、選んだ部分が置き換わる
    func reRecognizeLast(locally: Bool) {
        guard phase == .idle, let entry = lastRecording, let name = entry.audio else { return }
        phase = .finishing
        hud.showFinishing(locally ? "Mac 内で認識し直しています" : "Soniox で認識し直しています")
        Task {
            defer { phase = .idle }
            // メニューが閉じて元のアプリに戻るのを待つ
            try? await Task.sleep(for: .milliseconds(150))
            let samples: [Float]
            do {
                samples = try AudioFile.readSamples(from: store.audioURL(name))
            } catch {
                return hud.notice("録音を読めません(\(error))")
            }
            do {
                let text: String
                if locally {
                    text = try await local.transcribe(samples, terms: dictionary.hintTerms())
                } else {
                    guard let apiKey else { return hud.notice("Soniox の API キーが未登録です") }
                    let terms = dictionary.hintTerms()
                    let settings = SonioxSettings(terms: terms, clientReferenceID: "tsuzuri-app", paceInRealTime: false, timeoutSeconds: 15)
                    text = try await SonioxRealtime.transcribe(samples: samples, apiKey: apiKey, settings: settings).text
                    store.recordSoniox(audioSeconds: Double(samples.count) / AudioFile.sampleRate, hintCharacters: terms.reduce(0) { $0 + $1.count })
                }
                await deliver(text, engine: locally ? "whisperkit" : "soniox", audio: name, startedAt: Date())
            } catch {
                hud.notice("認識し直せませんでした(\(DictationRun.describe(error, connecting: false)))")
            }
        }
    }

    func copy(_ entry: HistoryEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
    }

    func showDictionary() {
        dictionaryWindow.show()
    }

    func showCandidates() {
        candidateWindow.show()
    }

    /// 動作の確かめ用。録音中の表示を見本の文字で出し、少したったら確定待ちに変えて消す
    func previewHUD(theme: HUDTheme) {
        hud.theme = theme
        hud.showRecording(engine: "Soniox")
        var assembler = TranscriptAssembler()
        assembler.apply([.init(text: "テストの件、午後に", isFinal: true), .init(text: "確認します", isFinal: false)])
        hud.update(assembler)
        hud.level = 0.6
        Task {
            try? await Task.sleep(for: .seconds(4))
            hud.willSubmit = true
            hud.showFinishing("確定を待っています")
            try? await Task.sleep(for: .seconds(4))
            hud.hide()
        }
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
