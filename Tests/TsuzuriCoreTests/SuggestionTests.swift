import Testing
@testable import TsuzuriCore

@Suite("拾う: 字の種類の印")
struct SuspectMarkerTests {
    @Test("カタカナが3字以上続く語に印を付け、2字以下には付けない")
    func katakanaRuns() {
        #expect(SuspectMarker.mark("その後クロードコードでタスクを整理します", dictionary: []) == ["クロードコード", "タスク"])
        #expect(SuspectMarker.mark("このメモを見て", dictionary: []) == [])
    }

    @Test("中黒で区切られたカタカナは1語にまとめる")
    func katakanaWithNakaguro() {
        #expect(SuspectMarker.mark("クロード・コードで直す", dictionary: []) == ["クロード・コード"])
    }

    @Test("英字とカタカナが混ざる語は、間に空白があっても1語にまとめる")
    func mixedWords() {
        #expect(SuspectMarker.mark("いま B テストの設定を見直しています", dictionary: []) == ["B テスト"])
        #expect(SuspectMarker.mark("Gitハブに上げる", dictionary: []) == ["Gitハブ"])
    }

    @Test("空白で続く英字の語は1語にまとめ、数字だけの語は拾わない")
    func latinWords() {
        #expect(SuspectMarker.mark("Cloud Code で 3 つ直す", dictionary: []) == ["Cloud Code"])
        #expect(SuspectMarker.mark("Next.js の設定", dictionary: []) == ["Next.js"])
    }

    @Test("辞書の語は調べない")
    func skipsDictionaryTerms() {
        #expect(SuspectMarker.mark("Claude Code で Vitest の設定を足す", dictionary: ["Claude Code", "Vitest"]) == [])
    }

    @Test("漢字・かなの語は拾わない")
    func skipsKanjiAndKana() {
        #expect(SuspectMarker.mark("この不具合は性的解析で拾える。ぞっとの型", dictionary: []) == [])
    }
}

@Suite("除く: 候補に残すもの")
struct CandidateFilterTests {
    let sentence = "その後クロードコードでタスクを整理します"

    @Test("文の中の字のまま、前後20字を添えて候補にする")
    func keepsContext() {
        let candidates = CandidateFilter.candidates(
            from: [Suspect(heard: "クロードコード", surfaces: ["Claude Code", "Cloud Code"])],
            in: sentence, dictionary: []
        )
        #expect(candidates == [SuggestionCandidate(heard: "クロードコード", surfaces: ["Claude Code", "Cloud Code"], before: "その後", after: "でタスクを整理します")])
    }

    @Test("空白の有無が違っても、文の中の字に合わせる")
    func matchesWithoutSpaces() {
        let candidates = CandidateFilter.candidates(
            from: [Suspect(heard: "Bテスト", surfaces: ["Vitest"])],
            in: "いま B テストの設定を見直しています", dictionary: []
        )
        #expect(candidates.map(\.heard) == ["B テスト"])
    }

    @Test("文に出てこない語・辞書の語・表記の案が同じものは捨てる")
    func dropsUnusable() {
        let candidates = CandidateFilter.candidates(
            from: [
                Suspect(heard: "ネクストジェイエス", surfaces: ["Next.js"]),
                Suspect(heard: "クロードコード", surfaces: ["Claude Code"]),
                Suspect(heard: "タスク", surfaces: ["タスク"]),
            ],
            in: sentence, dictionary: ["クロードコード"]
        )
        #expect(candidates.isEmpty)
    }

    @Test("本人が捨てた組は出さず、残りの案があれば残す")
    func dropsDiscardedPairs() {
        let candidates = CandidateFilter.candidates(
            from: [Suspect(heard: "クロードコード", surfaces: ["Cloud Code", "Claude Code"])],
            in: sentence, dictionary: [],
            discarded: [DiscardedPair(heard: "クロード・コード", surface: "Cloud Code")]
        )
        #expect(candidates.map(\.surfaces) == [["Claude Code"]])
    }

    @Test("同じ語は1つにまとめ、表記の案は2つまでにする")
    func dedupes() {
        let candidates = CandidateFilter.candidates(
            from: [
                Suspect(heard: "クロードコード", surfaces: ["Claude Code", "Claude code", "Cloud Code"]),
                Suspect(heard: "クロード・コード", surfaces: ["Claude"]),
            ],
            in: sentence, dictionary: []
        )
        #expect(candidates.map(\.surfaces) == [["Claude Code", "Claude code"]])
    }
}

@Suite("除く: 見込みの無い直し")
struct PlausibilityTests {
    @Test("語を足しただけ・削っただけの案は捨て、大文字小文字だけの直しは残す")
    func containment() {
        #expect(!CandidateFilter.isPlausible(heard: "Slack", surface: "Slack client"))
        #expect(!CandidateFilter.isPlausible(heard: "評価", surface: "評価率"))
        #expect(CandidateFilter.isPlausible(heard: "MacOS", surface: "macOS"))
    }

