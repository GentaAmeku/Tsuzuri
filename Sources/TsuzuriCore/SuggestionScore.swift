/// 辞書の候補の洗い出しを、正解の文と比べて数える(設計書「精度の測り方」の3つの数)。
/// 正解の文と認識の文を1字ずつ対応づけ、候補の語が正解の文のどこに当たるかで判定する
public enum SuggestionScore {
    /// 1つの候補の判定
    public enum Verdict: Sendable, Equatable {
        /// 誤って認識された辞書の語に当たった。`surfaceHit` は表記の案に正しい表記が入っていたか
        case term([String], surfaceHit: Bool)
        /// 正解の文と同じ字で出ていた語を挙げた(外れ)
        case falsePositive
        /// 辞書に無い語の誤りを挙げた(外れに数えない)
        case otherError
    }

    public struct SentenceResult: Sendable, Equatable {
        /// 誤って認識された辞書の語(出た順)
        public let termErrors: [String]
        /// 候補に上がらなかった、誤って認識された辞書の語
        public let missed: [String]
        public let verdicts: [Verdict]
    }

    public static func score(reference: String, hypothesis: String, terms: [String], candidates: [SuggestionCandidate]) -> SentenceResult {
        let ref = TermAccuracy.normalize(reference)
        let hyp = TermAccuracy.normalize(hypothesis)
        let alignment = Alignment(ref, hyp)
        let errors = TermAccuracy.positions(of: terms, in: ref).filter { term in
            !alignment.hypothesis(for: term.range).elementsEqual(TermAccuracy.normalize(term.term))
        }
        var covered: Set<Int> = []
        var used: [Range<Int>] = []
        let verdicts: [Verdict] = candidates.map { candidate in
            let key = TermAccuracy.normalize(candidate.heard)
            // 同じ字が2回出る文(B テストのテスト)では、前の候補が使っていない位置を採る
            guard let start = firstIndex(of: key, in: hyp, avoiding: used) else { return .otherError }
            used.append(start..<(start + key.count))
            guard let refRange = alignment.reference(for: start..<(start + key.count)) else { return .otherError }
            let hits = errors.indices.filter { errors[$0].range.overlaps(refRange) }
            if !hits.isEmpty {
                covered.formUnion(hits)
                let surfaces = Set(candidate.surfaces.map(TermAccuracy.normalize))
                let surfaceHit = hits.contains { surfaces.contains(TermAccuracy.normalize(errors[$0].term)) }
                return .term(hits.map { errors[$0].term }, surfaceHit: surfaceHit)
            }
            return ref[refRange].elementsEqual(key) ? .falsePositive : .otherError
        }
        return SentenceResult(
            termErrors: errors.map(\.term),
            missed: errors.indices.filter { !covered.contains($0) }.map { errors[$0].term },
            verdicts: verdicts
        )
    }

    static func firstIndex(of key: [Character], in characters: [Character], avoiding used: [Range<Int>]) -> Int? {
        guard !key.isEmpty, key.count <= characters.count else { return nil }
        let starts = (0...(characters.count - key.count)).filter { TermAccuracy.starts(characters, at: $0, with: key) }
        return starts.first { start in !used.contains { $0.overlaps(start..<(start + key.count)) } } ?? starts.first
    }
}

/// 3つの数の元になる件数。文ごとに足し合わせる
public struct SuggestionTally: Sendable, Equatable {
    public var sentences = 0
    public var candidates = 0
    /// 誤って認識された辞書の語の数(① の分母)
    public var termErrors = 0
    /// そのうち候補に上がった数(① の分子)
    public var covered = 0
    /// 辞書の語に当たった候補の数(② の分母)
    public var termCandidates = 0
    /// そのうち表記の案に正しい表記が入っていた数(② の分子)
    public var surfaceHits = 0
    /// 外れの候補(③)
    public var falsePositives = 0
    /// 辞書に無い語の誤りを挙げた数(外れに数えない)
    public var otherErrors = 0

    public init() {}

    public mutating func add(_ result: SuggestionScore.SentenceResult) {
        sentences += 1
        candidates += result.verdicts.count
        termErrors += result.termErrors.count
        covered += result.termErrors.count - result.missed.count
        for verdict in result.verdicts {
            switch verdict {
            case let .term(_, surfaceHit):
                termCandidates += 1
                if surfaceHit { surfaceHits += 1 }
            case .falsePositive:
                falsePositives += 1
            case .otherError:
                otherErrors += 1
            }
        }
    }

