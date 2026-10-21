import Foundation

/// 辞書の候補のファイル(`candidates.json`)の形。アプリだけが書く
public struct CandidatesFile: Codable, Sendable, Equatable {
    public var version: Int
    public var items: [StoredCandidate]
    /// 本人が捨てた組。二度出さない
    public var discarded: [DiscardedPair]
    /// 本人が辞書に入れた組。ヒントだけの語は文に残り続けるので、同じ組を二度出さない
    public var inserted: [DiscardedPair]

    public init(version: Int = 1, items: [StoredCandidate] = [], discarded: [DiscardedPair] = [], inserted: [DiscardedPair] = []) {
        self.version = version
        self.items = items
        self.discarded = discarded
        self.inserted = inserted
    }

    /// 洗い出しで二度出さない組
    public var settled: Set<DiscardedPair> {
        Set(discarded).union(inserted)
    }
}

/// 貯めた候補。同じ「認識した語 → 表記」の組は1つにまとめ、出た回数を数える
public struct StoredCandidate: Codable, Sendable, Hashable, Identifiable {
    public var heard: String
    public var surfaces: [String]
    /// 最後に出た文の前後20字
    public var before: String
    public var after: String
    /// 最後に貼った先のアプリ(バンドル ID)
    public var app: String?
    public var count: Int
    public var lastSeen: Date

    public init(heard: String, surfaces: [String], before: String, after: String, app: String?, count: Int, lastSeen: Date) {
        self.heard = heard
        self.surfaces = surfaces
        self.before = before
        self.after = after
        self.app = app
        self.count = count
        self.lastSeen = lastSeen
    }

    public var id: DiscardedPair { DiscardedPair(heard: heard, surface: surfaces[0]) }
}

/// 候補を貯める・捨てる・入れたことを残す(設計書「選ぶ: 候補の窓で、入れるか捨てるかを決める」)
public enum CandidateBook {
    /// 洗い出しの結果を貯める。同じ組は回数を足し、前後の文と貼った先を最後のものにする。捨てた組・入れた組は足さない
    public static func merging(_ candidates: [SuggestionCandidate], app: String?, at date: Date, into file: CandidatesFile) -> CandidatesFile {
        var file = file
        let settled = file.settled
        for candidate in candidates {
            let key = DiscardedPair(heard: candidate.heard, surface: candidate.surfaces[0])
            guard !settled.contains(key) else { continue }
            if let index = file.items.firstIndex(where: { $0.id == key }) {
                file.items[index].count += 1
                file.items[index].before = candidate.before
                file.items[index].after = candidate.after
                file.items[index].app = app
                file.items[index].lastSeen = date
            } else {
                file.items.append(StoredCandidate(
                    heard: candidate.heard, surfaces: candidate.surfaces,
                    before: candidate.before, after: candidate.after,
                    app: app, count: 1, lastSeen: date
                ))
            }
        }
        return file
    }

    /// 候補の窓に並べる順。出た回数の多い順、同じなら新しい順
    public static func ordered(_ items: [StoredCandidate]) -> [StoredCandidate] {
        items.sorted { ($0.count, $0.lastSeen) > ($1.count, $1.lastSeen) }
    }

    /// 捨てる。窓に出ていた組(1つ目の表記の案)を、二度出さない組として残す
    public static func discarding(_ id: DiscardedPair, from file: CandidatesFile) -> CandidatesFile {
        var file = file
        file.items.removeAll { $0.id == id }
        if !file.discarded.contains(id) { file.discarded.append(id) }
        return file
    }

    /// 辞書に入れたあと。候補から外し、入れた組として残す。本人が表記を直したら、直した組も残す
    public static func inserting(_ id: DiscardedPair, surface: String, from file: CandidatesFile) -> CandidatesFile {
        var file = file
        guard let item = file.items.first(where: { $0.id == id }) else { return file }
        file.items.removeAll { $0.id == id }
        for pair in [id, DiscardedPair(heard: item.heard, surface: surface)] where !file.inserted.contains(pair) {
            file.inserted.append(pair)
        }
        return file
    }

    /// 捨てた組を候補の窓から戻す(次に出たら、また候補になる)
    public static func restoring(_ id: DiscardedPair, from file: CandidatesFile) -> CandidatesFile {
        var file = file
        file.discarded.removeAll { $0 == id }
        return file
    }
}

/// 候補を辞書に入れる(設計書「選ぶ」の表)
public enum DictionaryInsertion {
    /// 入れたあとの辞書の語。何も足さないとき(ヒントだけで、表記がすでに辞書にある)は nil
    public static func insert(heard: String, surface: String, mode: InsertionMode, into entries: [DictionaryEntry]) -> [DictionaryEntry]? {
        let surface = surface.trimmingCharacters(in: .whitespaces)
        guard !surface.isEmpty else { return nil }
        // 置き換え元にできない字の種類(漢字・かな)は、選ばれてもヒントだけにする
        let replaces = mode == .replace && TermReplacer.kind(of: heard) != .unsupported
        var entries = entries
        if let index = entries.firstIndex(where: { $0.surface == surface }) {
            guard replaces else { return nil }
            let entry = entries[index]
            guard !entry.from.map(CandidateFilter.compact).contains(CandidateFilter.compact(heard)) else { return nil }
            entries[index] = DictionaryEntry(surface: entry.surface, from: entry.from + [heard], hint: entry.hint, pinned: entry.pinned, source: entry.source)
            return entries
        }
        entries.append(DictionaryEntry(surface: surface, from: replaces ? [heard] : [], hint: true, pinned: false, source: .auto))
        return entries
    }
}
