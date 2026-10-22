import Foundation

/// 録音中の表示の波形に使う音量(0〜1)。二乗平均の平方根をそのまま使うと、内蔵マイクのふつうの声(0.01〜0.03)では
/// 棒がほとんど伸びないので、耳の感じ方に近いデシベルの目盛りで決める
public enum AudioLevel {
    /// これ以下は無音(0)。本人の録音の静かな部分は 0.0008(約 -62dB)以下
    public static let floorDecibels: Float = -55
    /// これ以上は最大(1)。近くで大きめに話したとき
    public static let ceilingDecibels: Float = -20

    public static func meter(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        return min(1, max(0, (decibels - floorDecibels) / (ceilingDecibels - floorDecibels)))
    }

    public static func meter(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        return meter(rms: (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot())
    }
}
