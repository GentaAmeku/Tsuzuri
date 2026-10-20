import ArgumentParser
import Foundation
import TsuzuriCore
import TsuzuriEngines
import TsuzuriEvalKit

struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "録音を認識させ、結果を eval/results/ に残す(Qwen3-ASR は Tools/Qwen3Eval で測る)"
    )

    @OptionGroup var options: EvalOptions

    @Option(help: "認識(soniox / whisperkit / apple-dictation / apple-speech)")
    var engine: Engine

    @Option(help: "語のヒント(on / off / both)。apple-speech は受け付けないので無視する")
    var hints: HintChoice = .both

    @Option(help: "どのマイクの録音を使うか")
    var mic: Mic = .macbook

    @Option(parsing: .upToNextOption, help: "認識させる文の番号。省くと録音のある全文")
    var only: [String] = []

    @Option(help: "WhisperKit のモデル")
    var whisperModel = WhisperKitEngine.defaultModel

    @Flag(help: "Mac 内の認識のモデルを取得してよい(WhisperKit は約626MB、Apple の日本語モデルはシステムが取得)")
    var allowDownload = false

    @Flag(help: "Soniox に録音を話す速さで流さず、まとめて送る(待ち時間は正しく測れない)")
    var noPacing = false

    func run() async throws {
        let paths = options.paths
        let sentences = try EvalStore.sentences(paths).filter { only.isEmpty || only.contains($0.id) }
        let terms = try EvalStore.dictionary(paths).hintTerms
        let transcriber = try await makeTranscriber()
        for mode in hints.modes(for: engine) {
            print("== \(engine.rawValue) ヒント: \(mode.rawValue) マイク: \(mic.rawValue)")
            let items = await EvalRunner.run(sentences: sentences, paths: paths, mic: mic.rawValue) { _, url in
                try await transcriber.transcribe(url, mode == .on ? terms : [])
            }
            guard !items.isEmpty else {
                throw ValidationError("\(mic.rawValue) の録音がありません。先に `swift run tsuzuri-eval record --mic \(mic.rawValue)` で録ってください")
            }
            let run = EvalRun(engine: engine.rawValue, model: transcriber.model, hints: mode, mic: mic.rawValue, createdAt: Date(), items: items)
            let url = try EvalStore.write(run, paths)
            let summary = EvalReport.summarize(run, sentences: sentences, terms: try EvalStore.dictionary(paths).surfaces)
            print(String(
                format: "文字誤り率 %.1f%% / 用語正答率 %.1f%% / 失敗 %d → %@\n",
                summary.errors.rate * 100, summary.terms.rate * 100, summary.failures, url.path
            ))
        }
    }

    /// 認識ごとの準備(キーの読み出しやモデルの読み込み)を1回だけ行い、文ごとに呼ぶ関数を返す
    func makeTranscriber() async throws -> Transcriber {
        switch engine {
        case .soniox:
            let apiKey = try SonioxKeychain.load()
            let paced = !noPacing
            return Transcriber(model: "stt-rt-v5") { url, terms in
                let settings = SonioxSettings(terms: terms, clientReferenceID: "tsuzuri-eval", paceInRealTime: paced)
                return try await SonioxRealtime.transcribe(samples: try AudioFile.readSamples(from: url), apiKey: apiKey, settings: settings)
            }
        case .whisperkit:
            let whisper = try await WhisperKitEngine.load(model: whisperModel, allowDownload: allowDownload)
            return Transcriber(model: whisper.model) { url, terms in
                try await whisper.transcribe(samples: try AudioFile.readSamples(from: url), terms: terms)
            }
        case .appleDictation, .appleSpeech:
            let mode: AppleSpeech.Mode = engine == .appleDictation ? .dictation : .speech
            let allow = allowDownload
            return Transcriber(model: mode == .dictation ? "DictationTranscriber" : "SpeechTranscriber") { url, terms in
                try await AppleSpeech.transcribe(fileURL: url, mode: mode, terms: terms, allowAssetDownload: allow)
            }
        }
    }
}

/// 文ごとに呼ぶ認識。`transcribe` は録音のパスと語のヒントを受け取る
struct Transcriber {
    let model: String
    let transcribe: (URL, [String]) async throws -> Transcription
}
