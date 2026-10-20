import Foundation
import Observation
import os
import TsuzuriCore
import TsuzuriEngines

/// Mac 内の認識(WhisperKit)。Soniox が失敗したときの予備と、「Mac 内だけ」の切り替え先に使う。
/// 読み込みに数秒かかるので、起動したら裏で読み込んでおく。モデルは取得しない(段階0で取得済み)
@Observable
final class LocalRecognizer {
    enum State: Equatable {
        case notLoaded
        case loading
        case ready
        case unavailable(String)
    }

    private(set) var state: State = .notLoaded
    @ObservationIgnored private static let logger = Logger(subsystem: "work.ameku.Tsuzuri", category: "local")
    @ObservationIgnored private var loading: Task<WhisperKitEngine?, Never>?

    var isAvailable: Bool {
        if case .unavailable = state { return false }
        return true
    }

    /// 裏で読み込みを始める。何度呼んでもよい
    func prewarm() {
        guard loading == nil else { return }
        state = .loading
        loading = Task {
            do {
                let engine = try await Task.detached(priority: .utility) {
                    try await WhisperKitEngine.load(model: WhisperKitEngine.defaultModel, allowDownload: false)
                }.value
                state = .ready
                Self.logger.info("Mac 内の認識を読み込みました")
                return engine
            } catch {
                state = .unavailable("\(error)")
                Self.logger.error("Mac 内の認識を読み込めません: \(String(describing: error), privacy: .public)")
                return nil
            }
        }
    }

    /// 録音を文字にする。読み込みが終わっていなければ待つ
    func transcribe(_ samples: [Float], terms: [String]) async throws -> String {
        prewarm()
        guard let engine = await loading?.value else {
            throw LocalRecognizerError.unavailable(stateDescription)
        }
        let limited = Array(terms.prefix(WhisperKitEngine.hintLimit))
        return try await Task.detached(priority: .userInitiated) {
            try await engine.transcribe(samples: samples, terms: limited).text
        }.value
    }

    var stateDescription: String {
        switch state {
        case .notLoaded: "まだ読み込んでいません"
        case .loading: "読み込んでいます"
        case .ready: "使えます(WhisperKit)"
        case let .unavailable(reason): "使えません(\(reason))"
        }
    }
}

enum LocalRecognizerError: Error, CustomStringConvertible {
    case unavailable(String)

    var description: String {
        switch self {
        case let .unavailable(reason): "Mac 内の認識が\(reason)"
        }
    }
}
