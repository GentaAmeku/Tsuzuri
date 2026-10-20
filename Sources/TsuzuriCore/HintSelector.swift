import Foundation

/// 語ごとの使われ方(`usage.json` に残す。アプリだけが書く)
public struct TermUsage: Codable, Sendable, Equatable {
    /// 辞書に足した日時。追加したばかりの語を先にヒントへ入れるため
    public var addedAt: Date?
    /// 日ごと(yyyy-MM-dd)の使われた回数
    public var daily: [String: Int]
    public var lastUsedAt: Date?

    public init(addedAt: Date? = nil, daily: [String: Int] = [:], lastUsedAt: Date? = nil) {
        self.addedAt = addedAt
        self.daily = daily
        self.lastUsedAt = lastUsedAt
    }

    public mutating func record(_ count: Int, at date: Date, calendar: Calendar = .current) {
        guard count > 0 else { return }
        daily[Self.dayKey(date, calendar: calendar), default: 0] += count
        lastUsedAt = date
    }

    /// `now` までの `days` 日間に使われた回数
    public func count(days: Int, now: Date, calendar: Calendar = .current) -> Int {
        (0..<days).reduce(0) { total, offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { return total }
            return total + (daily[Self.dayKey(day, calendar: calendar)] ?? 0)
        }
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Soniox に毎回渡す語を選ぶ(設計書「語のヒントは、費用と上限があるので上位から選ぶ」)。
/// 本人が固定した語 → 追加して14日以内の語 → 30日間に使われた回数が多い語、の順に上限まで
public enum HintSelector {
    public static let defaultLimit = 100
    public static let recentDays = 14
    public static let countDays = 30

    public static func select(
        entries: [DictionaryEntry],
        usage: [String: TermUsage],
        now: Date,
        limit: Int = defaultLimit,
        calendar: Calendar = .current
    ) -> [String] {
        let candidates = entries.filter(\.hint)
        let recentLimit = now.addingTimeInterval(-Double(recentDays) * 24 * 60 * 60)
        let pinned = candidates.filter(\.pinned)
        let recent = candidates
            .filter { !$0.pinned }
            .compactMap { entry in usage[entry.surface]?.addedAt.map { (entry, $0) } }
            .filter { $0.1 >= recentLimit }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        // 回数が同じなら、最後に使われたのが新しい順、それも同じなら辞書の順
        let ranked = candidates.enumerated().sorted { lhs, rhs in
            let left = usage[lhs.element.surface], right = usage[rhs.element.surface]
            let leftCount = left?.count(days: countDays, now: now, calendar: calendar) ?? 0
            let rightCount = right?.count(days: countDays, now: now, calendar: calendar) ?? 0
            if leftCount != rightCount { return leftCount > rightCount }
            let leftLast = left?.lastUsedAt ?? .distantPast, rightLast = right?.lastUsedAt ?? .distantPast
            if leftLast != rightLast { return leftLast > rightLast }
            return lhs.offset < rhs.offset
        }.map(\.element)
        var selected: [String] = []
        for entry in pinned + recent + ranked where !selected.contains(entry.surface) {
            guard selected.count < limit else { break }
            selected.append(entry.surface)
        }
        return selected
    }

    /// 整えたあとの文字に、辞書の語が何回出たか(使われた回数として数える)。
    /// 長い語から数え、その中の短い語(Claude Code の中の Claude)は数えない
    public static func occurrences(of surfaces: [String], in text: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        var taken: [Range<String.Index>] = []
        for surface in Set(surfaces).sorted(by: { $0.count > $1.count }) where !surface.isEmpty {
            var start = text.startIndex
            while let found = text.range(of: surface, range: start..<text.endIndex) {
                start = found.upperBound
                guard !taken.contains(where: { $0.overlaps(found) }) else { continue }
                taken.append(found)
                counts[surface, default: 0] += 1
            }
        }
        return counts
    }
}
