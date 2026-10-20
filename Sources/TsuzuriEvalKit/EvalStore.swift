import Foundation
import TsuzuriCore

/// 評価セット・辞書・結果の JSON を読み書きする
public enum EvalStore {
    public static func sentences(_ paths: EvalPaths) throws -> [EvalSentence] {
        try decoder.decode(EvalSentenceSet.self, from: Data(contentsOf: paths.sentences)).sentences
    }

    public static func dictionary(_ paths: EvalPaths) throws -> DictionaryFile {
        try decoder.decode(DictionaryFile.self, from: Data(contentsOf: paths.dictionary))
    }

    public static func write(_ run: EvalRun, _ paths: EvalPaths) throws -> URL {
        let url = paths.result(engine: run.engine, hints: run.hints, mic: run.mic)
        try FileManager.default.createDirectory(at: paths.results, withIntermediateDirectories: true)
        try encoder.encode(run).write(to: url, options: .atomic)
        return url
    }

    public static func runs(_ paths: EvalPaths) throws -> [EvalRun] {
        guard FileManager.default.fileExists(atPath: paths.results.path) else { return [] }
        return try FileManager.default
            .contentsOfDirectory(at: paths.results, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { try decoder.decode(EvalRun.self, from: Data(contentsOf: $0)) }
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
