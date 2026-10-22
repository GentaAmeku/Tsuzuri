import Testing
@testable import TsuzuriCore

@Suite("ふつうの英単語の案")
struct PlainEnglishTests {
    let words: Set<String> = ["error", "preview", "feedback", "server", "component", "real", "time", "claude", "code", "storybook"]
    func isWord(_ word: String) -> Bool { words.contains(word.lowercased()) }

    @Test("1語の英単語と、小文字だけの複数語はふつうの英単語")
    func plain() {
        #expect(PlainEnglish.isPlain("error", isEnglishWord: isWord))
        #expect(PlainEnglish.isPlain("Preview", isEnglishWord: isWord))
        #expect(PlainEnglish.isPlain("server component", isEnglishWord: isWord))
        #expect(PlainEnglish.isPlain("Real-time", isEnglishWord: isWord))
        #expect(PlainEnglish.isPlain("Storybook", isEnglishWord: isWord))
    }

    @Test("途中の大文字・略語・記号・各語の頭が大文字の複数語・辞書に無い語は名前")
    func names() {
        #expect(!PlainEnglish.isPlain("TanStack", isEnglishWord: { _ in true }))
        #expect(!PlainEnglish.isPlain("CI", isEnglishWord: { _ in true }))
        #expect(!PlainEnglish.isPlain("Next.js", isEnglishWord: { _ in true }))
        #expect(!PlainEnglish.isPlain("Claude Code", isEnglishWord: isWord))
        #expect(!PlainEnglish.isPlain("Vercel", isEnglishWord: isWord))
    }

    @Test("日本語の字の語を英単語に訳しただけの案は捨て、英字の綴りの直しは残す")
    func filter() {
        let found = CandidateFilter.candidates(
            from: [Suspect(heard: "フィードバック", surfaces: ["feedback"]), Suspect(heard: "Storibook", surfaces: ["Storybook"])],
            in: "フィードバックを Storibook に書く", dictionary: [], isEnglishWord: isWord
        )
        #expect(found.map(\.heard) == ["Storibook"])
    }
}

@Suite("辞書の語に読みが近い語")
struct NearDictionaryTests {
    let entries = [
        DictionaryEntry(surface: "Soniox", from: ["ソニオックス"], hint: true, pinned: false, source: .manual),
        DictionaryEntry(surface: "Claude Code", from: ["クロードコード"], hint: true, pinned: false, source: .manual),
        DictionaryEntry(surface: "既定", from: [], hint: true, pinned: false, source: .manual),
    ]

    @Test("読みが近いのに字が違う語を、辞書の語への直しとして挙げる")
    func nearReading() {
        #expect(NearDictionary.suspects(marked: ["ソニックス"], entries: entries) == [Suspect(heard: "ソニックス", surfaces: ["Soniox"])])
        #expect(NearDictionary.suspects(marked: ["クロードコーデ"], entries: entries) == [Suspect(heard: "クロードコーデ", surfaces: ["Claude Code"])])
    }

    @Test("置き換え元と同じ語・遠い語・短い語は挙げない")
    func skips() {
        #expect(NearDictionary.suspects(marked: ["ソニオックス", "スケジュール", "ソニ"], entries: entries).isEmpty)
    }
}
