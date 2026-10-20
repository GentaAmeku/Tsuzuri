import Foundation

/// 文字誤り率。全角半角・大文字小文字をそろえ、空白と句読点を除いてから比べる
public enum CharacterErrorRate {
    /// 比べる前にそろえた文字の列
    public static func normalize(_ text: String) -> [Character] {
        Array(
            text.precomposedStringWithCompatibilityMapping
                .lowercased()
                .filter { !isIgnored($0) }
        )
    }

    /// 置換・抜け・余分を1つずつ数える編集距離
    public static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        let lastRow = a.indices.reduce(Array(0...b.count)) { previous, i in
            b.indices.reduce(into: [i + 1]) { row, j in
                let substitution = previous[j] + (a[i] == b[j] ? 0 : 1)
                let deletion = previous[j + 1] + 1
                let insertion = row[j] + 1
                row.append(min(substitution, deletion, insertion))
            }
        }
        return lastRow[b.count]
    }

    public static func measure(reference: String, hypothesis: String) -> ErrorCount {
        let expected = normalize(reference)
        let actual = normalize(hypothesis)
        return ErrorCount(edits: editDistance(expected, actual), length: expected.count)
    }

    /// 空白と句読点(Unicode の一般カテゴリが P のもの)は比べない。長音の「ー」は文字として残る
    static func isIgnored(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { $0.properties.isWhitespace || isPunctuation($0) }
    }

    static func isPunctuation(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation:
            true
        default:
            false
        }
    }
}

/// 誤りの数と、正解の文字数。足し合わせて全体の率を出す(文ごとの率の平均ではない)
public struct ErrorCount: Sendable, Equatable {
    public let edits: Int
    public let length: Int

    public init(edits: Int, length: Int) {
        self.edits = edits
        self.length = length
    }

    public static let zero = ErrorCount(edits: 0, length: 0)

    public var rate: Double {
        length == 0 ? 0 : Double(edits) / Double(length)
    }

    public static func + (lhs: ErrorCount, rhs: ErrorCount) -> ErrorCount {
        ErrorCount(edits: lhs.edits + rhs.edits, length: lhs.length + rhs.length)
    }
}
