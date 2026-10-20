/// 貼り付ける先に入力欄があるかの判断(設計書「貼り付けはクリップボードを借りて、すぐ戻す」)。
/// 入力欄が無いと分かったときだけ貼り付けず、判定できないアプリ(Electron 製・ターミナルなど)では貼り付ける
public enum PasteDecision: Sendable, Equatable {
    case paste
    /// 貼り付けず、文字をクリップボードに残して知らせる
    case clipboardOnly

    /// アクセシビリティ API で読めた、フォーカスのある要素
    public struct Focus: Sendable, Equatable {
        public var role: String
        /// 値を書き換えられるか、選択範囲を持つか(入力欄の印)
        public var acceptsText: Bool

        public init(role: String, acceptsText: Bool) {
            self.role = role
            self.acceptsText = acceptsText
        }
    }

    /// 入力欄ではないと言い切れる役割(Finder のファイルの一覧・ボタンなど)
    static let nonTextRoles: Set<String> = [
        "AXList", "AXOutline", "AXTable", "AXBrowser", "AXButton", "AXImage", "AXMenuItem", "AXCheckBox", "AXRadioButton"
    ]

    /// - Parameters:
    ///   - focus: フォーカスのある要素。読めなかったら nil
    ///   - appBundleID: いちばん前のアプリ
    public static func decide(focus: Focus?, appBundleID: String?) -> PasteDecision {
        guard let focus else {
            // Finder で何も選んでいないとき(デスクトップ)は入力欄が無い。ほかのアプリは判定できないので貼る
            return appBundleID == "com.apple.finder" ? .clipboardOnly : .paste
        }
        if focus.acceptsText { return .paste }
        return nonTextRoles.contains(focus.role) ? .clipboardOnly : .paste
    }
}
