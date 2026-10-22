/// 録音キーの扱い。段階4から設定の窓で変えられる(設計書「キーの設定は段階4で足す」)
public struct HotkeySettings: Sendable, Equatable, Codable {
    /// 録音キー。修飾キー単体だけを選べる(ほかのキーと重ならないため)
    public enum Key: String, Sendable, Codable, CaseIterable {
        case rightCommand
        case rightOption
        case fn

        /// 画面と案内に出す名前
        public var label: String {
            switch self {
            case .rightCommand: "右⌘"
            case .rightOption: "右⌥"
            case .fn: "fn"
            }
        }
    }

    public enum Mode: String, Sendable, Codable, CaseIterable {
        /// 短く押すと開始・停止、長く押すと押している間だけ録る
        case hybrid
        /// 押すたびに開始・停止を切り替える
        case toggle
        /// 押している間だけ録る
        case hold

        public var label: String {
            switch self {
            case .hybrid: "ハイブリッド(短く押すと切り替え、長く押すと押している間だけ)"
            case .toggle: "押すたびに開始・停止"
            case .hold: "押している間だけ"
            }
        }
    }

    public var key: Key
    public var mode: Mode
    /// これ以上押していたら長押しとみなす秒数
    public var longPressSeconds: Double
    /// 押してからこの秒数のうちにほかのキーが押されたら、同時押し(⌘C など)とみなす
    public var chordWindowSeconds: Double

    public init(key: Key = .rightCommand, mode: Mode = .hybrid, longPressSeconds: Double = 0.5, chordWindowSeconds: Double = 0.2) {
        self.key = key
        self.mode = mode
        self.longPressSeconds = longPressSeconds
        self.chordWindowSeconds = chordWindowSeconds
    }
}

/// 録音中の表示の色(段階4。設計書「録音中の表示は段階4で直す」)。並びと大きさはどちらも同じ
public enum HUDTheme: String, Sendable, Codable, CaseIterable {
    /// 白いカードを青い縁で囲む(既定)
    case blueWhite
    /// 黒い帯
    case dark

    public var label: String {
        switch self {
        case .blueWhite: "青と白"
        case .dark: "黒"
        }
    }
}
