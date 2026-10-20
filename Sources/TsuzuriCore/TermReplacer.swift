import Foundation

/// 辞書の置き換え元(`from`)を正しい表記(`surface`)に直す。日本語は語の間に空白が無いので、
/// 置き換える境目は置き換え元の字の種類で決める(設計書「置き換えの境目は、字の種類で決める」)
///
/// - カタカナだけ: 前後の字がカタカナや長音でないときだけ。中黒「・」や空白で区切られていても当てる
/// - 英字: 前後が英数字でないときだけ。大文字小文字は区別しない
/// - 英字とカタカナが混ざったもの(B テスト・グラフ QL): 端の字の種類ごとに、上の2つの境目で当てる。字の間の空白・中黒は問わない
/// - 漢字・ひらがなを含むもの: 置き換えに使わない(同音異義語はヒントだけに使う)
public struct TermReplacer: Sendable {
    struct Rule: @unchecked Sendable {
        let pattern: NSRegularExpression
        let surface: String
    }

    let rules: [Rule]

    public init(entries: [DictionaryEntry]) {
        rules = entries.flatMap { entry in
            entry.from.compactMap { from in Self.pattern(for: from).map { Rule(pattern: $0, surface: entry.surface) } }
        }
    }

    public enum FromKind: Equatable {
        case katakana
        case latin
        /// 英字(数字を含む)とカタカナが混ざったもの
        case mixed
        /// 置き換えに使わない
        case unsupported
    }

    public static func kind(of from: String) -> FromKind {
        let letters = from.filter { $0 != " " && $0 != "・" }
        guard !letters.isEmpty else { return .unsupported }
        if letters.allSatisfy(\.isKatakana) { return .katakana }
        if from.allSatisfy({ $0.isASCII }) && letters.contains(where: \.isASCIILetter) { return .latin }
        if letters.allSatisfy({ $0.isKatakana || $0.isASCIIAlphanumeric }),
           letters.contains(where: \.isKatakana), letters.contains(where: \.isASCIILetter) {
            return .mixed
        }
        return .unsupported
    }

    static func pattern(for from: String) -> NSRegularExpression? {
        let letters = from.filter { $0 != " " && $0 != "・" }
        let source: String
        switch kind(of: from) {
        case .katakana:
            // 字の間に「・」や空白が入っていても当てる(Soniox は「クロード・コード」と出すことがある)
            let body = letters.map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "[・ ]?")
            source = "(?<![\\p{Katakana}ー])" + body + "(?![\\p{Katakana}ー])"
        case .latin:
            let body = from.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: " ?")
            source = "(?<![A-Za-z0-9])" + body + "(?![A-Za-z0-9])"
        case .mixed:
            let body = letters.map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "[・ ]?")
            source = boundary(before: letters.first!) + body + boundary(after: letters.last!)
        case .unsupported:
            return nil
        }
        return try? NSRegularExpression(pattern: source, options: [.caseInsensitive])
    }

    /// 端の字の種類で決める境目。カタカナならカタカナと長音、英数字なら英数字が隣にないこと
    static func boundary(before first: Character) -> String {
        first.isKatakana ? "(?<![\\p{Katakana}ー])" : "(?<![A-Za-z0-9])"
    }

    static func boundary(after last: Character) -> String {
        last.isKatakana ? "(?![\\p{Katakana}ー])" : "(?![A-Za-z0-9])"
    }

    /// 重なる当たりは長いものを先に採り、1回で置き換える(置き換えた後の文字を、別の語がもう一度直さないように)
    public func replace(_ text: String) -> String {
        let whole = NSRange(text.startIndex..., in: text)
        var matches: [(range: NSRange, surface: String)] = []
        for rule in rules {
            for match in rule.pattern.matches(in: text, range: whole) {
                matches.append((match.range, rule.surface))
            }
        }
        var chosen: [(range: NSRange, surface: String)] = []
        for match in matches.sorted(by: { ($0.range.length, -$0.range.location) > ($1.range.length, -$1.range.location) })
        where !chosen.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }) {
            chosen.append(match)
        }
        let result = NSMutableString(string: text)
        for match in chosen.sorted(by: { $0.range.location > $1.range.location }) {
            result.replaceCharacters(in: match.range, with: match.surface)
        }
        return result as String
    }
}
