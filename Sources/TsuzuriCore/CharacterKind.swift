/// 整える・置き換える・空白を入れるときに使う、字の種類
extension Character {
    /// カタカナ(長音「ー」を含む。中黒「・」は含めない)
    var isKatakana: Bool {
        guard let scalar = unicodeScalars.first, unicodeScalars.count == 1 else { return false }
        switch scalar.value {
        case 0x30A1...0x30FA, 0x30FC...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F: return true
        default: return false
        }
    }

    var isHiragana: Bool {
        guard let scalar = unicodeScalars.first, unicodeScalars.count == 1 else { return false }
        return (0x3041...0x309F).contains(scalar.value)
    }

    var isKanji: Bool {
        guard let scalar = unicodeScalars.first, unicodeScalars.count == 1 else { return false }
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x3005, 0x3006: return true
        default: return false
        }
    }

    /// 日本語の字(かな・漢字)
    var isJapaneseLetter: Bool { isHiragana || isKatakana || isKanji }

    /// 日本語の約物(句読点・かっこなど)
    var isJapanesePunctuation: Bool {
        "、。「」『』（）！？：；〜…【】・".contains(self)
    }

    var isASCIILetter: Bool { isASCII && isLetter }
    var isASCIIAlphanumeric: Bool { isASCII && (isLetter || isNumber) }
}
