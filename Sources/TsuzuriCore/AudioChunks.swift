/// Mac 内の認識(WhisperKit)に渡す前に、長い録音を区切る(設計書「Mac 内の長い録音は、15秒以下に区切って認識する」)。
/// WhisperKit は1つの窓で書き出せる量に上限があり、30秒の切れ目の前後でも語が落ちるため。
/// 15秒を超えたら、15秒の手前3秒のうち最も静かな0.1秒の真ん中で区切り、残りも同じように区切る
public enum AudioChunks {
    public static let maxSeconds = 15.0
    /// 区切る所を探す、区切りの終わりの手前の秒数
    static let searchSeconds = 3.0
    /// 静かさを比べる長さ(秒)。この半分ずつずらして比べる
    static let frameSeconds = 0.1

    /// 区切りの範囲。どれも maxSeconds 以下で、つなぐと録音の全体になる。音の大きさは二乗の和で比べる
    public static func ranges(in samples: [Float], sampleRate: Double) -> [Range<Int>] {
        let maxLength = Int(maxSeconds * sampleRate)
        let searchLength = Int(searchSeconds * sampleRate)
        let frame = Int(frameSeconds * sampleRate)
        var result: [Range<Int>] = []
        var start = 0
        while samples.count - start > maxLength {
            let end = start + maxLength
            // どこも同じ大きさなら、探す範囲の頭で区切る
            var cut = end - searchLength + frame / 2
            var quietest = Float.infinity
            var position = end - searchLength
            while position + frame <= end {
                let energy = samples[position..<position + frame].reduce(0) { $0 + $1 * $1 }
                if energy < quietest {
                    quietest = energy
                    cut = position + frame / 2
                }
                position += frame / 2
            }
            result.append(start..<cut)
            start = cut
        }
        result.append(start..<samples.count)
        return result
    }
}
