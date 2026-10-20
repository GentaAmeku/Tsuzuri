import Foundation
import Testing
@testable import TsuzuriCore

@Suite("途中の文字の組み立て")
struct TranscriptAssemblerTests {
    @Test("確定した文字はつなげ、変わりうる文字は応答ごとに入れ替える")
    func finalAndTentative() {
        var assembler = TranscriptAssembler()
        assembler.apply([.init(text: "クロード", isFinal: false)])
        #expect(assembler.text == "クロード")
        assembler.apply([.init(text: "Claude", isFinal: true), .init(text: " Code で", isFinal: false)])
        assembler.apply([.init(text: " Code で", isFinal: true), .init(text: "直して", isFinal: false)])
        #expect(assembler.finalText == "Claude Code で")
        #expect(assembler.tentativeText == "直して")
    }

    @Test("終わりの印は文字に含めない")
    func dropsMarkers() {
        var assembler = TranscriptAssembler()
        assembler.apply([.init(text: "送ってください。", isFinal: true), .init(text: "<fin>", isFinal: true)])
        #expect(assembler.text == "送ってください。")
    }
}

@Suite("貼り付けるかの判断")
struct PasteDecisionTests {
    @Test("Slack の入力欄には貼る")
    func textAreaPastes() {
        let focus = PasteDecision.Focus(role: "AXTextArea", acceptsText: true)
        #expect(PasteDecision.decide(focus: focus, appBundleID: "com.tinyspeck.slackmacgap") == .paste)
    }

    @Test("Finder でファイルの一覧を選んでいるときは、クリップボードに残す")
    func finderListKeepsClipboard() {
        let focus = PasteDecision.Focus(role: "AXList", acceptsText: false)
        #expect(PasteDecision.decide(focus: focus, appBundleID: "com.apple.finder") == .clipboardOnly)
    }

    @Test("デスクトップを選んでいて要素が読めないときは、クリップボードに残す")
    func desktopKeepsClipboard() {
        #expect(PasteDecision.decide(focus: nil, appBundleID: "com.apple.finder") == .clipboardOnly)
    }

    @Test("Electron 製のアプリで要素が読めないときは、判定できないので貼る")
    func unknownPastes() {
        #expect(PasteDecision.decide(focus: nil, appBundleID: "com.anthropic.claudefordesktop") == .paste)
        let web = PasteDecision.Focus(role: "AXWebArea", acceptsText: false)
        #expect(PasteDecision.decide(focus: web, appBundleID: "com.anthropic.claudefordesktop") == .paste)
    }
}

@Suite("履歴")
struct DictationHistoryTests {
    func entry(_ text: String, error: String? = nil, at seconds: Double = 0) -> HistoryEntry {
        HistoryEntry(date: Date(timeIntervalSince1970: 1_800_000_000 + seconds), app: "com.tinyspeck.slackmacgap", engine: "soniox", raw: text, text: text, error: error)
    }

    @Test("JSON Lines に書いて読み戻せる")
    func roundTrip() throws {
        let entries = [entry("Claude Code で直して"), entry("", error: "Soniox につながりませんでした", at: 60)]
        let lines = try DictationHistory.encode(entries)
        #expect(lines.split(separator: "\n").count == 2)
        #expect(DictationHistory.decode(lines) == entries)
    }

    @Test("壊れた行は飛ばして、ほかの行は読む")
    func skipsBrokenLines() throws {
        let lines = try DictationHistory.encode([entry("確認してください")]) + "{壊れた行\n"
        #expect(DictationHistory.decode(lines).map(\.text) == ["確認してください"])
    }

    @Test("100件を超えたら古いものから落とす")
    func keepsLatest() {
        let entries = (0..<100).map { entry("文\($0)", at: Double($0)) }
        let appended = DictationHistory.appending(entry("新しい文", at: 100), to: entries)
        #expect(appended.count == 100)
        #expect(appended.first?.text == "文1")
        #expect(appended.last?.text == "新しい文")
    }

    @Test("貼り直すのは、失敗していない最新の文字")
    func lastTextSkipsFailures() {
        let entries = [entry("前の文"), entry("", error: "確定が3秒を超えました", at: 1)]
        #expect(DictationHistory.lastText(in: entries) == "前の文")
    }

    @Test("音声は7日を過ぎたものだけ消す")
    func audioRetention() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day = 24.0 * 60 * 60
        let files = [("8日前.wav", now.addingTimeInterval(-8 * day)), ("6日前.wav", now.addingTimeInterval(-6 * day))]
        #expect(AudioRetention.expired(files.map { (file: $0.0, createdAt: $0.1) }, now: now) == ["8日前.wav"])
    }
}

@Suite("話し声の有無")
struct SpeechPresenceTests {
    func tone(seconds: Double, amplitude: Float) -> [Float] {
        (0..<Int(seconds * 16_000)).map { amplitude * sin(Float($0) * 2 * .pi * 220 / 16_000) }
    }

    @Test("ほぼ無音の録音は、話し声なしとみなす")
    func silence() {
        #expect(!SpeechPresence.hasSpeech(tone(seconds: 2, amplitude: 0.003)))
        #expect(!SpeechPresence.hasSpeech([]))
    }

    @Test("声の大きさの音が0.3秒以上あれば、話し声ありとみなす")
    func speech() {
        #expect(SpeechPresence.hasSpeech(tone(seconds: 1, amplitude: 0.1)))
        #expect(!SpeechPresence.hasSpeech(tone(seconds: 0.2, amplitude: 0.1) + tone(seconds: 1, amplitude: 0.001)))
    }
}
