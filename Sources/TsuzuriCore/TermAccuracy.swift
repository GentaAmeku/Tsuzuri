import Foundation

/// 用語正答率。辞書の語が、正しい表記(大文字小文字まで)で出たかを数える
public enum TermAccuracy {
    /// 全角半角をそろえ、空白を除く。大文字小文字はそろえない(Github と GitHub は別の表記)
    public static func normalize(_ text: String) -> [Character] {
        Array(text.precomposedStringWithCompatibilityMapping.filter { !$0.isWhitespace })
    }

    /// 語が何回出たか。長い語から先に当て、重なった分は数えない
    /// (「Claude Code」の中の「Claude」は、Claude としては数えない)
    public static func occurrences(of terms: [String], in text: String) -> [String: Int] {
        positions(of: terms, in: normalize(text)).reduce(into: [:]) { $0[$1.term, default: 0] += 1 }
    }

    /// 語が出た位置(そろえた文字の列での範囲)。数え方は `occurrences` と同じ
    public static func positions(of terms: [String], in characters: [Character]) -> [(term: String, range: Range<Int>)] {
        let candidates = terms
            .map { (term: $0, key: normalize($0)) }
            .filter { !$0.key.isEmpty }
            .sorted { $0.key.count > $1.key.count }
        var found: [(term: String, range: Range<Int>)] = []
        var index = 0
        while index < characters.count {
            if let match = candidates.first(where: { starts(characters, at: index, with: $0.key) }) {
                found.append((match.term, index..<(index + match.key.count)))
                index += match.key.count
            } else {
                index += 1
            }
        }
        return found
    }

    public static func measure(reference: String, hypothesis: String, terms: [String]) -> TermCount {
        let expected = occurrences(of: terms, in: reference)
        let found = occurrences(of: terms, in: hypothesis)
        return TermCount(
            hits: expected.reduce(0) { $0 + min($1.value, found[$1.key, default: 0]) },
            total: expected.values.reduce(0, +),
            missed: expected.filter { found[$0.key, default: 0] < $0.value }.map(\.key).sorted()
        )
    }

    static func starts(_ characters: [Character], at index: Int, with key: [Character]) -> Bool {
        index + key.count <= characters.count
            && characters[index..<(index + key.count)].elementsEqual(key)
    }
}

/// 正しく出た語の数と、正解の文に入っていた語の数
public struct TermCount: Sendable, Equatable {
    public let hits: Int
    public let total: Int
    public let missed: [String]

    public init(hits: Int, total: Int, missed: [String]) {
        self.hits = hits
        self.total = total
        self.missed = missed
    }

    public static let zero = TermCount(hits: 0, total: 0, missed: [])

    /// 対象の語が1つも無いときは 1(取りこぼしが無い)とする
    public var rate: Double {
        total == 0 ? 1 : Double(hits) / Double(total)
    }

    public static func + (lhs: TermCount, rhs: TermCount) -> TermCount {
        TermCount(
            hits: lhs.hits + rhs.hits,
            total: lhs.total + rhs.total,
            missed: lhs.missed + rhs.missed
        )
    }
}
