import Foundation

/// 辞書の語に読みが近い語を、その辞書の語への直しとして挙げる(設計書「辞書の語に読みが近い語も挙げる」)。
/// 本人の言い間違い・聞き違いは辞書にあるドメインの語に多いので、Apple Foundation Models を使わない規則で拾う
public enum NearDictionary {
    /// 挙げる読みの近さの下限(初期値)
    public static let minimumSimilarity = 0.7
    /// これより短い読みの語は比べない
    public static let minimumReadingLength = 4

    /// `marked` は拾う段で印を付けた語(漢字・かなの語は含まない)
    public static func suspects(marked: [String], entries: [DictionaryEntry]) -> [Suspect] {
        let targets = entries
            .filter { $0.surface.contains(where: { $0.isASCIILetter || $0.isKatakana }) }
            .map { entry in (surface: entry.surface, keys: ([entry.surface] + entry.from).map(key)) }
        var result: [Suspect] = []
        for heard in marked {
            let heardKey = key(heard)
            guard heardKey.count >= minimumReadingLength else { continue }
            let best = targets
                .filter { !$0.keys.contains(heardKey) }
                .map { target in (surface: target.surface, similarity: target.keys.map { similarity(heardKey, $0) }.max() ?? 0) }
                .max { $0.similarity < $1.similarity }
            if let best, best.similarity >= minimumSimilarity {
                result.append(Suspect(heard: heard, surfaces: [best.surface]))
            }
        }
        return result
    }

    /// 比べるための読み。ローマ字にし、空白と中黒を除いた小文字
    static func key(_ text: String) -> String {
        Reading.romaji(CandidateFilter.compact(text)).lowercased()
    }

    static func similarity(_ a: String, _ b: String) -> Double {
        let length = max(a.count, b.count)
        guard length > 0 else { return 1 }
        return 1 - Double(CharacterErrorRate.editDistance(Array(a), Array(b))) / Double(length)
    }
}

/// 表記の案が、ふつうの英単語だけでできているか(2026-10-22。日本語の語を英語に訳しただけの案を捨てるため)。
/// 英単語かどうかは外から渡す(アプリと評価では macOS の綴りの辞書を使う)
public enum PlainEnglish {
    /// 1語の英単語(error・Preview)と、小文字だけの複数語(server component)を、ふつうの英単語とみなす。
    /// 途中に大文字がある名前(TanStack)・大文字の略語(CI)・記号を含む名前(Next.js)・各語の頭が大文字の複数語(Claude Code)は名前とみなす
    public static func isPlain(_ surface: String, isEnglishWord: (String) -> Bool) -> Bool {
        let words = surface.split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init)
        guard !words.isEmpty, words.allSatisfy({ $0.allSatisfy(\.isASCIILetter) }) else { return false }
        let simpleCase = words.allSatisfy { word in
            word == word.lowercased() || (word.first!.isUppercase && word.dropFirst() == word.dropFirst().lowercased() && word.count > 1)
        }
        guard simpleCase else { return false }
        if words.count > 1, words.allSatisfy({ $0.first!.isUppercase }) { return false }
        return words.allSatisfy(isEnglishWord)
    }
}
