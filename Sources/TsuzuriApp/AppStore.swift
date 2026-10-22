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

    /// Soniox を使わず、Mac 内(WhisperKit)だけで認識するか(メニューの手動の切り替え)
    var localOnly: Bool {
        didSet { UserDefaults.standard.set(localOnly, forKey: Self.localOnlyKey) }
    }

    /// 日本語と英字のあいだに半角スペースを入れるか
    var waObunSpacing: Bool {
        didSet { UserDefaults.standard.set(waObunSpacing, forKey: Self.waObunSpacingKey) }
    }

    /// 録音キーと操作の方式(段階4から設定の窓で変えられる)
    var hotkeySettings: HotkeySettings {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(hotkeySettings), forKey: Self.hotkeySettingsKey) }
    }

    /// 録音中の表示の色
    var hudTheme: HUDTheme {
        didSet { UserDefaults.standard.set(hudTheme.rawValue, forKey: Self.hudThemeKey) }
    }

    /// 月ごとの Soniox の使用量(`soniox-usage.json`。費用の表示に使う)
    private(set) var sonioxUsage = SonioxUsageFile()

    @ObservationIgnored let directory: URL
    @ObservationIgnored private let historyURL: URL
    @ObservationIgnored private let audioDirectory: URL
    @ObservationIgnored private let sonioxUsageURL: URL
    private static let keepAudioKey = "keepAudio"
    private static let waObunSpacingKey = "waObunSpacing"
    private static let localOnlyKey = "localOnly"
    private static let hotkeySettingsKey = "hotkeySettings"
    private static let hudThemeKey = "hudTheme"

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appending(path: "Tsuzuri", directoryHint: .isDirectory)
        historyURL = directory.appending(path: "history.jsonl")
        audioDirectory = directory.appending(path: "audio", directoryHint: .isDirectory)
        sonioxUsageURL = directory.appending(path: "soniox-usage.json")
        hotkeySettings = UserDefaults.standard.data(forKey: Self.hotkeySettingsKey)
            .flatMap { try? JSONDecoder().decode(HotkeySettings.self, from: $0) } ?? HotkeySettings()
        hudTheme = UserDefaults.standard.string(forKey: Self.hudThemeKey).flatMap(HUDTheme.init(rawValue:)) ?? .blueWhite
        keepAudio = UserDefaults.standard.object(forKey: Self.keepAudioKey) as? Bool ?? true
        waObunSpacing = UserDefaults.standard.object(forKey: Self.waObunSpacingKey) as? Bool ?? true
        localOnly = UserDefaults.standard.bool(forKey: Self.localOnlyKey)
        try? FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        if let lines = try? String(contentsOf: historyURL, encoding: .utf8) {
            history = DictationHistory.decode(lines)
        }
        if let data = try? Data(contentsOf: sonioxUsageURL), let file = try? JSONDecoder().decode(SonioxUsageFile.self, from: data) {
            sonioxUsage = file
        }
    }

    /// Soniox で1回認識したことを、月ごとの使用量に足す
    func recordSoniox(audioSeconds: Double, hintCharacters: Int) {
        sonioxUsage = sonioxUsage.adding(audioSeconds: audioSeconds, hintCharacters: hintCharacters, at: Date())
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(sonioxUsage).write(to: sonioxUsageURL, options: .atomic)
        } catch {
            NSLog("Tsuzuri: Soniox の使用量を書けません: \(error)")
        }
    }

    /// メニューに出す、今月の Soniox の使用時間と推定の代金
    var sonioxCostLine: String {
        SonioxPricing().menuLine(sonioxUsage.month(of: Date()))
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

    func audioURL(_ name: String) -> URL {
        audioDirectory.appending(path: name)
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
