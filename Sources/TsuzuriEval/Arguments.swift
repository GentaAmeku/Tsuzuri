import ArgumentParser
import TsuzuriCore
import TsuzuriEvalKit

struct EvalOptions: ParsableArguments {
    @Option(help: "評価セットのフォルダ(リポジトリの直下から見たパス)")
    var evalDir = "eval"

    var paths: EvalPaths { EvalPaths(evalDirectory: evalDir) }
}

enum Mic: String, ExpressibleByArgument, CaseIterable {
    case macbook
    case airpods

    /// AirPods は最初の10文だけ録る(設計書の「精度の測り方」)
    var defaultSentenceLimit: Int? {
        switch self {
        case .macbook: nil
        case .airpods: 10
        }
    }
}

enum Engine: String, ExpressibleByArgument, CaseIterable {
    case soniox
    case whisperkit
    case appleDictation = "apple-dictation"
    case appleSpeech = "apple-speech"

    /// 語のヒントを受け付けるか(SpeechTranscriber は受け付けない)
    var acceptsHints: Bool {
        self != .appleSpeech
    }
}

enum HintChoice: String, ExpressibleByArgument, CaseIterable {
    case on
    case off
    case both

    func modes(for engine: Engine) -> [HintMode] {
        guard engine.acceptsHints else { return [.none] }
        switch self {
        case .on: return [.on]
        case .off: return [.off]
        case .both: return [.off, .on]
        }
    }
}

/// 対象の文を選ぶ。`only` が空なら全文(マイクの既定の文数まで)
func selectSentences(_ sentences: [EvalSentence], only: [String], mic: Mic) -> [EvalSentence] {
    guard only.isEmpty else { return sentences.filter { only.contains($0.id) } }
    return mic.defaultSentenceLimit.map { Array(sentences.prefix($0)) } ?? sentences
}
