import Foundation
import Testing
@testable import TsuzuriCore

func entry(_ surface: String, from: [String] = [], hint: Bool = true, pinned: Bool = false) -> DictionaryEntry {
    DictionaryEntry(surface: surface, from: from, hint: hint, pinned: pinned, source: .manual)
}

@Suite("正規化")
struct NormalizerTests {
    @Test("全角の英数字を半角にする")
    func halfWidth() {
        #expect(Normalizer.normalize("ＰＲを３つ") == "PRを3つ")
    }

    @Test("全角の「，．」は読点と句点にし、数字の間なら小数点にする")
    func fullWidthPunctuation() {
        #expect(Normalizer.normalize("確認しました，あとで直します．") == "確認しました、あとで直します。")
        #expect(Normalizer.normalize("約０．１２ドル") == "約0.12ドル")
    }

    @Test("半角の「.」は変えないので Next.js は壊れない")
    func keepsDot() {
        #expect(Normalizer.normalize("Next.js の App Router") == "Next.js の App Router")
    }

    @Test("日本語の字の間の空白を消し、英字の前後の空白は残す")
    func removesJapaneseSpaces() {
        #expect(Normalizer.normalize("今日は 早めに 上がります。 残りは Jira に") == "今日は早めに上がります。残りは Jira に")
    }

    @Test("連続した空白と、前後の空白をまとめる")
    func collapsesSpaces() {
        #expect(Normalizer.normalize("  Claude   Code で ") == "Claude Code で")
    }
}

@Suite("つなぎ言葉")
struct FillerRemoverTests {
    let fillers = ["えー", "えーと", "えっと", "あのー"]

    @Test("文頭のつなぎ言葉と、読点の前のつなぎ言葉を消す")
    func removesFillers() {
        #expect(FillerRemover.remove(fillers, from: "えーと、PR を見てください。") == "PR を見てください。")
        #expect(FillerRemover.remove(fillers, from: "明日は、あのー、10時からです。") == "明日は、10時からです。")
    }

    @Test("登録していない語や、語の一部は消さない")
    func keepsWords() {
        #expect(FillerRemover.remove(fillers, from: "あの件は明日です。") == "あの件は明日です。")
        #expect(FillerRemover.remove(fillers, from: "ええ、そうです。") == "ええ、そうです。")
    }

    @Test("文の途中で読点が続かないつなぎ言葉は消さない")
    func keepsMidSentence() {
        #expect(FillerRemover.remove(fillers, from: "それはえーと思います") == "それはえーと思います")
    }
}

@Suite("置き換え")
struct TermReplacerTests {
    let replacer = TermReplacer(entries: [
        entry("Claude Code", from: ["クロードコード", "クラウドコード", "cloud code"]),
        entry("Claude", from: ["クロード"]),
        entry("GitHub", from: ["github"]),
        entry("静的", from: ["性的"])
    ])

    @Test("カタカナの置き換え元を、正しい表記に直す")
    func katakana() {
        #expect(replacer.replace("クロードコードで直して") == "Claude Codeで直して")
    }

    @Test("中黒や空白で区切られたカタカナにも当てる")
    func katakanaWithSeparators() {
        #expect(replacer.replace("クロード・コードで直して") == "Claude Codeで直して")
    }

    @Test("前後がカタカナや長音なら置き換えない")
    func katakanaBoundary() {
        #expect(replacer.replace("スーパークロードコード") == "スーパークロードコード")
        #expect(replacer.replace("クロードー") == "クロードー")
    }

    @Test("英字は大文字小文字を区別せず、前後が英数字なら置き換えない")
    func latin() {
        #expect(replacer.replace("Cloud Code を開く") == "Claude Code を開く")
        #expect(replacer.replace("Github と githubx") == "GitHub と githubx")
    }

    @Test("長い置き換え元を先に当て、中の短い語は二重に直さない")
    func longestFirst() {
        #expect(replacer.replace("クロードとクロードコード") == "ClaudeとClaude Code")
    }

    @Test("英字とカタカナが混ざった聞き違いも、英字の公式の表記に直す")
    func mixed() {
        let replacer = TermReplacer(entries: [
            entry("Vitest", from: ["Bテスト"]),
            entry("GraphQL", from: ["グラフQL"])
        ])
        #expect(replacer.replace("いま B テストの設定を見直す") == "いま Vitestの設定を見直す")
        #expect(replacer.replace("グラフ QL のスキーマ") == "GraphQL のスキーマ")
        #expect(TermReplacer.kind(of: "Bテスト") == .mixed)
    }

