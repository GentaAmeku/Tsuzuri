import Testing
@testable import TsuzuriCore

@Suite("文字誤り率")
struct CharacterErrorRateTests {
    @Test("同じ文なら誤りは0")
    func identical() {
        let count = CharacterErrorRate.measure(reference: "PR のレビューを進めます。", hypothesis: "PR のレビューを進めます。")
        #expect(count == ErrorCount(edits: 0, length: 12))
        #expect(count.rate == 0)
    }

    @Test("全角英数と大文字小文字はそろえてから比べる")
    func normalizesWidthAndCase() {
        let count = CharacterErrorRate.measure(reference: "API を呼ぶ", hypothesis: "ａｐｉを呼ぶ")
        #expect(count.edits == 0)
    }

    @Test("空白と句読点は数えない")
    func ignoresSpacesAndPunctuation() {
        let count = CharacterErrorRate.measure(reference: "Next.js の、設定。", hypothesis: "Nextjs の設定")
        #expect(count.edits == 0)
    }

    @Test("長音の「ー」は文字として比べる")
    func keepsProlongedSoundMark() {
        let count = CharacterErrorRate.measure(reference: "サーバー", hypothesis: "サーバ")
        #expect(count == ErrorCount(edits: 1, length: 4))
    }

    @Test("同音異義語の取り違えは置換として数える")
    func countsSubstitution() {
        let count = CharacterErrorRate.measure(reference: "静的解析", hypothesis: "性的解析")
        #expect(count == ErrorCount(edits: 1, length: 4))
        #expect(count.rate == 0.25)
    }

    @Test("認識結果が空なら、正解の文字数がそのまま誤りになる")
    func emptyHypothesis() {
        let count = CharacterErrorRate.measure(reference: "移行の作業", hypothesis: "")
        #expect(count == ErrorCount(edits: 5, length: 5))
    }

    @Test("抜けと余分も1字ずつ数える")
    func countsInsertionAndDeletion() {
        #expect(CharacterErrorRate.editDistance(Array("確認します"), Array("確認しまます")) == 1)
        #expect(CharacterErrorRate.editDistance(Array("確認します"), Array("確認す")) == 2)
    }

    @Test("文ごとの数を足して全体の率を出す")
    func addsCounts() {
        let total = ErrorCount(edits: 1, length: 10) + ErrorCount(edits: 3, length: 30)
        #expect(total == ErrorCount(edits: 4, length: 40))
        #expect(total.rate == 0.1)
    }
}
