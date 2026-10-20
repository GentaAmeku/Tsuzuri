import Testing
@testable import TsuzuriCore

@Suite("用語正答率")
struct TermAccuracyTests {
    @Test("カタカナで出た製品名は取りこぼしとして数える")
    func katakanaIsMiss() {
        let count = TermAccuracy.measure(
            reference: "Claude Code で直してください。",
            hypothesis: "クロードコードで直してください。",
            terms: ["Claude Code"]
        )
        #expect(count == TermCount(hits: 0, total: 1, missed: ["Claude Code"]))
    }

    @Test("空白の有無は問わない")
    func ignoresSpaces() {
        let count = TermAccuracy.measure(
            reference: "Google ドキュメントを更新した",
            hypothesis: "Googleドキュメントを更新した",
            terms: ["Google ドキュメント"]
        )
        #expect(count.hits == 1)
    }

    @Test("大文字小文字の違いは取りこぼしとして数える")
    func caseSensitive() {
        let count = TermAccuracy.measure(
            reference: "GitHub Actions の CI",
            hypothesis: "Github Actions の CI",
            terms: ["GitHub Actions", "CI"]
        )
        #expect(count == TermCount(hits: 1, total: 2, missed: ["GitHub Actions"]))
    }

    @Test("全角の英字はそろえてから比べる")
    func normalizesWidth() {
        let count = TermAccuracy.measure(reference: "CI が落ちた", hypothesis: "ＣＩが落ちた", terms: ["CI"])
        #expect(count.hits == 1)
    }

    @Test("長い語を先に当て、中に含まれる短い語は数えない")
    func longestMatchFirst() {
        let occurrences = TermAccuracy.occurrences(
            of: ["Claude", "Claude Code"],
            in: "Claude Code と Gemini と Claude の両方"
        )
        #expect(occurrences == ["Claude Code": 1, "Claude": 1])
    }

    @Test("対象の語が無い文は、率を1とする")
    func noTerms() {
        let count = TermAccuracy.measure(reference: "おはようございます", hypothesis: "おはようございます", terms: ["PR"])
        #expect(count == TermCount(hits: 0, total: 0, missed: []))
        #expect(count.rate == 1)
    }
}
