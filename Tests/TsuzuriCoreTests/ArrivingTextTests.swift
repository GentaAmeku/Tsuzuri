import Testing
@testable import TsuzuriCore

@Suite("新しく出た字の切れ端")
struct ArrivingTextTests {
    @Test("後ろに字が増えたら、増えた分だけが新しい切れ端になる")
    func appended() {
        var text = ArrivingText()
        text.update(to: "クロード", at: 0, settleAfter: 1)
        text.update(to: "クロードコードで", at: 0.3, settleAfter: 1)
        #expect(text.pieces == [
            .init(text: "クロード", arrival: 0),
            .init(text: "コードで", arrival: 0.3),
        ])
    }

    @Test("認識が後ろを言い直したら、同じ頭は残して、変わったところからを新しくする")
    func rewritten() {
        var text = ArrivingText()
        text.update(to: "単スタ", at: 0, settleAfter: 1)
        text.update(to: "タンススタック", at: 0.2, settleAfter: 1)
        #expect(text.pieces == [.init(text: "タンススタック", arrival: 0.2)])

        text.update(to: "タンススタックで", at: 0.4, settleAfter: 1)
        text.update(to: "タンスです", at: 0.5, settleAfter: 1)
        #expect(text.pieces == [
            .init(text: "タンス", arrival: 0.2),
            .init(text: "です", arrival: 0.5),
        ])
    }

    @Test("時間がたった切れ端は落ち着いたものとしてまとめ、動いている字が無くなる")
    func settles() {
        var text = ArrivingText()
        text.update(to: "1回実演で", at: 0, settleAfter: 0.8)
        text.update(to: "1回実演で見せます。", at: 0.5, settleAfter: 0.8)
        text.update(to: "1回実演で見せます。仕事の", at: 1.0, settleAfter: 0.8)
        #expect(text.pieces == [
            .init(text: "1回実演で", arrival: nil),
            .init(text: "見せます。", arrival: 0.5),
            .init(text: "仕事の", arrival: 1.0),
        ])
        #expect(text.isAnimating(at: 1.2, duration: 0.8))
        #expect(!text.isAnimating(at: 1.9, duration: 0.8))
        #expect(text.text == "1回実演で見せます。仕事の")
    }

    @Test("確定した字の数で色の区切りを切る(切れ端の途中でも切る)")
    func segments() {
        var text = ArrivingText()
        text.update(to: "見せます。", at: 0, settleAfter: 1)
        text.update(to: "見せます。仕事のメモ", at: 0.2, settleAfter: 1)
        #expect(text.segments(finalLength: 7) == [
            .init(text: "見せます。", arrival: 0, isFinal: true),
            .init(text: "仕事", arrival: 0.2, isFinal: true),
            .init(text: "のメモ", arrival: 0.2, isFinal: false),
        ])
        #expect(text.segments(finalLength: 0).allSatisfy { !$0.isFinal })
    }

    @Test("文字が空になったら切れ端も無くなる")
    func cleared() {
        var text = ArrivingText()
        text.update(to: "テスト", at: 0, settleAfter: 1)
        text.update(to: "", at: 0.1, settleAfter: 1)
        #expect(text.pieces.isEmpty)
    }
}
