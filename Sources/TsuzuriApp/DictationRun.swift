import Foundation
import TsuzuriCore
import TsuzuriEngines

/// 1回の音声入力。手元の録音を始め、合図があったら Soniox につないで、ためた音声から順に送る
final class DictationRun {
    enum Outcome {
        case text(String, samples: [Float])
        case failed(String, samples: [Float])
    }

    /// 接続と確定の待ち時間の上限(設計書「1回の音声入力の流れ」の初期値)
    static let connectTimeout = 2.0
    static let finishTimeout = 3.0

    let startedAt = Date()
    private let recorder: MicrophoneRecorder
    private let continuation: AsyncStream<[Float]>.Continuation
    private let chunks: AsyncStream<[Float]>
    private var session: SonioxLiveSession?
    private var sender: Task<Void, Never>?
    private var stopped = false
    private(set) var isCancelled = false
    /// 録音中に分かった失敗(つながらない・送れない)
    private(set) var failure: String?

    /// Mac 内で認識するときに、話している途中の文字を出す認識へも標本を渡す
    let tap = SampleTap()

    init(hud: RecordingHUD) {
        let (chunks, continuation) = AsyncStream.makeStream(of: [Float].self)
        self.chunks = chunks
        self.continuation = continuation
        self.recorder = MicrophoneRecorder(onSamples: Self.forward(to: continuation, tap: tap, hud: hud))
    }

    /// 音声の処理の糸で呼ばれる。送る列へ入れ、音量だけ画面へ渡す
    nonisolated private static func forward(to continuation: AsyncStream<[Float]>.Continuation, tap: SampleTap, hud: RecordingHUD) -> @Sendable ([Float]) -> Void {
        { [weak hud] samples in
            continuation.yield(samples)
            tap.append(samples)
            let level = MicrophoneRecorder.level(of: samples)
            Task { @MainActor in hud?.level = level }
        }
    }

    func startCapture() throws {
        try recorder.start()
    }

    /// Soniox につなぐ。`terms` は語のヒント。つながるまでの音声は列にたまっていて、つながったら順に送る
    func connect(apiKey: String, terms: [String], onUpdate: @escaping @Sendable (TranscriptAssembler) -> Void, onFailure: @escaping (String) -> Void) {
        let settings = SonioxSettings(terms: terms, clientReferenceID: "tsuzuri-app", paceInRealTime: false)
        let session = SonioxLiveSession(apiKey: apiKey, settings: settings, onUpdate: onUpdate)
        self.session = session
        let chunks = chunks
        sender = Task { [weak self] in
            do {
                try await session.connect(timeoutSeconds: Self.connectTimeout)
            } catch {
                self?.fail(Self.describe(error, connecting: true), onFailure)
                return
            }
            do {
                for await chunk in chunks {
                    try await session.send(chunk)
                }
            } catch {
                self?.fail(Self.describe(error, connecting: false), onFailure)
            }
        }
    }

    private func fail(_ message: String, _ onFailure: (String) -> Void) {
        guard !isCancelled, failure == nil else { return }
        failure = message
        onFailure(message)
    }

    /// 止めて、確定した文字を待つ
    func stop() async -> Outcome {
        let samples = stopCapture()
        await sender?.value
        guard let session else { return .failed("Soniox につないでいません", samples: samples) }
        if let failure {
            await session.cancel()
            return .failed(failure, samples: samples)
        }
        do {
            let text = try await session.finish(timeoutSeconds: Self.finishTimeout)
            return .text(text, samples: samples)
        } catch {
            return .failed(Self.describe(error, connecting: false), samples: samples)
        }
    }

    /// 録音だけを止めて音声を返す(Mac 内で認識するとき。Soniox にはつないでいない)
    func stopRecording() -> [Float] {
        sender?.cancel()
        return stopCapture()
    }

    /// 取り消す(Esc・同時押し)。音声も文字も残さない
    func cancel() {
        isCancelled = true
        _ = stopCapture()
        sender?.cancel()
        if let session {
            Task { await session.cancel() }
        }
    }

    private func stopCapture() -> [Float] {
        guard !stopped else { return [] }
        stopped = true
        let samples = recorder.stop()
        continuation.finish()
        return samples
    }

    static func describe(_ error: any Error, connecting: Bool) -> String {
        switch error {
        case SonioxError.timedOut where connecting:
            "Soniox に\(Int(connectTimeout))秒でつながりませんでした"
        case SonioxError.timedOut:
            "Soniox の確定が\(Int(finishTimeout))秒を超えました"
        case let error as SonioxError:
            error.description
        case let error as URLError:
            "Soniox との通信に失敗しました(\(error.code.rawValue))"
        default:
            "Soniox との通信に失敗しました(\(error.localizedDescription))"
        }
    }
}

/// 録音の標本を、あとから付く受け手へ渡す。受け手が付くまでは、録音の頭を落とさないようにためておく
nonisolated final class SampleTap: @unchecked Sendable {
    /// ためておく上限(16kHz で30秒)
    static let pendingLimit = 16_000 * 30
    private let lock = NSLock()
    private var pending: [Float] = []
    private var consumer: (@Sendable ([Float]) -> Void)?
    private var closed = false

    func append(_ samples: [Float]) {
        let consumer: (@Sendable ([Float]) -> Void)? = lock.withLock {
            guard !closed else { return nil }
            if self.consumer == nil, pending.count < Self.pendingLimit { pending += samples }
            return self.consumer
        }
        consumer?(samples)
    }

    /// 受け手を付け、ためておいた分から渡す
    func attach(_ consumer: @escaping @Sendable ([Float]) -> Void) {
        let backlog: [Float] = lock.withLock {
            guard !closed else { return [] }
            self.consumer = consumer
            defer { pending = [] }
            return pending
        }
        if !backlog.isEmpty { consumer(backlog) }
    }

    /// これ以上渡さない
    func close() {
        lock.withLock {
            closed = true
            consumer = nil
            pending = []
        }
    }
}
