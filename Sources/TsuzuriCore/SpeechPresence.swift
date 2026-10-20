/// 録音に話し声がありそうかを、音量だけで見る。無音に近い録音を Mac 内の認識へ渡すと、
/// 「ご視聴ありがとうございました」のような文を作ってしまうため(設計書「段階0の結果」)
public enum SpeechPresence {
    public static let sampleRate = 16_000.0
    /// 30ms ずつ音量を見る
    static let frameSamples = 480
    /// 声とみなす音量(二乗平均の平方根。約 -46dBFS)。本人の MacBook の録音で、静かな部分は 0.0008 以下、
    /// 40文のどれも2秒以上がこれを超えた(2026-10-21)
    static let threshold: Float = 0.005
    /// 声とみなす長さの合計(秒)
    static let minimumVoicedSeconds = 0.3

    public static func hasSpeech(_ samples: [Float]) -> Bool {
        var voiced = 0
        var start = 0
        while start < samples.count {
            let frame = samples[start..<min(start + frameSamples, samples.count)]
            let rms = (frame.reduce(0) { $0 + $1 * $1 } / Float(frame.count)).squareRoot()
            if rms >= threshold { voiced += frame.count }
            start += frameSamples
        }
        return Double(voiced) / sampleRate >= minimumVoicedSeconds
    }
}
