import Foundation
import TsuzuriCore
import TsuzuriEngines
@preconcurrency import WhisperKit

enum WhisperKitEngineError: Error, CustomStringConvertible {
    case modelNotDownloaded(String)

    var description: String {
        switch self {
        case let .modelNotDownloaded(model):
            "WhisperKit のモデル \(model) がまだありません(large-v3-v20240930_626MB なら約626MB)。--allow-download を付けると ~/Library/Caches/Tsuzuri/models に取得します"
        }
    }
}

/// 評価用の WhisperKit。段階0で Mac 内の既定に選ばれたら TsuzuriEngines へ移す
struct WhisperKitEngine {
    let pipe: WhisperKit
    let model: String

    static func load(model: String, allowDownload: Bool) async throws -> WhisperKitEngine {
        let cache = try ModelCache.directory()
        guard allowDownload || isDownloaded(model: model, in: cache) else {
            throw WhisperKitEngineError.modelNotDownloaded(model)
        }
        let config = WhisperKitConfig(
            model: model,
            downloadBase: cache,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: true
        )
        return WhisperKitEngine(pipe: try await WhisperKit(config), model: model)
    }

    /// 取得済みのモデルのフォルダ(名前の末尾がモデル名)があるか
    static func isDownloaded(model: String, in cache: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(at: cache, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return false
        }
        return enumerator.contains { ($0 as? URL)?.lastPathComponent.hasSuffix(model) == true }
    }

    func transcribe(samples: [Float], terms: [String]) async throws -> Transcription {
        let options = DecodingOptions(
            language: "ja",
            temperature: 0,
            usePrefillPrompt: true,
            detectLanguage: false,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            promptTokens: promptTokens(for: terms)
        )
        let startedAt = ContinuousClock.now
        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        return Transcription(
            text: results.map(\.text).joined(),
            latencySeconds: (ContinuousClock.now - startedAt).seconds
        )
    }

    /// 語のヒントを、Whisper の前置きの文(プロンプト)にする。約200トークンに収まる語まで入れる
    func promptTokens(for terms: [String]) -> [Int]? {
        guard !terms.isEmpty, let tokenizer = pipe.tokenizer else { return nil }
        let limit = 200
        let prompt = terms.reduce("") { accumulated, term in
            let next = accumulated.isEmpty ? term : accumulated + "、" + term
            return tokenizer.encode(text: " " + next).count <= limit ? next : accumulated
        }
        return tokenizer.encode(text: " " + prompt).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
    }
}
