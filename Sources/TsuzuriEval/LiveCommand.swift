import ArgumentParser
import Foundation
import TsuzuriCore
import TsuzuriEngines
import TsuzuriEvalKit

/// Mac 内の認識で、話している途中の文字を出す試験。段階0の録音を実際の速さで流し、途中の文字の出方と、
/// 止めてから貼る文字が出るまでの時間を測る(貼る文字はどの方式も WhisperKit で作る)
struct Live: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Mac 内の認識で話している途中の文字を出す方式を、段階0の録音を実際の速さで流して比べる(試験)"
    )

    enum Method: String, ExpressibleByArgument, CaseIterable {
        /// 途中の文字を出さない(今の作り)
        case none
        /// 録音中に WhisperKit で、それまでの録音を繰り返し認識する
        case whisperkit
        /// 途中の文字だけ Apple の認識(DictationTranscriber)で出す
        case apple
    }

    @OptionGroup var options: EvalOptions

    @Option(help: "方式(none・whisperkit・apple)。省くと3つとも")
    var method: [Method] = Method.allCases

    @Option(help: "この文だけを流す(例: --only ai-01)。省くと最初の8文")
    var only: [String] = []

    @Option(help: "WhisperKit で認識し直す間隔(秒)")
    var interval = 1.0

    func run() async throws {
        let paths = options.paths
        let sentences = try EvalStore.sentences(paths)
        let targets = only.isEmpty ? Array(sentences.prefix(8)) : sentences.filter { only.contains($0.id) }
        let dictionary = try EvalStore.dictionary(paths)
        let terms = Array(dictionary.hintTerms.prefix(WhisperKitEngine.hintLimit))
        print("WhisperKit を読み込んでいます…")
        let engine = try await WhisperKitEngine.load(model: WhisperKitEngine.defaultModel, allowDownload: false)
        // 1回目は遅いので、温めておく
        _ = try? await engine.transcribe(samples: [Float](repeating: 0, count: 16_000), terms: [])

        var lines = ["| 方式 | 文 | 途中の文字が最初に出るまで | 途中の文字が出た回数 | 止めてから貼る文字まで | 貼る文字の誤り率 |", "| --- | --- | ---: | ---: | ---: | ---: |"]
        for method in method {
            var stops: [Double] = []
            for sentence in targets {
                let url = paths.recording(mic: "macbook", id: sentence.id)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                let samples = try AudioFile.readSamples(from: url)
                let result = try await simulate(method, samples: samples, engine: engine, terms: terms)
                stops.append(result.stopToFinal)
                let error = CharacterErrorRate.measure(reference: sentence.text, hypothesis: result.final).rate
                lines.append("| \(method.rawValue) | \(sentence.id) | \(result.firstPartial.map { String(format: "%.1f秒", $0) } ?? "—") | \(result.partialCount) | \(String(format: "%.2f秒", result.stopToFinal)) | \(String(format: "%.1f%%", error * 100)) |")
                print("\(method.rawValue) \(sentence.id): 途中 \(result.partialCount)回 / 止めてから \(String(format: "%.2f", result.stopToFinal))秒 / 最後の途中の文字: \(result.lastPartial)")
            }
            let average = stops.isEmpty ? 0 : stops.reduce(0, +) / Double(stops.count)
            lines.append("| \(method.rawValue) | 平均 | | | \(String(format: "%.2f秒", average)) | |")
        }
        let table = lines.joined(separator: "\n")
        print("\n" + table)
        try FileManager.default.createDirectory(at: paths.results, withIntermediateDirectories: true)
        try ("# Mac 内の認識の途中の文字(試験)\n\n" + table + "\n").write(to: paths.results.appending(path: "live.md"), atomically: true, encoding: .utf8)
    }

    struct Result {
        var firstPartial: Double?
        var partialCount = 0
        var lastPartial = ""
        var stopToFinal = 0.0
        var final = ""
    }

    /// 0.1秒ずつ実際の速さで流す。止めた時刻(録音の終わり)から、貼る文字ができるまでを測る
    func simulate(_ method: Method, samples: [Float], engine: WhisperKitEngine, terms: [String]) async throws -> Result {
        let chunk = 1_600
        let state = PartialState()
        let started = ContinuousClock.now
        var apple: AppleSpeechLive?
        if method == .apple {
            let live = try await AppleSpeechLive.start(terms: terms)
            live.onUpdate = { final, volatile in state.record(final + volatile, at: (ContinuousClock.now - started).seconds) }
            apple = live
        }
        var inFlight: Task<Void, Never>?
        var lastRun = -interval
        var fed = 0
        while fed < samples.count {
            let next = min(samples.count, fed + chunk)
            let piece = Array(samples[fed..<next])
            fed = next
            apple?.feed(piece)
            let audioTime = Double(fed) / 16_000
            if method == .whisperkit, audioTime - lastRun >= interval, inFlight == nil || state.isIdle {
                lastRun = audioTime
                let sofar = Array(samples[0..<fed])
                state.setBusy(true)
                inFlight = Task.detached {
                    if let text = try? await engine.transcribe(samples: sofar, terms: terms).text {
                        state.record(text, at: (ContinuousClock.now - started).seconds)
                    }
                    state.setBusy(false)
                }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        // 止めた: Apple の認識は捨て、WhisperKit の認識し直しが走っていれば終わるのを待ってから、全体を認識する
        let stopped = ContinuousClock.now
        if let apple { _ = await apple.finish() }
        await inFlight?.value
        let final = try await engine.transcribe(samples: samples, terms: terms).text
        var result = state.snapshot()
        result.stopToFinal = (ContinuousClock.now - stopped).seconds
        result.final = final
        return result
    }
}

/// 途中の文字の記録(別の糸から書く)
final class PartialState: @unchecked Sendable {
    private let lock = NSLock()
    private var result = Live.Result()
    private var busy = false

    func record(_ text: String, at seconds: Double) {
        lock.withLock {
            guard !text.isEmpty, text != result.lastPartial else { return }
            if result.firstPartial == nil { result.firstPartial = seconds }
            result.partialCount += 1
            result.lastPartial = text
        }
    }

    func setBusy(_ value: Bool) { lock.withLock { busy = value } }
    var isIdle: Bool { lock.withLock { !busy } }
    func snapshot() -> Live.Result { lock.withLock { result } }
}

extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
