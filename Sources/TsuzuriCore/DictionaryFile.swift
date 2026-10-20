/// 辞書(`dictionary.json`)の形。設計書の「辞書の形と使い方」に合わせる
public struct DictionaryFile: Codable, Sendable, Equatable {
    public let version: Int
    public let entries: [DictionaryEntry]
    public let fillers: [String]

    public init(version: Int, entries: [DictionaryEntry], fillers: [String]) {
        self.version = version
        self.entries = entries
        self.fillers = fillers
    }

    /// 認識へのヒントに渡す語(`hint` が true のもの)
    public var hintTerms: [String] {
        entries.filter(\.hint).map(\.surface)
    }

    /// 正しい表記の一覧(用語正答率の対象)
    public var surfaces: [String] {
        entries.map(\.surface)
    }
}

public struct DictionaryEntry: Codable, Sendable, Hashable {
    public let surface: String
    public let from: [String]
    public let hint: Bool
    public let pinned: Bool
    public let source: Source

    public enum Source: String, Codable, Sendable {
        case manual
        case auto
    }

    public init(surface: String, from: [String], hint: Bool, pinned: Bool, source: Source) {
        self.surface = surface
        self.from = from
        self.hint = hint
        self.pinned = pinned
        self.source = source
    }
}
