import AppKit

/// 英単語かどうかを、macOS の綴りの辞書(NSSpellChecker)で見る。日本語の語を英単語に訳しただけの案を捨てるのに使う
public enum EnglishWords {
    @MainActor
    public static func isWord(_ word: String) -> Bool {
        let range = NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0, language: "en", wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
        return range.location == NSNotFound
    }
}
