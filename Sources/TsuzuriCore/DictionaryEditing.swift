import Foundation

/// 辞書の編集画面で使う処理。置き換え元の欄の区切り方と、保存する前の点検
public enum DictionaryEditing {
    /// 「、」「,」「，」・改行で区切った欄を、語の一覧にする。前後の空白を除き、空と重複を捨てる
    public static func parseList(_ text: String) -> [String] {
        var seen: Set<String> = []
        return text
            .split(whereSeparator: { "、,，\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    public static func joinList(_ items: [String]) -> String {
        items.joined(separator: "、")
    }

    public enum Issue: Equatable, Sendable {
        /// 表記が空の行(保存できない)
        case emptySurface(row: Int)
        /// 同じ表記の行が2つ以上ある(保存できない)
        case duplicateSurface(String)
        /// 置き換えに使えない置き換え元(漢字・ひらがなを含む)。ヒントには残る
        case unusableFrom(surface: String, from: String)
        /// 別の語の表記を、置き換え元にしている(保存はできるが、その語を書き換えてしまう)
        case fromIsAnotherSurface(surface: String, from: String)

        /// 保存を止めるか
        public var blocksSaving: Bool {
            switch self {
            case .emptySurface, .duplicateSurface: true
            case .unusableFrom, .fromIsAnotherSurface: false
            }
        }

        public var message: String {
            switch self {
            case let .emptySurface(row): "\(row + 1)行目の表記が空です"
            case let .duplicateSurface(surface): "「\(surface)」が2つあります"
            case let .unusableFrom(surface, from): "「\(surface)」の置き換え元「\(from)」は漢字・ひらがなを含むので、置き換えに使いません"
            case let .fromIsAnotherSurface(surface, from): "「\(surface)」の置き換え元「\(from)」は、別の語の表記です。その語まで書き換えます"
            }
        }
    }

    public static func issues(_ entries: [DictionaryEntry]) -> [Issue] {
        var issues: [Issue] = []
        var counts: [String: Int] = [:]
        for (row, entry) in entries.enumerated() {
            let surface = entry.surface.trimmingCharacters(in: .whitespaces)
            if surface.isEmpty {
                issues.append(.emptySurface(row: row))
            } else {
                counts[surface, default: 0] += 1
            }
        }
        for (surface, count) in counts.sorted(by: { $0.key < $1.key }) where count > 1 {
            issues.append(.duplicateSurface(surface))
        }
        let surfaces = Set(entries.map(\.surface))
        for entry in entries {
            for from in entry.from {
                if TermReplacer.kind(of: from) == .unsupported {
                    issues.append(.unusableFrom(surface: entry.surface, from: from))
                } else if from != entry.surface, surfaces.contains(from) {
                    issues.append(.fromIsAnotherSurface(surface: entry.surface, from: from))
                }
            }
        }
        return issues
    }

    /// 1行の欄から語を足したときの結果
    public enum QuickAddResult: Equatable, Sendable {
        /// 新しい語として足した
        case added
        /// もうある語に、聞き違い・読みだけを足した
        case extended
        /// もうある語で、足すものが無かった
        case unchanged
        /// 語が空
        case empty
    }

    /// 窓の上の1行の欄から語を足す(2026-10-22。打って Return で足す)。
    /// もうある語なら、聞き違い・読みだけを重ならないように足す。新しい語は手で足した語として、ヒントにする
    public static func quickAdd(surface: String, misheard: String, to entries: [DictionaryEntry]) -> (entries: [DictionaryEntry], result: QuickAddResult) {
        let surface = surface.trimmingCharacters(in: .whitespaces)
        guard !surface.isEmpty else { return (entries, .empty) }
        let readings = parseList(misheard).filter { $0 != surface }
        var entries = entries
        if let index = entries.firstIndex(where: { $0.surface == surface }) {
            let entry = entries[index]
            let added = readings.filter { !entry.from.contains($0) }
            guard !added.isEmpty else { return (entries, .unchanged) }
            entries[index] = DictionaryEntry(surface: entry.surface, from: entry.from + added, hint: entry.hint, pinned: entry.pinned, source: entry.source)
            return (entries, .extended)
        }
        entries.append(DictionaryEntry(surface: surface, from: readings, hint: true, pinned: false, source: .manual))
        return (entries, .added)
    }
}