    @Test("漢字の語を英字に訳した案と、略語を書き下した案は捨てる")
    func translations() {
        #expect(!CandidateFilter.isPlausible(heard: "以降", surface: "after"))
        #expect(!CandidateFilter.isPlausible(heard: "API", surface: "Application Programming Interface"))
        #expect(CandidateFilter.isPlausible(heard: "ぞっと", surface: "Zod"))
    }

    @Test("漢字・かなどうしは、読みが近い直しだけ残す")
    func homophones() {
        #expect(CandidateFilter.isPlausible(heard: "性的", surface: "静的"))
        #expect(CandidateFilter.isPlausible(heard: "規定", surface: "既定"))
        #expect(!CandidateFilter.isPlausible(heard: "明日", surface: "明後日"))
    }

    @Test("助詞まで含めて挙げた語は、印の付いた語に切り詰める")
    func trimsToMarked() {
        #expect(CandidateFilter.trimToMarked("ストーリーブックのストーリー", marked: ["ストーリーブック", "ストーリー"]) == "ストーリーブック")
        #expect(CandidateFilter.trimToMarked("性的", marked: []) == "性的")
    }
}

@Suite("入れ方の初期値")
struct InsertionModeTests {
    @Test("カタカナや英字の語で、表記に英字を含むときは置き換える")
    func replace() {
        #expect(InsertionMode.initial(heard: "クロードコード", surface: "Claude Code") == .replace)
        #expect(InsertionMode.initial(heard: "B テスト", surface: "Vitest") == .replace)
        #expect(InsertionMode.initial(heard: "Github", surface: "GitHub") == .replace)
    }

    @Test("漢字・かなの語と、カタカナどうしはヒントだけにする")
    func hintOnly() {
        #expect(InsertionMode.initial(heard: "性的", surface: "静的") == .hintOnly)
        #expect(InsertionMode.initial(heard: "ぞっと", surface: "Zod") == .hintOnly)
        #expect(InsertionMode.initial(heard: "ホーム", surface: "フォーム") == .hintOnly)
    }
}

@Suite("洗い出しの数え方")
struct SuggestionScoreTests {
    func candidate(_ heard: String, _ surfaces: [String]) -> SuggestionCandidate {
        SuggestionCandidate(heard: heard, surfaces: surfaces, before: "", after: "")
    }

    @Test("誤って認識された辞書の語に当たり、表記の案が正しければ当たりに数える")
    func coversTermError() {
        let result = SuggestionScore.score(
            reference: "Claude Code で TanStack Query のキャッシュを足す",
            hypothesis: "クロードコードで単スタッククエリーのキャッシュを足す",
            terms: ["Claude Code", "TanStack Query"],
            candidates: [candidate("クロードコード", ["Claude Code"]), candidate("スタッククエリー", ["Stack Query"])]
        )
        #expect(result.termErrors == ["Claude Code", "TanStack Query"])
        #expect(result.missed.isEmpty)
        #expect(result.verdicts == [.term(["Claude Code"], surfaceHit: true), .term(["TanStack Query"], surfaceHit: false)])
    }

    @Test("正しく出ていた語を挙げたら外れ、辞書に無い語の誤りは別に数える")
    func falsePositiveAndOtherError() {
        let result = SuggestionScore.score(
            reference: "フォームのバリデーションを直してください",
            hypothesis: "ホームのバリデーションを直してください",
            terms: ["Zod"],
            candidates: [candidate("バリデーション", ["Validation"]), candidate("ホーム", ["フォーム"])]
        )
        #expect(result.termErrors.isEmpty)
        #expect(result.verdicts == [.falsePositive, .otherError])
    }

    @Test("同じ字が2回出る文では、前の候補が使っていない位置で判定する")
    func repeatedWords() {
        let result = SuggestionScore.score(
            reference: "Vitest のテストも書いてください",
            hypothesis: "B テストのテストも書いてください",
            terms: ["Vitest"],
            candidates: [candidate("B テスト", ["Vitest"]), candidate("テスト", ["Test"])]
        )
        #expect(result.verdicts == [.term(["Vitest"], surfaceHit: true), .falsePositive])
    }

    @Test("候補に上がらなかった誤りは取りこぼしに残る")
    func missed() {
        let result = SuggestionScore.score(
            reference: "このエラーは静的解析で拾えるはず",
            hypothesis: "このエラーは性的解析で拾えるはず",
            terms: ["静的"],
            candidates: []
        )
        #expect(result.missed == ["静的"])
    }

    @Test("文ごとの件数を足して、3つの数を出す")
    func tally() {
        var tally = SuggestionTally()
        tally.add(SuggestionScore.SentenceResult(termErrors: ["Claude Code", "Vitest"], missed: ["Vitest"], verdicts: [.term(["Claude Code"], surfaceHit: true), .falsePositive]))
        tally.add(SuggestionScore.SentenceResult(termErrors: [], missed: [], verdicts: []))
        #expect(tally.coveredRate == 0.5)
        #expect(tally.surfaceRate == 1)
        #expect(tally.falsePositivesPerTen == 5)
        #expect(!tally.meetsTargets)
    }
}
