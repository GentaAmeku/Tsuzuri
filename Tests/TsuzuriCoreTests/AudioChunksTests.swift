import Testing
@testable import TsuzuriCore

@Suite("長い録音の区切り方")
struct AudioChunksTests {
    let rate = 16_000.0

    /// 声の大きさの音が続く録音。silences の秒の範囲だけ無音にする
    func recording(seconds: Double, silences: [ClosedRange<Double>] = []) -> [Float] {
        (0..<Int(seconds * rate)).map { index in
            let time = Double(index) / rate
            return silences.contains { $0.contains(time) } ? 0 : 0.1
        }
    }

    func samples(_ seconds: Double) -> Int {
        Int(seconds * rate)
    }

    @Test("15秒以下の録音は区切らない")
    func shortRecording() {
        #expect(AudioChunks.ranges(in: recording(seconds: 15), sampleRate: rate) == [0..<samples(15)])
        #expect(AudioChunks.ranges(in: recording(seconds: 4), sampleRate: rate) == [0..<samples(4)])
        #expect(AudioChunks.ranges(in: [], sampleRate: rate) == [0..<0])
    }

    @Test("15秒を超えたら、15秒の手前3秒のうち最も静かな所で区切る")
    func cutsAtSilence() {
        let ranges = AudioChunks.ranges(in: recording(seconds: 20, silences: [13.4...13.6]), sampleRate: rate)
        #expect(ranges.count == 2)
        #expect((samples(13.4)...samples(13.6)).contains(ranges[0].upperBound))
        #expect(ranges[1] == ranges[0].upperBound..<samples(20))
    }

    @Test("3秒より前の無音では区切らない")
    func ignoresEarlySilence() {
        let ranges = AudioChunks.ranges(in: recording(seconds: 20, silences: [9.5...10.5]), sampleRate: rate)
        #expect(ranges[0].upperBound >= samples(12))
    }

    @Test("どこも同じ大きさなら、15秒の3秒手前で区切る")
    func cutsWithoutSilence() {
        let ranges = AudioChunks.ranges(in: recording(seconds: 20), sampleRate: rate)
        #expect(ranges.count == 2)
        #expect(ranges[0] == 0..<samples(12.05))
    }

    @Test("区切りはどれも15秒以下で、つなぐと録音の全体になる")
    func coversWholeRecording() {
        let audio = recording(seconds: 50, silences: [13.0...13.2, 26.5...26.7, 41.0...41.1])
        let ranges = AudioChunks.ranges(in: audio, sampleRate: rate)
        #expect(ranges.count == 4)
        #expect(ranges.allSatisfy { $0.count <= samples(15) })
        #expect(ranges.first?.lowerBound == 0)
        #expect(ranges.last?.upperBound == audio.count)
        #expect(zip(ranges, ranges.dropFirst()).allSatisfy { $0.upperBound == $1.lowerBound })
    }
}
