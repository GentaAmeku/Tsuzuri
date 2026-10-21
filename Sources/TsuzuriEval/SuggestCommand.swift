import ArgumentParser
import Foundation
import TsuzuriCore
import TsuzuriEngines
import TsuzuriEvalKit

struct Suggest: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "段階0の認識結果(語のヒントなし)に辞書の候補の洗い出しをかけ、挙げた割合・表記の当たり・外れの候補を出す(設計書の段階3)"
    )

    @OptionGroup var options: EvalOptions

    @Option(help: "使う結果(eval/results/ のファイル名から .json を除いたもの)。省くと、語のヒントを使わない Soniox・WhisperKit・Apple の2種")
    var runs: [String] = ["soniox-off-macbook", "whisperkit-off-macbook", "apple-dictation-off-macbook", "apple-speech-none-macbook"]

    @Option(help: "この文だけを流す(例: --only ai-01 --only ai-02)")
    var only: [String] = []

    @Flag(help: "文ごとの候補と判定を表示する")
    var verbose = false

    func run() async throws {
        guard SuspectScanner.isAvailable else {
            throw ValidationError("Apple Foundation Models を使えません(Apple Intelligence が無効など)")
        }
        let paths = options.paths
        let sentences = Dictionary(uniqueKeysWithValues: try EvalStore.sentences(paths).map { ($0.id, $0) })
        let dictionary = try EvalStore.dictionary(paths)
        // アプリと同じ入力にするため、空の辞書で整える段をかける(置き換えは起きない)
        let shaper = TextShaper(dictionary: DictionaryFile(version: dictionary.version, entries: [], fillers: dictionary.fillers))
        let available = Dictionary(uniqueKeysWithValues: try EvalStore.runs(paths).map { ($0.name, $0) })

        var rows: [(name: String, tally: SuggestionTally, seconds: [Double], failures: Int)] = []
        var details: [String] = []
        for name in runs {
            guard let run = available[name] else {
                print("結果がありません: \(name)")
                continue
            }
            var tally = SuggestionTally()
            var seconds: [Double] = []
            var failures = 0
            details.append("## \(name)\n")
            for item in run.items where only.isEmpty || only.contains(item.id) {
                guard let hypothesis = item.hypothesis, let sentence = sentences[item.id] else { continue }
                let shaped = shaper.shape(hypothesis)
                let marked = SuspectMarker.mark(shaped, dictionary: [])
                let clock = ContinuousClock.now
                let suspects: [Suspect]
                do {
                    suspects = try await SuspectScanner.scan(shaped, marked: marked)
                } catch {
                    failures += 1
                    details.append("- **\(item.id)** 洗い出しに失敗: \(error)\n")
                    continue
                }
                let candidates = CandidateFilter.candidates(from: suspects, in: shaped, dictionary: [], marked: marked)
                let elapsed = clock.duration(to: .now)
                seconds.append(Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
                let result = SuggestionScore.score(reference: sentence.text, hypothesis: shaped, terms: dictionary.surfaces, candidates: candidates)
                tally.add(result)
                let line = Self.describe(id: item.id, reference: sentence.text, shaped: shaped, marked: marked, candidates: candidates, result: result)
                details.append(line)
                if verbose { print(line) }
            }
            rows.append((name, tally, seconds, failures))
        }

        let total = rows.reduce(SuggestionTally()) { $0 + $1.tally }
        let table = Self.table(rows + [("合計", total, rows.flatMap(\.seconds), rows.reduce(0) { $0 + $1.failures })])
        let verdict = total.meetsTargets ? "目標に届いた" : "目標に届いていない"
        let report = "# 辞書の候補の洗い出し\n\n目標: ① 8割以上・③ 外れの異なる語が\(SuggestionTally.maximumFalsePositiveWords)語以下(160文で)。② は参考(\(verdict))\n\n\(table)\n\n" + details.joined(separator: "\n")
        try FileManager.default.createDirectory(at: paths.results, withIntermediateDirectories: true)
        let url = paths.results.appending(path: "suggest.md")
        try report.write(to: url, atomically: true, encoding: .utf8)
        print(table)
        print("\n\(verdict)。文ごとの候補: \(url.path)")
    }

    static func table(_ rows: [(name: String, tally: SuggestionTally, seconds: [Double], failures: Int)]) -> String {
        var lines = [
            "| 結果 | 文 | 誤った辞書の語 | ① 挙げた割合 | ② 表記の当たり(参考) | ③ 外れの異なる語 | 外れ(10文あたり) | 辞書の外の誤り | 時間(平均/最長) | 失敗 |",
            "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
        ]
        for row in rows {
            let t = row.tally
            let average = row.seconds.isEmpty ? 0 : row.seconds.reduce(0, +) / Double(row.seconds.count)
            lines.append(
                "| \(row.name) | \(t.sentences) | \(t.termErrors) | \(percent(t.coveredRate))(\(t.covered)/\(t.termErrors)) "
                    + "| \(percent(t.surfaceRate))(\(t.surfaceHits)/\(t.termCandidates)) | \(t.falsePositiveWords.count)語 | \(String(format: "%.1f", t.falsePositivesPerTen))(\(t.falsePositives)件) "
                    + "| \(t.otherErrors) | \(String(format: "%.1f", average))秒/\(String(format: "%.1f", row.seconds.max() ?? 0))秒 | \(row.failures) |"
            )
        }
        return lines.joined(separator: "\n")
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    static func describe(
        id: String, reference: String, shaped: String, marked: [String],
        candidates: [SuggestionCandidate], result: SuggestionScore.SentenceResult
    ) -> String {
        var lines = [
            "- **\(id)**",
            "  - 正解: \(reference)",
            "  - 認識: \(shaped)",
            "  - 印: \(marked.isEmpty ? "なし" : marked.joined(separator: "・"))",
        ]
        for (candidate, verdict) in zip(candidates, result.verdicts) {
            let label: String
            switch verdict {
            case let .term(terms, surfaceHit):
                label = "当たり(\(terms.joined(separator: "・")))" + (surfaceHit ? "" : "・表記は外れ")
            case .falsePositive:
                label = "外れ"
            case .otherError:
                label = "辞書の外の誤り"
            }
            lines.append("  - 候補: \(candidate.heard) → \(candidate.surfaces.joined(separator: " / "))(\(label))")
        }
        if !result.missed.isEmpty {
            lines.append("  - 取りこぼし: \(result.missed.joined(separator: "・"))")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

extension EvalRun {
    /// 結果のファイル名から .json を除いたもの(soniox-off-macbook など)
    var name: String { "\(engine)-\(hints.rawValue)-\(mic)" }
}
