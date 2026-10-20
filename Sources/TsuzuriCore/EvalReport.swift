import Foundation

/// 評価の1回分をまとめた数字
public struct EvalSummary: Sendable, Equatable {
    public let engine: String
    public let model: String?
    public let hints: HintMode
    public let mic: String
    public let errors: ErrorCount
    public let terms: TermCount
    public let medianLatency: Double?
    public let medianLatencyLong: Double?
    public let count: Int
    public let failures: Int
}

/// 正解と違った1文。段階3の「正解付きの直し」の材料にもなる
public struct EvalMistake: Sendable, Equatable {
    public let id: String
    public let reference: String
    public let hypothesis: String
    public let errors: ErrorCount
    public let missedTerms: [String]
}

/// 評価の結果を、文字誤り率・用語正答率・待ち時間の表にする
public enum EvalReport {
    /// 「長い文」とみなす音声の秒数。待ち時間の目安はこの長さ以上の文で見る
    public static let longClipSeconds = 10.0

    public static func summarize(_ run: EvalRun, sentences: [EvalSentence], terms: [String]) -> EvalSummary {
        let scored = scoredItems(run, sentences: sentences)
        return EvalSummary(
            engine: run.engine,
            model: run.model,
            hints: run.hints,
            mic: run.mic,
            errors: scored
                .map { CharacterErrorRate.measure(reference: $0.reference, hypothesis: $0.item.hypothesis ?? "") }
                .reduce(.zero, +),
            terms: scored
                .map { TermAccuracy.measure(reference: $0.reference, hypothesis: $0.item.hypothesis ?? "", terms: terms) }
                .reduce(.zero, +),
            medianLatency: median(scored.compactMap(\.item.latencySeconds)),
            medianLatencyLong: median(
                scored.filter { $0.item.audioSeconds >= longClipSeconds }.compactMap(\.item.latencySeconds)
            ),
            count: scored.count,
            failures: scored.filter { $0.item.error != nil }.count
        )
    }

    public static func mistakes(_ run: EvalRun, sentences: [EvalSentence], terms: [String]) -> [EvalMistake] {
        scoredItems(run, sentences: sentences).compactMap { scored in
            let hypothesis = scored.item.hypothesis ?? ""
            let errors = CharacterErrorRate.measure(reference: scored.reference, hypothesis: hypothesis)
            let missed = TermAccuracy.measure(reference: scored.reference, hypothesis: hypothesis, terms: terms).missed
            guard errors.edits > 0 || !missed.isEmpty else { return nil }
            return EvalMistake(
                id: scored.item.id,
                reference: scored.reference,
                hypothesis: scored.item.error.map { "(失敗: \($0))" } ?? hypothesis,
                errors: errors,
                missedTerms: missed
            )
        }
    }

    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    public static func markdown(_ summaries: [EvalSummary]) -> String {
        let header = [
            "| 認識 | ヒント | マイク | 文字誤り率 | 用語正答率 | 待ち時間(中央値) | 10秒以上の文 | 文の数 | 失敗 |",
            "| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |"
        ]
        let rows = summaries.map { summary in
            [
                summary.model.map { "\(summary.engine)(\($0))" } ?? summary.engine,
                hintLabel(summary.hints),
                summary.mic,
                percent(summary.errors.rate),
                percent(summary.terms.rate),
                seconds(summary.medianLatency),
                seconds(summary.medianLatencyLong),
                String(summary.count),
                String(summary.failures)
            ].joined(separator: " | ")
        }
        return (header + rows.map { "| \($0) |" }).joined(separator: "\n")
    }

    public static func mistakesMarkdown(title: String, _ mistakes: [EvalMistake]) -> String {
        let body = mistakes.map { mistake in
            [
                "- **\(mistake.id)**(誤り \(mistake.errors.edits)字)",
                "  - 正解: \(mistake.reference)",
                "  - 認識: \(mistake.hypothesis)",
                mistake.missedTerms.isEmpty ? nil : "  - 取りこぼした語: \(mistake.missedTerms.joined(separator: "・"))"
            ].compactMap { $0 }.joined(separator: "\n")
        }
        return (["## \(title)", ""] + (body.isEmpty ? ["誤りなし"] : body)).joined(separator: "\n")
    }

    static func scoredItems(_ run: EvalRun, sentences: [EvalSentence]) -> [(item: EvalItem, reference: String)] {
        let references = Dictionary(uniqueKeysWithValues: sentences.map { ($0.id, $0.text) })
        return run.items.compactMap { item in references[item.id].map { (item: item, reference: $0) } }
    }

    static func hintLabel(_ hints: HintMode) -> String {
        switch hints {
        case .on: "あり"
        case .off: "なし"
        case .none: "—"
        }
    }

    static func percent(_ rate: Double) -> String {
        String(format: "%.1f%%", rate * 100)
    }

    static func seconds(_ value: Double?) -> String {
        value.map { String(format: "%.2f秒", $0) } ?? "—"
    }
}
