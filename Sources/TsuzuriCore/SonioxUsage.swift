import Foundation

/// 月ごとの Soniox の使用量(`soniox-usage.json`。段階4)。履歴は直近100件しか残らないので、別のファイルで月ごとに足していく
/// (設計書「費用の表示は段階4で足す」)
public struct SonioxUsageFile: Codable, Sendable, Equatable {
    public var version: Int
    /// 月(yyyy-MM)ごとの合計
    public var months: [String: SonioxMonth]

    public init(version: Int = 1, months: [String: SonioxMonth] = [:]) {
        self.version = version
        self.months = months
    }

    /// Soniox で1回認識したことを足す
    public func adding(audioSeconds: Double, hintCharacters: Int, at date: Date, calendar: Calendar = .current) -> SonioxUsageFile {
        var file = self
        file.months[Self.monthKey(for: date, calendar: calendar), default: SonioxMonth()].add(audioSeconds: audioSeconds, hintCharacters: hintCharacters)
        return file
    }

    public func month(of date: Date, calendar: Calendar = .current) -> SonioxMonth {
        months[Self.monthKey(for: date, calendar: calendar)] ?? SonioxMonth()
    }

    public static func monthKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }
}

/// 1か月の合計
public struct SonioxMonth: Codable, Sendable, Equatable {
    public var sessions: Int
    public var audioSeconds: Double
    /// 渡した語のヒントの字数(語の字数の和)
    public var hintCharacters: Int

    public init(sessions: Int = 0, audioSeconds: Double = 0, hintCharacters: Int = 0) {
        self.sessions = sessions
        self.audioSeconds = audioSeconds
        self.hintCharacters = hintCharacters
    }

    public mutating func add(audioSeconds: Double, hintCharacters: Int) {
        sessions += 1
        self.audioSeconds += audioSeconds
        self.hintCharacters += hintCharacters
    }
}

/// Soniox の代金の目安。音声の時間の代金と、語のヒント(入力テキスト)の代金の和を、幅で出す
/// (設計書「語のヒントは、費用と上限があるので上位から選ぶ」の目安。本人が使用量の画面で実際の額を見たら直す)
public struct SonioxPricing: Sendable, Equatable {
    /// 音声1時間あたりのドル(認識した文字の代金を含む)
    public var dollarsPerAudioHour: Double
    /// 入力テキスト100万トークンあたりのドル
    public var dollarsPerMillionTextTokens: Double
    /// 1字あたりのトークン数の幅(資料によって0.3〜0.8)
    public var tokensPerCharacter: ClosedRange<Double>

    public init(dollarsPerAudioHour: Double = 0.12, dollarsPerMillionTextTokens: Double = 4, tokensPerCharacter: ClosedRange<Double> = 0.3...0.8) {
        self.dollarsPerAudioHour = dollarsPerAudioHour
        self.dollarsPerMillionTextTokens = dollarsPerMillionTextTokens
        self.tokensPerCharacter = tokensPerCharacter
    }

    /// 1か月の代金の幅(ドル)
    public func estimate(_ month: SonioxMonth) -> ClosedRange<Double> {
        let audio = month.audioSeconds / 3600 * dollarsPerAudioHour
        let text = { (tokens: Double) in Double(month.hintCharacters) * tokens / 1_000_000 * dollarsPerMillionTextTokens }
        return (audio + text(tokensPerCharacter.lowerBound))...(audio + text(tokensPerCharacter.upperBound))
    }

    /// メニューに出す1行。例: 「今月の Soniox: 1時間23分・推定 0.8〜1.1ドル」
    public func menuLine(_ month: SonioxMonth) -> String {
        let range = estimate(month)
        return "今月の Soniox: \(Self.duration(month.audioSeconds))・推定 \(Self.dollars(range.lowerBound))〜\(Self.dollars(range.upperBound))ドル"
    }

    static func duration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes)分" }
        return "\(minutes / 60)時間\(minutes % 60)分"
    }

    /// 1ドル未満は小数2桁、それ以上は小数1桁
    static func dollars(_ value: Double) -> String {
        String(format: value < 1 ? "%.2f" : "%.1f", value)
    }
}
