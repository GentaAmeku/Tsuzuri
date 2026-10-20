import Foundation
import TsuzuriCore
@preconcurrency import WhisperKit

public enum WhisperKitEngineError: Error, CustomStringConvertible {
    case modelNotDownloaded(String)

    public var description: String {
        switch self {
        case let .modelNotDownloaded(model):
            "WhisperKit のモデル \(model) がまだありません(large-v3-v20240930_626MB なら約626MB)。--allow-download を付けると ~/Library/Caches/Tsuzuri/models に取得します"
        }
    }
}

/// Mac 内の認識(段階0で既定に選んだ WhisperKit)。評価の CLI とアプリが使う。
/// モデルは ~/Library/Caches/Tsuzuri/models に置き、`allowDownload` が無ければ取得しない
public struct WhisperKitEngine: @unchecked Sendable {
    public static let defaultModel = "large-v3-v20240930_626MB"
    /// Whisper の前置きの文に入れる語の数(設計書「語のヒントは、費用と上限があるので上位から選ぶ」)
    public static let hintLimit = 40

    let pipe: WhisperKit
    public let model: String

    public static func load(model: String, allowDownload: Bool) async throws -> WhisperKitEngine {
        let cache = try ModelCache.directory()
        // 手元にあれば、その場所を渡して取得を切る(取得を許すと、手元にあっても配布元へ確かめに行くため)
        if let folder = localFolder(model: model, in: cache) {
            let config = WhisperKitConfig(
                model: model,
                downloadBase: cache,
                modelFolder: folder.path,
                tokenizerFolder: cache,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: false
            )
            return WhisperKitEngine(pipe: try await WhisperKit(config), model: model)
        }
        guard allowDownload else {
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

    /// 取得済みのモデルのフォルダ(名前の末尾がモデル名)
    public static func localFolder(model: String, in cache: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: cache, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return nil
        }
        return enumerator.lazy.compactMap { $0 as? URL }.first { $0.lastPathComponent.hasSuffix(model) }
    }

    public func transcribe(samples: [Float], terms: [String]) async throws -> Transcription {
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
