/// 録音キーの扱い。段階4で設定画面から変えられるようにするまで、初期値で固定して使う(設計書「キーの設定は段階4で足す」)
public struct HotkeySettings: Sendable, Equatable, Codable {
    public enum Key: String, Sendable, Codable {
        case rightCommand
    }

    public enum Mode: String, Sendable, Codable {
        /// 短く押すと開始・停止、長く押すと押している間だけ録る
        case hybrid
        /// 押すたびに開始・停止を切り替える
        case toggle
        /// 押している間だけ録る
        case hold
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
