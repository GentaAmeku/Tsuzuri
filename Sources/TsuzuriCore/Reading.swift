import Foundation

/// 日本語の読み。macOS の `CFStringTokenizer` でローマ字にし、読みの近さを出す
public enum Reading {
    /// ローマ字の読み(空白なし・小文字)。読めない字はそのまま残す
    public static func romaji(_ text: String) -> String {
        let source = text as CFString
        let tokenizer = CFStringTokenizerCreate(nil, source, CFRange(location: 0, length: CFStringGetLength(source)), kCFStringTokenizerUnitWordBoundary, Locale(identifier: "ja") as CFLocale)
        var result = ""
        var type = CFStringTokenizerAdvanceToNextToken(tokenizer)
        while type != [] {
            if let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String {
                result += latin
            } else {
                let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
                result += (text as NSString).substring(with: NSRange(location: range.location, length: range.length))
            }
            type = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }
        return result.lowercased().filter { !$0.isWhitespace }
    }

    /// 読みの近さ。1 −(編集距離 ÷ 長い方の文字数)。1が同じ読み
    public static func similarity(_ a: String, _ b: String) -> Double {
        let left = Array(romaji(a))
        let right = Array(romaji(b))
        let length = max(left.count, right.count)
        guard length > 0 else { return 1 }
        return 1 - Double(CharacterErrorRate.editDistance(left, right)) / Double(length)
    }
}
