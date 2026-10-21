/// 辞書の候補の洗い出しの1段目(拾う)。整えたあとの文を字の種類で区切り、怪しい語に印を付ける
/// (設計書「拾う: 字の種類の規則で、怪しい語に印を付ける」)。
/// 印は Apple Foundation Models へ渡す手がかりで、印の付いた語をそのまま候補にはしない
///
/// - カタカナが3字以上続く語(クロードコード)
/// - 英字とカタカナが混ざる語(B テスト)。間に空白や中黒があっても1語にまとめる
/// - 辞書に無い英字の語(Cloud Code)。空白で続く英字の語は1語にまとめる
/// - 漢字・かなの語は拾わない(Apple Foundation Models が文脈から拾う)
public enum SuspectMarker {
    public static let minimumKatakanaLength = 3

    /// 印を付けた語。文に出た順で、重複は除く。辞書の語(置き換えで直した箇所を含む)は調べない
    public static func mark(_ text: String, dictionary surfaces: [String]) -> [String] {
        let characters = Array(text)
        let masked = mask(characters, surfaces: surfaces)
        var marked: [String] = []
        for group in groups(characters, masked: masked) where isSuspicious(group, in: characters) {
            let word = String(characters[group.start..<group.end])
            if !marked.contains(word) { marked.append(word) }
        }
        return marked
    }

    enum PieceKind {
        case katakana
        case latin
    }

    struct Piece {
        let kind: PieceKind
        let start: Int
        let end: Int
    }

    struct Group {
        var pieces: [Piece]
        var start: Int { pieces.first!.start }
        var end: Int { pieces.last!.end }
    }

    /// 辞書の語が出た箇所を、調べない印にする
    static func mask(_ characters: [Character], surfaces: [String]) -> [Bool] {
        var masked = Array(repeating: false, count: characters.count)
        for surface in surfaces.map(Array.init).filter({ !$0.isEmpty }).sorted(by: { $0.count > $1.count }) {
            var index = 0
            while index + surface.count <= characters.count {
                if characters[index..<(index + surface.count)].elementsEqual(surface) {
                    for i in index..<(index + surface.count) { masked[i] = true }
                    index += surface.count
                } else {
                    index += 1
                }
            }
        }
        return masked
    }

    /// カタカナの続きと英字の続き(英字・数字と、語の中の「.-_+#」)
    static func pieces(_ characters: [Character], masked: [Bool]) -> [Piece] {
        var pieces: [Piece] = []
        var index = 0
        while index < characters.count {
            guard !masked[index] else { index += 1; continue }
            let character = characters[index]
            if character.isKatakana {
                var end = index + 1
                while end < characters.count, !masked[end], characters[end].isKatakana { end += 1 }
                pieces.append(Piece(kind: .katakana, start: index, end: end))
                index = end
            } else if character.isASCIIAlphanumeric {
                var end = index + 1
                while end < characters.count, !masked[end] {
                    let next = characters[end]
                    if next.isASCIIAlphanumeric {
                        end += 1
                    } else if ".-_+#".contains(next), end + 1 < characters.count, !masked[end + 1], characters[end + 1].isASCIIAlphanumeric {
                        end += 2
                    } else if "+#".contains(next) {
                        // C++・C# のように語の終わりに付く記号
                        end += 1
                    } else {
                        break
                    }
                }
                pieces.append(Piece(kind: .latin, start: index, end: end))
                index = end
            } else {
                index += 1
            }
        }
        return pieces
    }

    /// 隣り合う(間が空白か中黒の1字だけの)切れ端をまとめる。カタカナどうし・英字どうし・英字とカタカナをまとめる
    static func groups(_ characters: [Character], masked: [Bool]) -> [Group] {
        var groups: [Group] = []
        for piece in pieces(characters, masked: masked) {
            if var last = groups.last, joinable(characters, last.pieces.last!, piece) {
                last.pieces.append(piece)
                groups[groups.count - 1] = last
            } else {
                groups.append(Group(pieces: [piece]))
            }
        }
        return groups
    }

    static func joinable(_ characters: [Character], _ left: Piece, _ right: Piece) -> Bool {
        let gap = right.start - left.end
        if gap == 0 { return true }
        guard gap == 1 else { return false }
        let separator = characters[left.end]
        return separator == " " || separator == "・"
    }

    static func isSuspicious(_ group: Group, in characters: [Character]) -> Bool {
        let kinds = Set(group.pieces.map(\.kind))
        if kinds.count > 1 { return true }
        let length = group.pieces.reduce(0) { $0 + $1.end - $1.start }
        switch kinds.first! {
        case .katakana:
            return length >= minimumKatakanaLength
        case .latin:
            // 数字だけの語(3・15)は拾わない
            return characters[group.start..<group.end].contains(where: \.isASCIILetter)
        }
    }
}

