import ArgumentParser
import Foundation
import TsuzuriCore
import TsuzuriEngines
import TsuzuriEvalKit

struct Record: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "評価セットを1文ずつ読み上げて録音する(録音は eval/recordings/ に置き、git に入れない)"
    )

    @OptionGroup var options: EvalOptions

    @Option(help: "使うマイク。入力の機器はシステム設定で切り替えておく")
    var mic: Mic = .macbook

    @Option(parsing: .upToNextOption, help: "録る文の番号(例: --only ai-01 sl-03)。省くと全文(AirPods は最初の10文)")
    var only: [String] = []

    @Flag(help: "録音済みの文も録り直す")
    var overwrite = false

    func run() async throws {
        let paths = options.paths
        let targets = selectSentences(try EvalStore.sentences(paths), only: only, mic: mic)
            .filter { overwrite || !FileManager.default.fileExists(atPath: paths.recording(mic: mic.rawValue, id: $0.id).path) }
        guard !targets.isEmpty else {
            print("録る文がありません(録音済みの文を録り直すときは --overwrite)")
            return
        }
        guard await MicrophoneRecorder.requestAccess() else {
            throw ValidationError("マイクの使用が許可されていません。システム設定 > プライバシーとセキュリティ > マイク で、このターミナルを許可してください")
        }
        print("入力の機器: \(MicrophoneRecorder.currentInputName)(\(mic.rawValue) として保存)")
        print("Enter で録音を始め、読み終えたらもう一度 Enter。s で飛ばす、q で終わる\n")

        for (index, sentence) in targets.enumerated() {
            print("[\(index + 1)/\(targets.count)] \(sentence.id)")
            print("  \(sentence.text)")
            guard try recordUntilAccepted(sentence, paths: paths) else {
                print("終了しました")
                return
            }
        }
        print("すべて録り終えました")
    }

    /// 1文を、本人が良しとするまで録り直す。q のときは false
    func recordUntilAccepted(_ sentence: EvalSentence, paths: EvalPaths) throws -> Bool {
        while true {
            switch ask("  Enter で録音開始(s: 飛ばす, q: 終わる)> ") {
            case "q": return false
            case "s": return true
            default: break
            }
            let recorder = MicrophoneRecorder()
            try recorder.start()
            _ = ask("  ● 録音中… 読み終えたら Enter ")
            let samples = recorder.stop()
            let seconds = Double(samples.count) / AudioFile.sampleRate
            guard seconds >= 0.5 else {
                print("  短すぎるので保存しませんでした。もう一度録ります")
                continue
            }
            let url = paths.recording(mic: mic.rawValue, id: sentence.id)
            try AudioFile.writeWAV(samples: samples, to: url)
            print(String(format: "  保存しました(%.1f秒)", seconds))
            switch ask("  Enter で次へ(r: 録り直す, q: 終わる)> ") {
            case "r": continue
            case "q": return false
            default: return true
            }
        }
    }
}
