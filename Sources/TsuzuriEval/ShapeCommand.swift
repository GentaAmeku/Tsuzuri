import ArgumentParser
import Foundation
import TsuzuriCore
import TsuzuriEvalKit

struct Shape: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "認識の出力に整える規則を1段ずつ当て、途中の文字を見せる(辞書を直したときの確かめ用)"
    )

    @OptionGroup var options: EvalOptions

    @Option(help: "使う辞書のファイル。省くと評価用の辞書(eval/dictionary.json)")
    var dictionary: String?

    @Argument(help: "認識の出力の文")
    var text: String

    func run() throws {
        let file: DictionaryFile
        if let dictionary {
            file = try JSONDecoder().decode(DictionaryFile.self, from: Data(contentsOf: URL(filePath: dictionary)))
        } else {
            file = try EvalStore.dictionary(options.paths)
        }
        let normalized = Normalizer.normalize(text)
        let withoutFillers = FillerRemover.remove(file.fillers, from: normalized)
        let replaced = TermReplacer(entries: file.entries).replace(withoutFillers)
        let spaced = WaObunSpacing.apply(replaced)
        print("認識の出力: \(text)")
        print("正規化: \(normalized)")
        print("つなぎ言葉: \(withoutFillers)")
        print("置き換え: \(replaced)")
        print("和欧間スペース: \(spaced)")
    }
}
