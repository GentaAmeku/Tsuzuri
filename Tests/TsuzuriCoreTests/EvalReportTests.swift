import Foundation
import Testing
@testable import TsuzuriCore

@Suite("評価の集計")
struct EvalReportTests {
    let sentences = [
        EvalSentence(id: "ai-01", scene: "ai", text: "Claude Code で直して"),
        EvalSentence(id: "sl-01", scene: "slack", text: "静的解析を見る")
    ]

    func run(_ items: [EvalItem]) -> EvalRun {
        EvalRun(engine: "soniox", model: "stt-rt-v5", hints: .on, mic: "macbook", createdAt: Date(timeIntervalSince1970: 0), items: items)
    }

    @Test("中央値は、数が偶数なら真ん中の2つの平均")
    func median() {
        #expect(EvalReport.median([]) == nil)
        #expect(EvalReport.median([3, 1, 2]) == 2)
        #expect(EvalReport.median([4, 1, 3, 2]) == 2.5)
    }

    @Test("文字誤り率は文ごとの数を足してから率にする")
    func summarizesErrors() {
        let summary = EvalReport.summarize(
            run([
                EvalItem(id: "ai-01", hypothesis: "Claude Code で直して", audioSeconds: 4, latencySeconds: 0.4, error: nil),
                EvalItem(id: "sl-01", hypothesis: "性的解析を見る", audioSeconds: 12, latencySeconds: 0.8, error: nil)
            ]),
            sentences: sentences,
            terms: ["Claude Code", "静的"]
        )
        #expect(summary.errors == ErrorCount(edits: 1, length: 21))
        #expect(summary.terms == TermCount(hits: 1, total: 2, missed: ["静的"]))
        #expect(abs((summary.medianLatency ?? 0) - 0.6) < 1e-9)
        #expect(summary.medianLatencyLong == 0.8)
        #expect(summary.count == 2)
        #expect(summary.failures == 0)
    }

    @Test("失敗した文は、正解の文字数をすべて誤りとして数える")
    func countsFailures() {
        let summary = EvalReport.summarize(
            run([EvalItem(id: "sl-01", hypothesis: nil, audioSeconds: 3, latencySeconds: nil, error: "timeout")]),
            sentences: sentences,
            terms: []
        )
        #expect(summary.errors == ErrorCount(edits: 7, length: 7))
        #expect(summary.failures == 1)
        #expect(summary.medianLatency == nil)
    }

    @Test("誤りのある文だけを、取りこぼした語と一緒に挙げる")
    func listsMistakes() {
        let mistakes = EvalReport.mistakes(
            run([
                EvalItem(id: "ai-01", hypothesis: "Claude Code で直して", audioSeconds: 4, latencySeconds: 0.4, error: nil),
                EvalItem(id: "sl-01", hypothesis: "性的解析を見る", audioSeconds: 5, latencySeconds: 0.5, error: nil)
            ]),
            sentences: sentences,
            terms: ["静的"]
        )
        #expect(mistakes.map(\.id) == ["sl-01"])
        #expect(mistakes.first?.missedTerms == ["静的"])
    }

    @Test("表は認識・ヒント・マイクごとに1行")
    func rendersMarkdown() {
        let summary = EvalReport.summarize(
            run([EvalItem(id: "ai-01", hypothesis: "Claude Code で直して", audioSeconds: 4, latencySeconds: 0.42, error: nil)]),
            sentences: sentences,
            terms: ["Claude Code"]
        )
        let table = EvalReport.markdown([summary])
        #expect(table.contains("| soniox(stt-rt-v5) | あり | macbook | 0.0% | 100.0% | 0.42秒 | — | 1 | 0 |"))
    }
}
