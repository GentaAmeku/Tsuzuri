import ArgumentParser

@main
struct TsuzuriEval: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tsuzuri-eval",
        abstract: "本人の声の評価セットで、認識ごとの精度と待ち時間を測る(設計書の段階0)",
        subcommands: [SetKey.self, FetchModel.self, Record.self, Run.self, Report.self, Readings.self, Shape.self, Suggest.self, Live.self]
    )
}
