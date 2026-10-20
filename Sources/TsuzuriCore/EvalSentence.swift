/// 評価セット(`eval/sentences.json`)の形
public struct EvalSentenceSet: Codable, Sendable, Equatable {
    public let version: Int
    public let sentences: [EvalSentence]

    public init(version: Int, sentences: [EvalSentence]) {
        self.version = version
        self.sentences = sentences
    }
}

/// 読み上げる1文。`scene` は使う場面(ai・slack・doc)
public struct EvalSentence: Codable, Sendable, Hashable {
    public let id: String
    public let scene: String
    public let text: String

    public init(id: String, scene: String, text: String) {
        self.id = id
        self.scene = scene
        self.text = text
    }
}
