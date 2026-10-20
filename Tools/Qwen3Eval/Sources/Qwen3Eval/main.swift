import Foundation
import Qwen3ASR
import TsuzuriCore
import TsuzuriEngines
import TsuzuriEvalKit

// 使い方: Tools/Qwen3Eval で
//   swift run -c release Qwen3Eval [--mic macbook|airpods] [--hints on|off|both] [--allow-download] [--model <HF の ID>] [--eval-dir ../../eval]

struct Arguments {
    var evalDir = "../../eval"
    var mic = "macbook"
    var hints = "both"
    var allowDownload = false
    var model = Qwen3ASRModel.largeModelId

    init(_ arguments: [String]) {
        var rest = arguments[...]
        while let flag = rest.popFirst() {
            switch flag {
            case "--eval-dir": evalDir = rest.popFirst() ?? evalDir
            case "--mic": mic = rest.popFirst() ?? mic
            case "--hints": hints = rest.popFirst() ?? hints
            case "--model": model = rest.popFirst() ?? model
            case "--allow-download": allowDownload = true
            default: print("知らない指定です: \(flag)")
            }
        }
    }

    var modes: [HintMode] {
        switch hints {
        case "on": [.on]
        case "off": [.off]
        default: [.off, .on]
        }
    }
}

/// モデルは ~/Library/Caches/Tsuzuri/models/qwen3-asr/<ID> に置く。無ければ、許可があるときだけ取得する
func loadModel(_ arguments: Arguments) async throws -> Qwen3ASRModel {
    let directory = try ModelCache.directory()
        .appending(path: "qwen3-asr/\(arguments.model.replacingOccurrences(of: "/", with: "--"))", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    do {
        return try await Qwen3ASRModel.fromPretrained(modelId: arguments.model, cacheDir: directory, offlineMode: true)
    } catch {
        guard arguments.allowDownload else {
            print("Qwen3-ASR のモデル \(arguments.model)(1.7B の 8bit で約2GB)がまだありません。--allow-download を付けると取得します")
            exit(1)
        }
        return try await Qwen3ASRModel.fromPretrained(modelId: arguments.model, cacheDir: directory) { progress, status in
            print(String(format: "  %3.0f%% %@", progress * 100, status))
        }
    }
}

let arguments = Arguments(Array(CommandLine.arguments.dropFirst()))
let paths = EvalPaths(evalDirectory: arguments.evalDir)
let sentences = try EvalStore.sentences(paths)
let dictionary = try EvalStore.dictionary(paths)
let model = try await loadModel(arguments)
// 文脈の文。Qwen3-ASR は system プロンプトの文脈を手がかりに使う
let context = "用語: " + dictionary.hintTerms.joined(separator: "、")

for mode in arguments.modes {
    print("== qwen3 ヒント: \(mode.rawValue) マイク: \(arguments.mic)")
    let items = await EvalRunner.run(sentences: sentences, paths: paths, mic: arguments.mic) { _, url in
        let samples = try AudioFile.readSamples(from: url)
        let startedAt = ContinuousClock.now
        let text = model.transcribe(
            audio: samples,
            sampleRate: Int(AudioFile.sampleRate),
            language: "Japanese",
            context: mode == .on ? context : nil
        )
        return Transcription(text: text, latencySeconds: (ContinuousClock.now - startedAt).seconds)
    }
    guard !items.isEmpty else {
        print("\(arguments.mic) の録音がありません")
        exit(1)
    }
    let run = EvalRun(engine: "qwen3", model: arguments.model, hints: mode, mic: arguments.mic, createdAt: Date(), items: items)
    let url = try EvalStore.write(run, paths)
    let summary = EvalReport.summarize(run, sentences: sentences, terms: dictionary.surfaces)
    print(String(format: "文字誤り率 %.1f%% / 用語正答率 %.1f%% → %@\n", summary.errors.rate * 100, summary.terms.rate * 100, url.path))
}
