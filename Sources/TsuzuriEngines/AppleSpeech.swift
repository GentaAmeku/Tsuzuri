@preconcurrency import AVFoundation
import Foundation
import Speech
import TsuzuriCore

public enum AppleSpeechError: Error, CustomStringConvertible {
    case localeUnsupported(String)
    case assetsNotInstalled

    public var description: String {
        switch self {
        case let .localeUnsupported(identifier):
            "Apple の認識は \(identifier) に対応していません"
        case .assetsNotInstalled:
            "Apple の日本語の認識モデルが入っていません。--allow-download を付けると、システムが取得します"
        }
    }
}

/// macOS 26 の SpeechAnalyzer。DictationTranscriber は語のヒント(contextualStrings)を使え、
/// SpeechTranscriber は使えない(Apple の技術者の回答による)
public enum AppleSpeech {
    public enum Mode: String, Sendable, CaseIterable {
        case dictation
        case speech
    }

    public static let locale = Locale(identifier: "ja-JP")

    public static func transcribe(fileURL: URL, mode: Mode, terms: [String], allowAssetDownload: Bool) async throws -> Transcription {
        switch mode {
        case .dictation:
            guard let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) else {
                throw AppleSpeechError.localeUnsupported(locale.identifier)
            }
            let transcriber = DictationTranscriber(locale: supported, preset: .longDictation)
            try await ensureAssets(for: [transcriber], allowDownload: allowAssetDownload)
            return try await analyze(fileURL: fileURL, module: transcriber, terms: terms) {
                try await transcriber.results.reduce(into: "") { text, result in
                    if result.isFinal { text += String(result.text.characters) }
                }
            }
        case .speech:
            guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
                throw AppleSpeechError.localeUnsupported(locale.identifier)
            }
            let transcriber = SpeechTranscriber(locale: supported, preset: .transcription)
            try await ensureAssets(for: [transcriber], allowDownload: allowAssetDownload)
            return try await analyze(fileURL: fileURL, module: transcriber, terms: []) {
                try await transcriber.results.reduce(into: "") { text, result in
                    if result.isFinal { text += String(result.text.characters) }
                }
            }
        }
    }

    static func analyze(
        fileURL: URL,
        module: any SpeechModule,
        terms: [String],
        collect: @escaping @Sendable () async throws -> String
    ) async throws -> Transcription {
        let analyzer = SpeechAnalyzer(modules: [module])
        if !terms.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = terms
            try await analyzer.setContext(context)
        }
        let file = try AVAudioFile(forReading: fileURL)
        let startedAt = ContinuousClock.now
        async let text = collect()
        try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        let collected = try await text
        return Transcription(text: collected, latencySeconds: (ContinuousClock.now - startedAt).seconds)
    }

    /// 認識モデルが無ければ、許可されているときだけシステムに取得させる
    static func ensureAssets(for modules: [any SpeechModule], allowDownload: Bool) async throws {
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: modules) else { return }
        guard allowDownload else { throw AppleSpeechError.assetsNotInstalled }
        try await request.downloadAndInstall()
    }
}
