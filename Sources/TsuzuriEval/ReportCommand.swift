import ArgumentParser
import Foundation
import TsuzuriCore
import TsuzuriEvalKit

struct Report: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "eval/results/ の結果を表にし、report.md と mistakes.md を書く"
    )

    @OptionGroup var options: EvalOptions

    func run() throws {
        let paths = options.paths
        let sentences = try EvalStore.sentences(paths)
        let terms = try EvalStore.dictionary(paths).surfaces
        let runs = try EvalStore.runs(paths)
        guard !runs.isEmpty else {
            print("結果がありません。先に `swift run tsuzuri-eval run --engine soniox` などを実行してください")
            return
        }
        let summaries = runs
            .map { EvalReport.summarize($0, sentences: sentences, terms: terms) }
            .sorted { ($0.mic, $0.errors.rate) < ($1.mic, $1.errors.rate) }
        let table = EvalReport.markdown(summaries)
        let mistakes = runs.map { run in
            EvalReport.mistakesMarkdown(
                title: "\(run.engine) ヒント: \(run.hints.rawValue) マイク: \(run.mic)",
                EvalReport.mistakes(run, sentences: sentences, terms: terms)
            )
        }
        try FileManager.default.createDirectory(at: paths.results, withIntermediateDirectories: true)
        try ("# 評価の結果\n\n" + table + "\n").write(to: paths.results.appending(path: "report.md"), atomically: true, encoding: .utf8)
        try ("# 正解と違った文\n\n" + mistakes.joined(separator: "\n\n") + "\n").write(to: paths.results.appending(path: "mistakes.md"), atomically: true, encoding: .utf8)
        print(table)
        print("\n書き出し: \(paths.results.appending(path: "report.md").path) / mistakes.md")
    }
}
