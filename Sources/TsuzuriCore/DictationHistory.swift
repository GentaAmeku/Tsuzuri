import Foundation

/// 履歴の1件(設計書: 時刻・使ったアプリ・認識・整える前と後の文字)。段階1は整える規則が無いので、前と後は同じ
public struct HistoryEntry: Sendable, Equatable, Codable {
    public var date: Date
    /// 貼り付けた先のアプリ(バンドル ID)
    public var app: String?
    public var engine: String
    /// 認識が返した文字
    public var raw: String
    /// 整えたあとの文字(貼り付けた文字)
    public var text: String
    /// 残した音声のファイル名
    public var audio: String?
    /// 失敗したときの理由
    public var error: String?

    public init(date: Date, app: String?, engine: String, raw: String, text: String, audio: String? = nil, error: String? = nil) {
        self.date = date
        self.app = app
        self.engine = engine
        self.raw = raw
        self.text = text
        self.audio = audio
        self.error = error
    }
}

/// 履歴の JSON Lines。直近の決めた件数だけ残す
public enum DictationHistory {
    public static let limit = 100

    public static func decode(_ jsonLines: String) -> [HistoryEntry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // 壊れた行は飛ばす(手で直したときなどに、全体を読めなくしないため)
        return jsonLines.split(whereSeparator: \.isNewline).compactMap {
            try? decoder.decode(HistoryEntry.self, from: Data($0.utf8))
        }
    }

    public static func encode(_ entries: [HistoryEntry]) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try entries.map { String(decoding: try encoder.encode($0), as: UTF8.self) + "\n" }.joined()
    }

    /// 1件足し、古いものから落として `limit` 件以内にする
    public static func appending(_ entry: HistoryEntry, to entries: [HistoryEntry], limit: Int = limit) -> [HistoryEntry] {
        Array((entries + [entry]).suffix(limit))
    }

    /// ⌃⌥⌘V で貼り直す文字(失敗していない最新の文字)
    public static func lastText(in entries: [HistoryEntry]) -> String? {
        entries.last { $0.error == nil && !$0.text.isEmpty }?.text
    }
}

/// 残した音声を消す時期(設計書: 7日だけ残す)
public enum AudioRetention {
    public static let days = 7

    /// 作った日時が期限を過ぎたファイル
    public static func expired<File>(_ files: [(file: File, createdAt: Date)], now: Date, days: Int = days) -> [File] {
        let limit = now.addingTimeInterval(-Double(days) * 24 * 60 * 60)
        return files.filter { $0.createdAt < limit }.map(\.file)
    }
}