    @Test("混ざった置き換え元も、端の字の種類で境目を決める")
    func mixedBoundary() {
        let replacer = TermReplacer(entries: [entry("Vitest", from: ["Bテスト"])])
        #expect(replacer.replace("ABテストを回す") == "ABテストを回す")
        #expect(replacer.replace("Bテストケース") == "Bテストケース")
    }

    @Test("漢字の置き換え元は使わない(同音異義語はヒントだけ)")
    func kanjiIsIgnored() {
        #expect(replacer.replace("性的解析") == "性的解析")
        #expect(TermReplacer.kind(of: "性的") == .unsupported)
    }
}

@Suite("和欧間スペース")
struct WaObunSpacingTests {
    @Test("日本語と英字の語のあいだに空白を入れる")
    func insertsSpaces() {
        #expect(WaObunSpacing.apply("Claude Codeで、Next.jsのPRを見る") == "Claude Code で、Next.js の PR を見る")
    }

    @Test("数字だけの語と約物の前後には入れない")
    func skipsNumbersAndPunctuation() {
        #expect(WaObunSpacing.apply("15時に3つ、約0.12ドル。") == "15時に3つ、約0.12ドル。")
        #expect(WaObunSpacing.apply("「PR」を") == "「PR」を")
    }

    @Test("すでに空白があれば増やさない")
    func keepsExistingSpace() {
        #expect(WaObunSpacing.apply("Slack で声をかける") == "Slack で声をかける")
    }
}

@Suite("整える流れ")
struct TextShaperTests {
    @Test("整える → 置き換え → 和欧間スペースの順に流す")
    func pipeline() {
        let dictionary = DictionaryFile(version: 1, entries: [entry("Claude Code", from: ["クロードコード"])], fillers: ["えーと"])
        let shaper = TextShaper(dictionary: dictionary)
        #expect(shaper.shape("えーと、クロード・コードで ＰＲ を 見て") == "Claude Code で PR を見て")
    }

    @Test("和欧間スペースを切ると、空白は入れない")
    func spacingOff() {
        let dictionary = DictionaryFile(version: 1, entries: [entry("Claude Code", from: ["クロードコード"])], fillers: [])
        let shaper = TextShaper(dictionary: dictionary, waObunSpacing: false)
        #expect(shaper.shape("クロードコードで見て") == "Claude Codeで見て")
    }
}

@Suite("ヒントの選び方")
struct HintSelectorTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let day = 24.0 * 60 * 60
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    @Test("固定した語 → 追加して14日以内の語 → よく使う語の順に選ぶ")
    func order() {
        let entries = [entry("Slack"), entry("Vitest"), entry("Biome"), entry("Codex", pinned: true)]
        var used = TermUsage()
        used.record(5, at: now.addingTimeInterval(-day), calendar: calendar)
        let usage = [
            "Slack": used,
            "Biome": TermUsage(addedAt: now.addingTimeInterval(-3 * day))
        ]
        let selected = HintSelector.select(entries: entries, usage: usage, now: now, calendar: calendar)
        #expect(selected == ["Codex", "Biome", "Slack", "Vitest"])
    }

    @Test("上限を超えたら切り、ヒントに使わない語は入れない")
    func limitAndHintFlag() {
        let entries = [entry("Slack"), entry("Notion", hint: false), entry("Jira")]
        #expect(HintSelector.select(entries: entries, usage: [:], now: now, limit: 1, calendar: calendar) == ["Slack"])
        #expect(!HintSelector.select(entries: entries, usage: [:], now: now, calendar: calendar).contains("Notion"))
    }

    @Test("30日より前に使った回数は数えない")
    func countWindow() {
        var usage = TermUsage()
        usage.record(3, at: now.addingTimeInterval(-40 * day), calendar: calendar)
        usage.record(2, at: now, calendar: calendar)
        #expect(usage.count(days: 30, now: now, calendar: calendar) == 2)
    }

    @Test("使われた回数は長い語から数え、中の短い語は数えない")
    func occurrences() {
        let counts = HintSelector.occurrences(of: ["Claude", "Claude Code"], in: "Claude Code と Claude で比べる")
        #expect(counts == ["Claude Code": 1, "Claude": 1])
    }
}
