import Foundation
import NaturalLanguage

/// 認識の出力を、決めた規則だけで整える(設計書「日本語の精度を上げる4つの層」の3と4)。
/// 流す順番は、整える(正規化・つなぎ言葉)→ 置き換え → 和欧間スペース。文章を書き換えることはしない
public struct TextShaper: Sendable {
    public var replacer: TermReplacer
    public var fillers: [String]
    /// 日本語と英字のあいだに半角スペースを入れるか(段階2の設定で切り替える。既定は入れる)
    public var waObunSpacing: Bool

    public init(dictionary: DictionaryFile, waObunSpacing: Bool = true) {
        self.replacer = TermReplacer(entries: dictionary.entries)
        self.fillers = dictionary.fillers
        self.waObunSpacing = waObunSpacing
    }

    public func shape(_ text: String) -> String {
        var shaped = Normalizer.normalize(text)
        shaped = FillerRemover.remove(fillers, from: shaped)
        shaped = replacer.replace(shaped)
        if waObunSpacing {
            shaped = WaObunSpacing.apply(shaped)
        }
        return shaped
    }

    /// 話している途中の文字を、貼る文字と同じ規則で整える。確定した文字とまだ変わりうる文字をつないで整え、
    /// 整えたあとの文字のうち、確定した文字にあたる頭の字数も返す(表示で色を分けるため)。
    /// 確定した文字だけを整えたものと頭が同じところまでを、確定した字とみなす(置き換えが境目をまたぐときは、またいだ語から後ろを薄く出す)
    public func shapePartial(final: String, tentative: String) -> (text: String, finalLength: Int) {
        let all = shape(final + tentative)
        guard !tentative.isEmpty else { return (all, all.count) }
        let shapedFinal = Array(shape(final))
        let common = zip(Array(all), shapedFinal).prefix { $0 == $1 }.count
        return (all, common)
    }
}

/// 正規化: 全角の英数字を半角に、全角の「,.」を「、。」に、日本語の字の間の空白を消す
public enum Normalizer {
    public static func normalize(_ text: String) -> String {
        let halfWidth = String(text.map(halfWidthAlphanumeric))
        let characters = Array(halfWidth)
        var result: [Character] = []
        for (index, character) in characters.enumerated() {
            let previous = index > 0 ? characters[index - 1] : nil
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            switch character {
            case "，", "．":
                // 数字や英字に挟まれた「．」「，」は小数点や桁の区切り(0．12 → 0.12)
                let between = previous?.isASCIIAlphanumeric == true && next?.isASCIIAlphanumeric == true
                if between {
                    result.append(character == "，" ? "," : ".")
                } else {
                    result.append(character == "，" ? "、" : "。")
                }
            case " ", "\u{3000}":
                // 日本語の字・約物どうしの間の空白は消す。英字の前後の空白は残す(連続は1つに)
                let left = result.last
                if left == nil || left == " " { continue }
                if let left, isJapanese(left), let right = nextNonSpace(characters, after: index), isJapanese(right) { continue }
                result.append(" ")
            default:
                result.append(character)
            }
        }
        while result.last == " " { result.removeLast() }
        return String(result)
    }

    static func isJapanese(_ character: Character) -> Bool {
        character.isJapaneseLetter || character.isJapanesePunctuation
    }

    static func nextNonSpace(_ characters: [Character], after index: Int) -> Character? {
        characters[(index + 1)...].first { $0 != " " && $0 != "\u{3000}" }
    }

    /// 全角の英数字(Ａ〜Ｚ・ａ〜ｚ・０〜９)だけを半角にする。記号は変えない
    static func halfWidthAlphanumeric(_ character: Character) -> Character {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return character }
        switch scalar.value {
        case 0xFF10...0xFF19, 0xFF21...0xFF3A, 0xFF41...0xFF5A:
            return Character(UnicodeScalar(scalar.value - 0xFEE0)!)
        default:
            return character
        }
    }
}

/// つなぎ言葉を消す。登録した語のうち、文頭か読点「、」の直前にあり、単語の区切りと一致するものだけ消す
/// (「あのー、」は消し、「あの件」は消さない)
public enum FillerRemover {
    static let sentenceEnds: Set<Character> = ["。", "！", "？", "!", "?", "\n"]

    public static func remove(_ fillers: [String], from text: String) -> String {
        guard !fillers.isEmpty, !text.isEmpty else { return text }
        let boundaries = wordBoundaries(of: text)
        var removals: [Range<String.Index>] = []
        // 長い語から当てる(「えーと」を「えー」より先に)
        for filler in fillers.sorted(by: { $0.count > $1.count }) where !filler.isEmpty {
            var searchStart = text.startIndex
            while let found = text.range(of: filler, range: searchStart..<text.endIndex) {
                searchStart = found.upperBound
                guard boundaries.contains(found.lowerBound), boundaries.contains(found.upperBound),
                      !removals.contains(where: { $0.overlaps(found) }) else { continue }
                let followedByComma = text[found.upperBound...].first == "、"
                guard followedByComma || isSentenceStart(text, at: found.lowerBound) else { continue }
                var end = followedByComma ? text.index(after: found.upperBound) : found.upperBound
                while end < text.endIndex, text[end] == " " { end = text.index(after: end) }
                removals.append(found.lowerBound..<end)
            }
        }
        var result = text
        for range in removals.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            result.removeSubrange(range)
        }
        return result
    }

    static func isSentenceStart(_ text: String, at index: String.Index) -> Bool {
        let before = text[..<index].reversed().first { $0 != " " }
        return before == nil || sentenceEnds.contains(before!)
    }

    /// NLTokenizer で分けた語の境目
    static func wordBoundaries(of text: String) -> Set<String.Index> {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.setLanguage(.japanese)
        tokenizer.string = text
        var boundaries: Set<String.Index> = [text.startIndex, text.endIndex]
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            boundaries.insert(range.lowerBound)
            boundaries.insert(range.upperBound)
            return true
        }
        return boundaries
    }
}

/// 和欧間スペース: 日本語の字と、英字を含む語のあいだに半角スペースを入れる。
/// 数字だけの語(3つ・15時・0.12ドル)には入れない
public enum WaObunSpacing {
    /// 英数字の語として続けて読む字
    static func isWordCharacter(_ character: Character) -> Bool {
        character.isASCIIAlphanumeric || "._+#-/".contains(character)
    }

    public static func apply(_ text: String) -> String {
        let characters = Array(text)
        guard characters.count > 1 else { return text }
        var result: [Character] = [characters[0]]
        for index in 1..<characters.count {
            let left = characters[index - 1]
            let right = characters[index]
            if left.isJapaneseLetter, isWordCharacter(right), wordHasLetter(characters, from: index, forward: true) {
                result.append(" ")
            } else if isWordCharacter(left), right.isJapaneseLetter, wordHasLetter(characters, from: index - 1, forward: false) {
                result.append(" ")
            }
            result.append(right)
        }
        return String(result)
    }

    /// `index` から前か後ろへ続く英数字の語に、英字が1つでもあるか
    static func wordHasLetter(_ characters: [Character], from index: Int, forward: Bool) -> Bool {
        var position = index
        while characters.indices.contains(position), isWordCharacter(characters[position]) {
            if characters[position].isASCIILetter { return true }
            position += forward ? 1 : -1
        }
        return false
    }
}
