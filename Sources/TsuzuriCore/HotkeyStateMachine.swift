/// 録音キーの状態の移り変わり(設計書「右⌘の操作と状態」)。
/// キーの出来事を受け取り、アプリがすべきことと、そのキーを相手のアプリに届けないか(consume)を返す。
/// 時刻は秒で受け取る(単調に増えればよい)
public struct HotkeyStateMachine: Sendable {
    public enum State: Sendable, Equatable {
        case idle
        /// 押した直後。手元で録音を始めたが、まだ Soniox にはつながない
        case armed(pressedAt: Double)
        /// 録音中。`keyHeld` は最初の押下がまだ続いているか
        case recording(pressedAt: Double, keyHeld: Bool)
        /// 止めて、確定した文字を待っている
        case finishing
    }

    public enum Event: Sendable, Equatable {
        case keyDown(at: Double)
        case keyUp(at: Double)
        /// 録音キー以外のキー(修飾キーを含む)が押された
        case otherKeyDown(at: Double)
        /// 押してから同時押しの秒数がたった
        case chordWindowElapsed
        case escape
        /// Return が押された(段階4。録音中なら、貼り付けたあとに Return を送る)
        case returnKey(at: Double)
        /// 確定・貼り付けまで終わった(失敗を含む)
        case finished
    }

    public enum Action: Sendable, Equatable {
        /// 手元で録音を始める
        case startCapture
        /// Soniox につなぎ、ためた音声を送る
        case connect
        /// 同時押しとみなし、録音を捨てる
        case discard
        /// 止めて、確定を待って貼り付ける
        case stop
        /// 取り消す(何も貼り付けない)
        case cancel
        /// 貼り付けたあとに Return を送る(段階4)。1回の録音で1度だけ出す
        case submitAfterPaste
    }

    public struct Output: Sendable, Equatable {
        public var actions: [Action]
        /// そのキーを相手のアプリに届けないか
        public var consume: Bool

        public init(_ actions: [Action] = [], consume: Bool = false) {
            self.actions = actions
            self.consume = consume
        }
    }

    public var settings: HotkeySettings
    public private(set) var state: State = .idle
    /// いまの録音で、貼り付けたあとに Return を送るか
    public private(set) var submitRequested = false

    public init(settings: HotkeySettings = HotkeySettings()) {
        self.settings = settings
    }

    /// 録音を始められなかったとき(安全な入力・権限が無いなど)に待機へ戻す
    public mutating func reset() {
        state = .idle
        submitRequested = false
    }

    public mutating func handle(_ event: Event) -> Output {
        switch (state, event) {
        case let (.idle, .keyDown(at)):
            state = .armed(pressedAt: at)
            submitRequested = false
            return Output([.startCapture])

        case let (.armed(pressedAt), .keyUp):
            // 同時押しの秒数より前に離した。押している間だけ録る方式では短すぎるので捨て、ほかは押すたびの切り替えとして続ける
            if settings.mode == .hold {
                state = .idle
                return Output([.discard])
            }
            state = .recording(pressedAt: pressedAt, keyHeld: false)
            return Output([.connect])

        case let (.armed(pressedAt), .otherKeyDown(at)), let (.armed(pressedAt), .returnKey(at)):
            // 押してすぐの Return は、ほかのキーと同じく同時押し(⌘Return)とみなし、相手のアプリへ届ける
            guard at - pressedAt <= settings.chordWindowSeconds else { return Output() }
            state = .idle
            return Output([.discard])

        case (.recording, .returnKey):
            // 押した瞬間に止め、貼り付けたあとに送る。Return は貼り付けより先に届かないよう止める
            state = .finishing
            submitRequested = true
            return Output([.stop, .submitAfterPaste], consume: true)

        case (.finishing, .returnKey):
            guard !submitRequested else { return Output(consume: true) }
            submitRequested = true
            return Output([.submitAfterPaste], consume: true)

        case let (.armed(pressedAt), .chordWindowElapsed):
            state = .recording(pressedAt: pressedAt, keyHeld: true)
            return Output([.connect])

        case let (.recording(pressedAt, true), .keyUp(at)):
            let longPress = at - pressedAt >= settings.longPressSeconds
            switch settings.mode {
            case .hybrid where longPress, .hold:
                state = .finishing
                return Output([.stop])
            case .hybrid, .toggle:
                state = .recording(pressedAt: pressedAt, keyHeld: false)
                return Output()
            }

        case (.recording(_, false), .keyDown):
            // 短く押して始めた録音を、もう一度押した瞬間に止める
            state = .finishing
            return Output([.stop])

        case (.armed, .escape), (.recording, .escape), (.finishing, .escape):
            state = .idle
            submitRequested = false
            return Output([.cancel], consume: true)

        case (.finishing, .finished):
            state = .idle
            submitRequested = false
            return Output()

        default:
            return Output()
        }
    }
}
