import Foundation
import TsuzuriCore

public enum SonioxError: Error, CustomStringConvertible {
    case server(code: Int, type: String, message: String)
    case unexpectedMessage
    case timedOut(seconds: Double)

    public var description: String {
        switch self {
        case let .server(code, type, message): "Soniox のエラー \(code) \(type): \(message)"
        case .unexpectedMessage: "Soniox から読めない応答が返りました"
        case let .timedOut(seconds): "Soniox の応答が \(Int(seconds)) 秒以内に終わりませんでした"
        }
    }
}

public struct SonioxSettings: Sendable {
    public var model: String
    public var languageHints: [String]
    /// 語のヒント(context.terms)。空なら context を送らない
    public var terms: [String]
    /// 使用量の記録に付ける名札。評価とふだんの利用を分けて追うため
    public var clientReferenceID: String?
    /// 音声を話す速さで送るか。待ち時間を実際の使い方に近い形で測るときに使う
    public var paceInRealTime: Bool
    public var timeoutSeconds: Double

    public init(
        model: String = "stt-rt-v5",
        languageHints: [String] = ["ja", "en"],
        terms: [String] = [],
        clientReferenceID: String? = nil,
        paceInRealTime: Bool = true,
        timeoutSeconds: Double = 60
    ) {
        self.model = model
        self.languageHints = languageHints
        self.terms = terms
        self.clientReferenceID = clientReferenceID
        self.paceInRealTime = paceInRealTime
        self.timeoutSeconds = timeoutSeconds
    }
}

/// Soniox のリアルタイム認識(WebSocket)。設定 → 音声 → 空のテキストで終わり、の順に送る
public enum SonioxRealtime {
    public static let endpoint = URL(string: "wss://stt-rt.soniox.com/transcribe-websocket")!
    /// 1回に送る音声。120ms(16kHz × 0.12秒)
    static let chunkSamples = 1_920

    public static func transcribe(samples: [Float], apiKey: String, settings: SonioxSettings) async throws -> Transcription {
        try await withTimeout(seconds: settings.timeoutSeconds) {
            try await stream(samples: samples, apiKey: apiKey, settings: settings)
        }
    }

    static func stream(samples: [Float], apiKey: String, settings: SonioxSettings) async throws -> Transcription {
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let task = URLSession.shared.webSocketTask(with: request)
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }

        try await task.send(.string(try startMessage(settings)))
        async let received = receiveUntilFinished(task)
        let endedAt = try await sendAudio(samples, over: task, paced: settings.paceInRealTime)
        let (text, finishedAt) = try await received
        return Transcription(text: text, latencySeconds: (finishedAt - endedAt).seconds)
    }

    /// 接続の直後に送る設定メッセージ。API キーはここに書かず、接続時のヘッダーで渡す
    static func startMessage(_ settings: SonioxSettings) throws -> String {
        let message = StartMessage(
            model: settings.model,
            audioFormat: "pcm_s16le",
            sampleRate: Int(AudioFile.sampleRate),
            numChannels: 1,
            languageHints: settings.languageHints,
            context: settings.terms.isEmpty ? nil : .init(terms: settings.terms),
            clientReferenceId: settings.clientReferenceID
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return String(decoding: try encoder.encode(message), as: UTF8.self)
    }

    static func sendAudio(_ samples: [Float], over task: URLSessionWebSocketTask, paced: Bool) async throws -> ContinuousClock.Instant {
        let chunks = stride(from: 0, to: samples.count, by: chunkSamples).map {
            Array(samples[$0..<min($0 + chunkSamples, samples.count)])
        }
        for chunk in chunks {
            try await task.send(.data(AudioFile.pcm16LittleEndian(chunk)))
            if paced {
                try await Task.sleep(for: .milliseconds(120))
            }
        }
        let endedAt = ContinuousClock.now
        try await task.send(.string(""))
        return endedAt
    }

    /// 確定したトークン(is_final)だけを連結する。確定トークンは一度だけ届く
    static func receiveUntilFinished(_ task: URLSessionWebSocketTask) async throws -> (String, ContinuousClock.Instant) {
        var finalText = ""
        while true {
            let response = try decode(try await task.receive())
            if let code = response.errorCode {
                throw SonioxError.server(code: code, type: response.errorType ?? "", message: response.errorMessage ?? "")
            }
            finalText += finalTokens(of: response)
            if response.finished == true {
                return (finalText, ContinuousClock.now)
            }
        }
    }

    static func decode(_ message: URLSessionWebSocketTask.Message) throws -> Response {
        let data: Data
        switch message {
        case let .string(text): data = Data(text.utf8)
        case let .data(bytes): data = bytes
        @unknown default: throw SonioxError.unexpectedMessage
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Response.self, from: data)
    }

    static func finalTokens(of response: Response) -> String {
        (response.tokens ?? []).filter(\.isFinal).map(\.text).joined()
    }

    struct StartMessage: Encodable {
        let model: String
        let audioFormat: String
        let sampleRate: Int
        let numChannels: Int
        let languageHints: [String]
        let context: Context?
        let clientReferenceId: String?

        struct Context: Encodable {
            let terms: [String]
        }
    }

    struct Response: Decodable {
        let tokens: [Token]?
        let finished: Bool?
        let errorCode: Int?
        let errorType: String?
        let errorMessage: String?

        struct Token: Decodable {
            let text: String
            let isFinal: Bool
        }
    }
}
