import Foundation
import TsuzuriCore

/// Soniox への1回分の接続。話している間に音声を少しずつ送り、途中の文字を `onUpdate` で返す。
/// 使い方: connect → send(何度でも)→ finish。やめるときは cancel
public actor SonioxLiveSession {
    private let task: URLSessionWebSocketTask
    private let settings: SonioxSettings
    private let onUpdate: @Sendable (TranscriptAssembler) -> Void
    private var receiver: Task<String, any Error>?

    public init(apiKey: String, settings: SonioxSettings, onUpdate: @escaping @Sendable (TranscriptAssembler) -> Void = { _ in }) {
        var request = URLRequest(url: SonioxRealtime.endpoint)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        self.task = URLSession.shared.webSocketTask(with: request)
        self.settings = settings
        self.onUpdate = onUpdate
    }

    /// つないで設定メッセージを送る。決めた秒数でつながらなければ `SonioxError.timedOut`
    public func connect(timeoutSeconds: Double) async throws {
        let task = task
        let start = try SonioxRealtime.startMessage(settings)
        task.resume()
        // 送信は接続が開くまで待つので、設定メッセージを送り終えた時点を「つながった」とみなす
        try await withTimeout(seconds: timeoutSeconds) {
            try await task.send(.string(start))
        }
        let onUpdate = onUpdate
        receiver = Task {
            try await Self.receiveUntilFinished(task, onUpdate: onUpdate)
        }
    }

    /// 16kHz・モノラルの標本列を送る
    public func send(_ samples: [Float]) async throws {
        guard !samples.isEmpty else { return }
        try await task.send(.data(AudioFile.pcm16LittleEndian(samples)))
    }

    /// 終わりの合図(空のテキスト)を送り、確定した文字を待つ。決めた秒数を超えたら `SonioxError.timedOut`
    public func finish(timeoutSeconds: Double) async throws -> String {
        guard let receiver else { throw SonioxError.unexpectedMessage }
        try await task.send(.string(""))
        defer { task.cancel(with: .normalClosure, reason: nil) }
        return try await withTimeout(seconds: timeoutSeconds) {
            try await receiver.value
        }
    }

    public func cancel() {
        receiver?.cancel()
        task.cancel(with: .normalClosure, reason: nil)
    }

    static func receiveUntilFinished(_ task: URLSessionWebSocketTask, onUpdate: @Sendable (TranscriptAssembler) -> Void) async throws -> String {
        var assembler = TranscriptAssembler()
        while true {
            let response = try SonioxRealtime.decode(try await task.receive())
            if let code = response.errorCode {
                throw SonioxError.server(code: code, type: response.errorType ?? "", message: response.errorMessage ?? "")
            }
            assembler.apply(response.assemblerTokens)
            onUpdate(assembler)
            if response.finished == true {
                return assembler.finalText
            }
        }
    }
}
