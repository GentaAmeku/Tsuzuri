import Testing
@testable import TsuzuriCore

@Suite("波形の音量")
struct AudioLevelTests {
    @Test("静かな部分(0.0008)は0、ふつうの声(0.01〜0.03)は棒の半分ほどまで伸びる")
    func speechIsVisible() {
        #expect(AudioLevel.meter(rms: 0.0008) == 0)
        #expect(AudioLevel.meter(rms: 0.01) > 0.4)
        #expect(AudioLevel.meter(rms: 0.03) > 0.7)
        #expect(AudioLevel.meter(rms: 0.5) == 1)
    }

    @Test("音の無い録音は0")
    func silence() {
        #expect(AudioLevel.meter(of: []) == 0)
        #expect(AudioLevel.meter(of: [0, 0, 0]) == 0)
    }
}
