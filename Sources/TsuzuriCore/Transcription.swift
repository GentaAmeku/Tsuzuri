/// 認識の結果。`latencySeconds` は、音声を渡し終えてから文字が確定するまでの秒数
public struct Transcription: Sendable, Equatable {
    public let text: String
    public let latencySeconds: Double

    public init(text: String, latencySeconds: Double) {
        self.text = text
        self.latencySeconds = latencySeconds
    }
}

public extension Duration {
    /// 秒の小数にする
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
