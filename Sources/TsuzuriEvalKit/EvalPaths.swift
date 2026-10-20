import Foundation
import TsuzuriCore

/// 評価のファイルの置き場所。録音と結果は git に入れない(.gitignore)
public struct EvalPaths: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// 今いるフォルダからの相対パス(既定は eval)で作る
    public init(evalDirectory: String) {
        self.root = URL(filePath: evalDirectory, directoryHint: .isDirectory, relativeTo: URL.currentDirectory()).standardizedFileURL
    }

    public var sentences: URL { root.appending(path: "sentences.json") }
    public var dictionary: URL { root.appending(path: "dictionary.json") }
    public var results: URL { root.appending(path: "results", directoryHint: .isDirectory) }

    public func recordings(mic: String) -> URL {
        root.appending(path: "recordings/\(mic)", directoryHint: .isDirectory)
    }

    public func recording(mic: String, id: String) -> URL {
        recordings(mic: mic).appending(path: "\(id).wav")
    }

    public func result(engine: String, hints: HintMode, mic: String) -> URL {
        results.appending(path: "\(engine)-\(hints.rawValue)-\(mic).json")
    }
}
