import Foundation
import Testing
@testable import TsuzuriCore

@Suite("候補を貯める")
struct CandidateBookTests {
    let t0 = Date(timeIntervalSince1970: 0)
    let t1 = Date(timeIntervalSince1970: 60)

    func found(_ heard: String, _ surface: String, before: String = "", after: String = "") -> SuggestionCandidate {
        SuggestionCandidate(heard: heard, surfaces: [surface], before: before, after: after)
    }

    @Test("同じ組は1つにまとめて回数を数え、前後の文は最後のものにする")
    func mergesSamePair() {
        var file = CandidateBook.merging([found("クロードコード", "Claude Code", before: "その後")], app: "com.tinyspeck.slackmacgap", at: t0, into: CandidatesFile())
        file = CandidateBook.merging([found("クロード・コード", "Claude Code", before: "まず")], app: "com.anthropic.claudefordesktop", at: t1, into: file)
        #expect(file.items.count == 1)
        #expect(file.items[0].count == 2)
        #expect(file.items[0].before == "まず")
        #expect(file.items[0].app == "com.anthropic.claudefordesktop")
    }

    @Test("捨てた組は二度出さない")
    func skipsDiscarded() {
        var file = CandidateBook.merging([found("エラー", "error")], app: nil, at: t0, into: CandidatesFile())
        file = CandidateBook.discarding(file.items[0].id, from: file)
        file = CandidateBook.merging([found("エラー", "error")], app: nil, at: t1, into: file)
        #expect(file.items.isEmpty)
        #expect(file.discarded == [DiscardedPair(heard: "エラー", surface: "error")])
    }

    @Test("入れた組は、本人が直した表記の組も含めて二度出さない")
    func skipsInserted() {
        var file = CandidateBook.merging([found("性的", "性的な")], app: nil, at: t0, into: CandidatesFile())
        file = CandidateBook.inserting(file.items[0].id, surface: "静的", from: file)
        file = CandidateBook.merging([found("性的", "静的")], app: nil, at: t1, into: file)
        #expect(file.items.isEmpty)
    }

    @Test("出た回数の多い順、同じなら新しい順に並べる")
    func orders() {
        var file = CandidateBook.merging([found("ゾッド", "Zod")], app: nil, at: t0, into: CandidatesFile())
        file = CandidateBook.merging([found("バーセル", "Vercel")], app: nil, at: t1, into: file)
        file = CandidateBook.merging([found("ゾッド", "Zod")], app: nil, at: t1, into: file)
        file = CandidateBook.merging([found("ジラ", "Jira")], app: nil, at: t1.addingTimeInterval(1), into: file)
        #expect(CandidateBook.ordered(file.items).map(\.heard) == ["ゾッド", "ジラ", "バーセル"])
    }
}

@Suite("辞書に入れる")
struct DictionaryInsertionTests {
    @Test("置き換えるときは、新しい語として置き換え元つきで足す")
    func addsReplacement() {
        let entries = DictionaryInsertion.insert(heard: "クロードコード", surface: "Claude Code", mode: .replace, into: [])
        #expect(entries == [DictionaryEntry(surface: "Claude Code", from: ["クロードコード"], hint: true, pinned: false, source: .auto)])
    }

    @Test("表記が辞書にあれば、置き換え元だけ足す")
    func addsFromToExisting() {
        let existing = [DictionaryEntry(surface: "Vitest", from: ["バイテスト"], hint: true, pinned: true, source: .manual)]
        let entries = DictionaryInsertion.insert(heard: "B テスト", surface: "Vitest", mode: .replace, into: existing)
        #expect(entries == [DictionaryEntry(surface: "Vitest", from: ["バイテスト", "B テスト"], hint: true, pinned: true, source: .manual)])
    }

    @Test("ヒントだけのときは置き換え元を付けず、表記がすでにあれば何も足さない")
    func hintOnly() {
        let entries = DictionaryInsertion.insert(heard: "性的", surface: "静的", mode: .hintOnly, into: [])
        #expect(entries == [DictionaryEntry(surface: "静的", from: [], hint: true, pinned: false, source: .auto)])
        #expect(DictionaryInsertion.insert(heard: "性的", surface: "静的", mode: .hintOnly, into: entries!) == nil)
    }

    @Test("漢字・かなの語は、置き換えを選んでもヒントだけにする")
    func kanjiNeverReplaces() {
        let entries = DictionaryInsertion.insert(heard: "ぞっと", surface: "Zod", mode: .replace, into: [])
        #expect(entries?.first?.from == [])
    }
}
