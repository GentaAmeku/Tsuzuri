import ArgumentParser
import TsuzuriEngines

struct Readings: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Apple Foundation Models に、語のカタカナの読み(置き換え元の候補)を出させる。辞書の読みの提案を確かめる"
    )

    @Argument(help: "読みを出させる表記(例: Vitest GraphQL)")
    var surfaces: [String]

    func run() async throws {
        guard ReadingSuggester.isAvailable else {
            throw ValidationError("Apple Foundation Models を使えません(Apple Intelligence が無効など)")
        }
        for surface in surfaces {
            let readings = try await ReadingSuggester.suggest(for: surface)
            print("\(surface): \(readings.joined(separator: "、"))")
        }
    }
}
