import Foundation
import TsuzuriCore
import TsuzuriEngines

/// 録音のある文を順に認識させ、1文ずつの結果にする。失敗した文は理由を残して次へ進む
public enum EvalRunner {
    public static func run(
        sentences: [EvalSentence],
        paths: EvalPaths,
        mic: String,
        transcribe: (EvalSentence, URL) async throws -> Transcription,
        report: (String) -> Void = { print($0) }
    ) async -> [EvalItem] {
        let targets = sentences.filter { FileManager.default.fileExists(atPath: paths.recording(mic: mic, id: $0.id).path) }
        var items: [EvalItem] = []
        for (index, sentence) in targets.enumerated() {
            let url = paths.recording(mic: mic, id: sentence.id)
            let seconds = (try? AudioFile.duration(of: url)) ?? 0
            do {
                let transcription = try await transcribe(sentence, url)
                items.append(EvalItem(id: sentence.id, hypothesis: transcription.text, audioSeconds: seconds, latencySeconds: transcription.latencySeconds, error: nil))
                report("[\(index + 1)/\(targets.count)] \(sentence.id) \(String(format: "%.2f", transcription.latencySeconds))秒: \(transcription.text)")
            } catch {
                items.append(EvalItem(id: sentence.id, hypothesis: nil, audioSeconds: seconds, latencySeconds: nil, error: String(describing: error)))
                report("[\(index + 1)/\(targets.count)] \(sentence.id) 失敗: \(error)")
            }
        }
        return items
    }
}
