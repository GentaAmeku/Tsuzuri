@preconcurrency import AVFoundation
import Foundation
import Speech
import TsuzuriCore

/// Apple の認識(DictationTranscriber)に、録音を少しずつ渡して、話している途中の文字を受け取る(Mac 内の認識の途中の文字に使う)。
/// 貼る文字は WhisperKit で作り、こちらは表示だけに使う
public final class AppleSpeechLive: @unchecked Sendable {
    private let analyzer: SpeechAnalyzer
    private let transcriber: DictationTranscriber
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private let format: AVAudioFormat
    private let converter: AVAudioConverter?
    private var reader: Task<Void, Never>?
    private let lock = NSLock()
    private var finalText = ""
    private var volatileText = ""

    /// 途中の文字が変わるたびに呼ばれる(確定した文字・まだ変わりうる文字)
    public var onUpdate: (@Sendable (String, String) -> Void)?

    private init(analyzer: SpeechAnalyzer, transcriber: DictationTranscriber, input: AsyncStream<AnalyzerInput>.Continuation, format: AVAudioFormat) {
        self.analyzer = analyzer
        self.transcriber = transcriber
        self.input = input
        self.format = format
        converter = AVAudioConverter(from: AudioFile.processingFormat, to: format)
    }

    /// 一度確かめた言語とモデルの状態。OS の認識の常駐プロセスは、しばらく使わないと終わる。終わったあとは、
    /// このプロセスからのモデルの問い合わせが「入っていない」と答えるようになるが、認識そのものは動く。
    /// そこで、確かめるのは最初の1回だけにする
    private static let checked = CheckedLocale()

    /// 始める。日本語のモデルが入っていなければ失敗する(取得はしない)
    public static func start(terms: [String]) async throws -> AppleSpeechLive {
        let locale: Locale
        if let known = checked.locale {
            locale = known
        } else {
            guard let supported = await DictationTranscriber.supportedLocale(equivalentTo: AppleSpeech.locale) else {
                throw AppleSpeechError.localeUnsupported(AppleSpeech.locale.identifier)
            }
            locale = supported
        }
        let transcriber = DictationTranscriber(
            locale: locale,
            contentHints: [],
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        if checked.locale == nil {
            // モデルはシステムに入っていても、このアプリへの言語の割り当てが無いと使えない。割り当てだけ行い、取得はしない
            if await AssetInventory.status(forModules: [transcriber]) != .installed {
                _ = try? await AssetInventory.reserve(locale: locale)
            }
            try await AppleSpeech.ensureAssets(for: [transcriber], allowDownload: false)
            checked.locale = locale
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if !terms.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = terms
            try await analyzer.setContext(context)
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw AppleSpeechError.localeUnsupported("音声の形式")
        }
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let live = AppleSpeechLive(analyzer: analyzer, transcriber: transcriber, input: continuation, format: format)
        try await analyzer.start(inputSequence: stream)
        live.reader = Task { [weak live] in
            do {
                for try await result in transcriber.results {
                    live?.receive(String(result.text.characters), isFinal: result.isFinal)
                }
            } catch {}
        }
        return live
    }

    /// 16kHz・モノラルの標本を渡す。音声の処理の糸から呼んでよい
    public func feed(_ samples: [Float]) {
        guard !samples.isEmpty,
              let source = AVAudioPCMBuffer(pcmFormat: AudioFile.processingFormat, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        source.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { pointer in
            source.floatChannelData![0].update(from: pointer.baseAddress!, count: samples.count)
        }
        guard let buffer = convert(source) else { return }
        input.yield(AnalyzerInput(buffer: buffer))
    }

    /// 入力を閉じて終える。最後に確定した文字を返す
    public func finish() async -> String {
        input.finish()
        try? await analyzer.finalizeAndFinishThroughEndOfInput()
        await reader?.value
        return lock.withLock { finalText + volatileText }
    }

    /// 途中で捨てる
    public func cancel() async {
        input.finish()
        await analyzer.cancelAndFinishNow()
        reader?.cancel()
    }

    private func receive(_ text: String, isFinal: Bool) {
        let (final, volatile): (String, String) = lock.withLock {
            if isFinal {
                finalText += text
                volatileText = ""
            } else {
                volatileText = text
            }
            return (finalText, volatileText)
        }
        onUpdate?(final, volatile)
    }

    private func convert(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if source.format == format { return source }
        guard let converter else { return nil }
        let capacity = AVAudioFrameCount(Double(source.frameLength) * format.sampleRate / source.format.sampleRate) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        // 入力を渡す処理は convert の中で同期して呼ばれるので、この変数を別の糸と取り合うことはない
        nonisolated(unsafe) var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return source
        }
        return error == nil ? output : nil
    }
}

/// 確かめ済みの言語(別の糸から読み書きする)
private final class CheckedLocale: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Locale?

    var locale: Locale? {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

extension AppleSpeechLive {
    /// 確かめ用。日本語のモデルの状態と、このアプリに割り当てた言語
    public static func assetReport() async -> String {
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: AppleSpeech.locale) else { return "日本語に対応していません" }
        let transcriber = DictationTranscriber(locale: locale, contentHints: [], transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
        let status = await AssetInventory.status(forModules: [transcriber])
        let reserved = await AssetInventory.reservedLocales.map(\.identifier)
        return "モデルの状態: \(status) / 割り当て済みの言語: \(reserved)"
    }
}

extension AppleSpeechLive {
    /// 日本語の認識モデルを、システムに取得させる(入っていれば何もしない)。`tsuzuri-eval fetch-model` から使う
    public static func installJapaneseModel() async throws {
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: AppleSpeech.locale) else {
            throw AppleSpeechError.localeUnsupported(AppleSpeech.locale.identifier)
        }
        let transcriber = DictationTranscriber(locale: locale, contentHints: [], transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
        // システムに入っていても、このプロセスへの言語の割り当てが無いと「入っていない」と答えるので、先に割り当てる。
        // 入っていれば、ここで取得せずに終わる
        if await AssetInventory.status(forModules: [transcriber]) != .installed {
            _ = try? await AssetInventory.reserve(locale: locale)
        }
        try await AppleSpeech.ensureAssets(for: [transcriber], allowDownload: true)
    }
}
