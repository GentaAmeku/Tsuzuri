import AppKit
import Observation
import TsuzuriCore
import TsuzuriEngines

/// アプリが残すもの。~/Library/Application Support/Tsuzuri/ に履歴(JSON Lines)と7日分の音声を置く
@Observable
final class AppStore {
    private(set) var history: [HistoryEntry] = []
    /// 音声を残すか(直前の録音の認識し直しと評価に使う)
    var keepAudio: Bool {
        didSet { UserDefaults.standard.set(keepAudio, forKey: Self.keepAudioKey) }
    }

    /// 日本語と英字のあいだに半角スペースを入れるか
    var waObunSpacing: Bool {
        didSet { UserDefaults.standard.set(waObunSpacing, forKey: Self.waObunSpacingKey) }
    }

    @ObservationIgnored let directory: URL
    @ObservationIgnored private let historyURL: URL
    @ObservationIgnored private let audioDirectory: URL
    private static let keepAudioKey = "keepAudio"
    private static let waObunSpacingKey = "waObunSpacing"

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appending(path: "Tsuzuri", directoryHint: .isDirectory)
        historyURL = directory.appending(path: "history.jsonl")
        audioDirectory = directory.appending(path: "audio", directoryHint: .isDirectory)
        keepAudio = UserDefaults.standard.object(forKey: Self.keepAudioKey) as? Bool ?? true
        waObunSpacing = UserDefaults.standard.object(forKey: Self.waObunSpacingKey) as? Bool ?? true
        try? FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        if let lines = try? String(contentsOf: historyURL, encoding: .utf8) {
            history = DictationHistory.decode(lines)
        }
    }

    func record(_ entry: HistoryEntry) {
        history = DictationHistory.appending(entry, to: history)
        do {
            try DictationHistory.encode(history).write(to: historyURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Tsuzuri: 履歴を書けません: \(error)")
        }
    }

    /// 音声を WAV で残し、ファイル名を返す。残さない設定や音声が無いときは nil
    func saveAudio(_ samples: [Float], startedAt: Date) -> String? {
        guard keepAudio, !samples.isEmpty else { return nil }
        let name = Self.fileName(for: startedAt)
        do {
            try AudioFile.writeWAV(samples: samples, to: audioDirectory.appending(path: name))
            return name
        } catch {
            NSLog("Tsuzuri: 音声を書けません: \(error)")
            return nil
        }
    }

    /// 7日を過ぎた音声を消す
    func purgeOldAudio() {
        let files = (try? FileManager.default.contentsOfDirectory(at: audioDirectory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        let dated = files.compactMap { url -> (file: URL, createdAt: Date)? in
            guard let date = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate else { return nil }
            return (url, date)
        }
        for url in AudioRetention.expired(dated, now: Date()) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([historyURL])
    }

    static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: date) + ".wav"
    }
}