    /// ① 挙げた割合
    public var coveredRate: Double { termErrors == 0 ? 1 : Double(covered) / Double(termErrors) }
    /// ② 表記の当たり
    public var surfaceRate: Double { termCandidates == 0 ? 0 : Double(surfaceHits) / Double(termCandidates) }
    /// ③ 外れの候補(10文あたり)
    public var falsePositivesPerTen: Double { sentences == 0 ? 0 : Double(falsePositives) * 10 / Double(sentences) }

    /// 設計書の目標(① 8割以上・② 6割以上・③ 10文あたり3件以下)に届いたか
    public var meetsTargets: Bool {
        coveredRate >= 0.8 && surfaceRate >= 0.6 && falsePositivesPerTen <= 3
    }

    public static func + (lhs: SuggestionTally, rhs: SuggestionTally) -> SuggestionTally {
        var sum = lhs
        sum.sentences += rhs.sentences
        sum.candidates += rhs.candidates
        sum.termErrors += rhs.termErrors
        sum.covered += rhs.covered
        sum.termCandidates += rhs.termCandidates
        sum.surfaceHits += rhs.surfaceHits
        sum.falsePositives += rhs.falsePositives
        sum.otherErrors += rhs.otherErrors
        return sum
    }
}

/// 正解の文と認識の文の、1字ずつの対応(編集距離の最小の道筋)
struct Alignment {
    enum Step: Equatable {
        /// 同じ字か置き換わった字
        case pair(ref: Int, hyp: Int)
        /// 正解にあって認識に無い字
        case deletion(ref: Int)
        /// 認識にだけある字
        case insertion(hyp: Int)

        var ref: Int? {
            switch self {
            case let .pair(ref, _), let .deletion(ref): ref
            case .insertion: nil
            }
        }

        var hyp: Int? {
            switch self {
            case let .pair(_, hyp), let .insertion(hyp): hyp
            case .deletion: nil
            }
        }
    }

    let steps: [Step]
    let hyp: [Character]

    init(_ ref: [Character], _ hyp: [Character]) {
        self.hyp = hyp
        var cost = Array(repeating: Array(repeating: 0, count: hyp.count + 1), count: ref.count + 1)
        for i in 0...ref.count { cost[i][0] = i }
        for j in 0...hyp.count { cost[0][j] = j }
        if !ref.isEmpty && !hyp.isEmpty {
            for i in 1...ref.count {
                for j in 1...hyp.count {
                    cost[i][j] = min(
                        cost[i - 1][j - 1] + (ref[i - 1] == hyp[j - 1] ? 0 : 1),
                        cost[i - 1][j] + 1,
                        cost[i][j - 1] + 1
                    )
                }
            }
        }
        var steps: [Step] = []
        var i = ref.count
        var j = hyp.count
        while i > 0 || j > 0 {
            if i > 0, j > 0, cost[i][j] == cost[i - 1][j - 1] + (ref[i - 1] == hyp[j - 1] ? 0 : 1) {
                steps.append(.pair(ref: i - 1, hyp: j - 1))
                i -= 1
                j -= 1
            } else if i > 0, cost[i][j] == cost[i - 1][j] + 1 {
                steps.append(.deletion(ref: i - 1))
                i -= 1
            } else {
                steps.append(.insertion(hyp: j - 1))
                j -= 1
            }
        }
        self.steps = steps.reversed()
    }

    /// 正解の文の範囲に当たる、認識の文の字
    func hypothesis(for refRange: Range<Int>) -> [Character] {
        guard let first = steps.firstIndex(where: { $0.ref.map(refRange.contains) == true }),
              let last = steps.lastIndex(where: { $0.ref.map(refRange.contains) == true }) else { return [] }
        return steps[first...last].compactMap(\.hyp).map { hyp[$0] }
    }

    /// 認識の文の範囲に当たる、正解の文の範囲。認識にだけある字なら nil
    func reference(for hypRange: Range<Int>) -> Range<Int>? {
        guard let first = steps.firstIndex(where: { $0.hyp.map(hypRange.contains) == true }),
              let last = steps.lastIndex(where: { $0.hyp.map(hypRange.contains) == true }) else { return nil }
        let refs = steps[first...last].compactMap(\.ref)
        guard let low = refs.min(), let high = refs.max() else { return nil }
        return low..<(high + 1)
    }
}
