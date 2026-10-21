import Foundation

/// Apple Foundation Models が挙げた、誤って認識したらしい語と表記の案(洗い出しの答えの写し)
public struct Suspect: Sendable, Hashable {
    public let heard: String
    public let surfaces: [String]

    public init(heard: String, surfaces: [String]) {
        self.heard = heard
        self.surfaces = surfaces
    }
}

/// 辞書の候補。候補の窓に並べ、本人が入れるか捨てるかを選ぶ(設計書「選ぶ: 候補の窓で、入れるか捨てるかを決める」)
public struct SuggestionCandidate: Codable, Sendable, Hashable {
    /// 認識した語(文の中の字のまま)
    public let heard: String
    /// 表記の案(1〜2個。よく使われる表記から順に)
    public let surfaces: [String]
    /// 出た文の前後20字
    public let before: String
    public let after: String

    public init(heard: String, surfaces: [String], before: String, after: String) {
        self.heard = heard
        self.surfaces = surfaces
        self.before = before
        self.after = after
    }

    /// 入れ方の初期値(1つ目の表記の案で決める)
    public var initialMode: InsertionMode {
        InsertionMode.initial(heard: heard, surface: surfaces[0])
    }
}

/// 候補の入れ方
public enum InsertionMode: String, Codable, Sendable {
    /// 辞書の語に足し、認識した語を置き換え元に入れる
    case replace
    /// 表記をヒントだけの語として入れる。置き換えには使わない
    case hintOnly

    /// 初期値。認識した語がカタカナ・英字・その2つの混ざりだけでできていて、表記に英字を含むときだけ置き換える。
    /// 漢字・かなの語は辞書の決まりのとおり置き換えに使わず、カタカナどうしはふつうの語どうしの聞き違い(ホーム → フォーム)が多いのでヒントだけにする
    public static func initial(heard: String, surface: String) -> InsertionMode {
        guard TermReplacer.kind(of: heard) != .unsupported, surface.contains(where: \.isASCIILetter) else { return .hintOnly }
        return .replace
    }
}

/// 本人が捨てた組。同じ組は二度出さない
public struct DiscardedPair: Codable, Sendable, Hashable {
    public let heard: String
    public let surface: String

    public init(heard: String, surface: String) {
        self.heard = CandidateFilter.compact(heard)
        self.surface = CandidateFilter.compact(surface)
    }
}

/// 洗い出しの答えから、候補に残すものを選ぶ(設計書「挙げる」の除き方)。
/// 文の中に出てこない語・表記の案が認識した語と同じもの・辞書の語・本人が前に捨てた組と同じ組は捨てる
public enum CandidateFilter {
    public static let contextLength = 20
    /// 長すぎる語は、文の書き直しとみなして捨てる
    public static let maximumHeardLength = 30
    public static let maximumSurfaces = 2

    public static func candidates(
        from suspects: [Suspect],
        in text: String,
        dictionary surfaces: [String],
        discarded: Set<DiscardedPair> = []
    ) -> [SuggestionCandidate] {
        let known = Set(surfaces.map(compact))
        var seen: Set<String> = []
        var result: [SuggestionCandidate] = []
        for suspect in suspects {
            let heardKey = compact(suspect.heard.trimmingCharacters(in: .whitespaces))
            guard !heardKey.isEmpty, heardKey.count <= maximumHeardLength,
                  !known.contains(heardKey), !seen.contains(heardKey),
                  let range = find(suspect.heard, in: text) else { continue }
            let heard = String(text[range])
            var keys: Set<String> = [heardKey]
            let proposals = suspect.surfaces
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { proposal in
                    let key = compact(proposal)
                    return !key.isEmpty
                        && !discarded.contains(DiscardedPair(heard: heard, surface: proposal))
                        && keys.insert(key).inserted
                }
                .prefix(maximumSurfaces)
            guard !proposals.isEmpty else { continue }
            seen.insert(heardKey)
            result.append(SuggestionCandidate(
                heard: heard,
                surfaces: Array(proposals),
                before: String(text[..<range.lowerBound].suffix(contextLength)),
                after: String(text[range.upperBound...].prefix(contextLength))
            ))
        }
        return result
    }

    /// 空白と中黒を除いた形。「B テスト」と「Bテスト」、「クロード・コード」と「クロードコード」を同じ語とみなす
    public static func compact(_ text: String) -> String {
        text.filter { $0 != " " && $0 != "・" && $0 != "\u{3000}" }
    }

    /// 文の中で語が出た範囲。字の間の空白・中黒の有無は問わない
    static func find(_ heard: String, in text: String) -> Range<String.Index>? {
        let letters = compact(heard)
        guard !letters.isEmpty else { return nil }
        let pattern = letters.map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "[・ ]?")
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return Range(match.range, in: text)
    }
}
