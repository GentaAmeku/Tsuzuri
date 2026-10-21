import Foundation
import Testing
@testable import TsuzuriCore

@Suite("Soniox の費用(段階4)")
struct SonioxUsageTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    @Test("月ごとに回数・音声の秒数・ヒントの字数を足す。月の境目は日本の時刻で決める")
    func addsByMonth() {
        let file = SonioxUsageFile()
            .adding(audioSeconds: 12, hintCharacters: 600, at: date("2026-10-21T01:00:00Z"), calendar: calendar)
            .adding(audioSeconds: 8, hintCharacters: 500, at: date("2026-10-31T16:00:00Z"), calendar: calendar)
        #expect(file.months["2026-10"] == SonioxMonth(sessions: 1, audioSeconds: 12, hintCharacters: 600))
        #expect(file.months["2026-11"] == SonioxMonth(sessions: 1, audioSeconds: 8, hintCharacters: 500))
    }

    @Test("1回(15秒・ヒント600字)の代金は、設計書の目安と同じく音声0.0005ドルとヒント0.0007〜0.0019ドルの和")
    func estimatesOneSession() {
        let range = SonioxPricing().estimate(SonioxMonth(sessions: 1, audioSeconds: 15, hintCharacters: 600))
        #expect(abs(range.lowerBound - 0.00122) < 0.00001)
        #expect(abs(range.upperBound - 0.00242) < 0.00001)
    }

    @Test("1日100回を30日使うと、ヒントだけで月に約2〜6ドル")
    func estimatesMonth() {
        let range = SonioxPricing().estimate(SonioxMonth(sessions: 3000, audioSeconds: 0, hintCharacters: 3000 * 600))
        #expect(abs(range.lowerBound - 2.16) < 0.001)
        #expect(abs(range.upperBound - 5.76) < 0.001)
    }

    @Test("メニューの1行は、使用時間と推定の代金の幅を出す")
    func menuLine() {
        let line = SonioxPricing().menuLine(SonioxMonth(sessions: 400, audioSeconds: 4980, hintCharacters: 240_000))
        #expect(line == "今月の Soniox: 1時間23分・推定 0.45〜0.93ドル")
        #expect(SonioxPricing().menuLine(SonioxMonth()) == "今月の Soniox: 0分・推定 0.00〜0.00ドル")
    }
}
