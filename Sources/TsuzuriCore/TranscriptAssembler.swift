/// 認識の途中の結果を、もう変わらない「確定した文字」と、まだ変わりうる文字に分けて組み立てる。
/// Soniox は確定したトークンを一度だけ返し、変わりうるトークンは応答ごとに今の候補を返し直す
public struct TranscriptAssembler: Sendable, Equatable {
    public struct Token: Sendable, Equatable {
        public let text: String
        public let isFinal: Bool

        public init(text: String, isFinal: Bool) {
            self.text = text
            self.isFinal = isFinal
        }
    }

    /// 終わりや確定の合図として返る印。文字には含めない
    static let markers: Set<String> = ["<end>", "<fin>"]

    public private(set) var finalText = ""
    public private(set) var tentativeText = ""

    public init() {}

    public var text: String { finalText + tentativeText }

    public mutating func apply(_ tokens: [Token]) {
        let words = tokens.filter { !Self.markers.contains($0.text) }
        finalText += words.filter(\.isFinal).map(\.text).joined()
        tentativeText = words.filter { !$0.isFinal }.map(\.text).joined()
    }
}
