import Foundation

/// 評価の1回分(1つの認識 × ヒントの有無 × マイク)。`eval/results/` に JSON で残す
public struct EvalRun: Codable, Sendable, Equatable {
    public let engine: String
    public let model: String?
    public let hints: HintMode
    public let mic: String
    public let createdAt: Date
    public let items: [EvalItem]

    public init(engine: String, model: String?, hints: HintMode, mic: String, createdAt: Date, items: [EvalItem]) {
        self.engine = engine
        self.model = model
        self.hints = hints
        self.mic = mic
        self.createdAt = createdAt
        self.items = items
    }
}

/// 語のヒントを渡したか
public enum HintMode: String, Codable, Sendable, CaseIterable {
    case on
    case off
    /// 語のヒントを受け付けない認識
    case none
}

/// 1文の結果。失敗した文は `hypothesis` が無く、`error` に理由が入る
public struct EvalItem: Codable, Sendable, Equatable {
    public let id: String
    public let hypothesis: String?
    public let audioSeconds: Double
    public let latencySeconds: Double?
    public let error: String?

    public init(id: String, hypothesis: String?, audioSeconds: Double, latencySeconds: Double?, error: String?) {
        self.id = id
        self.hypothesis = hypothesis
        self.audioSeconds = audioSeconds
        self.latencySeconds = latencySeconds
        self.error = error
    }
}
