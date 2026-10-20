import AppKit
import Observation
import TsuzuriCore

/// 辞書(`dictionary.json`)と使われた回数(`usage.json`)。辞書は本人が手で直すので、
/// 使う直前に更新日時を見て読み直す。壊れていたら、最後に読めた中身を使い続けて知らせる
@Observable
final class DictionaryStore {
    private(set) var dictionary = DictionaryFile(version: 1, entries: [], fillers: [])
    /// 読めなかったときの理由
    private(set) var loadError: String?

    @ObservationIgnored let dictionaryURL: URL
    @ObservationIgnored private let usageURL: URL
    @ObservationIgnored private var usage: [String: TermUsage] = [:]
    @ObservationIgnored private var loadedModificationDate: Date?

    init(directory: URL) {
        dictionaryURL = directory.appending(path: "dictionary.json")
        usageURL = directory.appending(path: "usage.json")
        seedIfNeeded()
        reloadIfChanged()
        if let data = try? Data(contentsOf: usageURL), let file = try? Self.decoder.decode(UsageFile.self, from: data) {
            usage = file.terms
        }
    }

    /// 初めて起動したときは、アプリに同梱した最初の辞書(評価用の辞書と同じ語)を置く
    private func seedIfNeeded() {
        guard !FileManager.default.fileExists(atPath: dictionaryURL.path),
              let starter = Bundle.main.url(forResource: "starter-dictionary", withExtension: "json") else { return }
        try? FileManager.default.copyItem(at: starter, to: dictionaryURL)
    }

    /// 更新日時が変わっていたら読み直す
    func reloadIfChanged() {
        let modified = (try? dictionaryURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard modified != loadedModificationDate else { return }
        loadedModificationDate = modified
        do {
            dictionary = try JSONDecoder().decode(DictionaryFile.self, from: Data(contentsOf: dictionaryURL))
            loadError = nil
        } catch {
            loadError = "辞書のファイルを読めません(\(error.localizedDescription))。直すまで、前に読めた中身を使います"
        }
    }

    /// 認識に渡す語(上限まで。Mac 内の認識は、さらに上位40語に絞る)
    func hintTerms(now: Date = Date()) -> [String] {
        HintSelector.select(entries: dictionary.entries, usage: usage, now: now)
    }

    func shaper(waObunSpacing: Bool) -> TextShaper {
        TextShaper(dictionary: dictionary, waObunSpacing: waObunSpacing)
    }

    /// 整えたあとの文字に出た辞書の語を、使われた回数として数える
    func recordUsage(in text: String, at date: Date = Date()) {
        let counts = HintSelector.occurrences(of: dictionary.entries.map(\.surface), in: text)
        guard !counts.isEmpty else { return }
        for (surface, count) in counts {
            usage[surface, default: TermUsage()].record(count, at: date)
        }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(UsageFile(version: 1, terms: usage)).write(to: usageURL, options: .atomic)
        } catch {
            NSLog("Tsuzuri: 使われた回数を書けません: \(error)")
        }
    }

    func openInEditor() {
        NSWorkspace.shared.open(dictionaryURL)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// `usage.json` の形
struct UsageFile: Codable {
    var version: Int
    var terms: [String: TermUsage]
}
