import Foundation
import FoundationModels
import TsuzuriCore

/// 辞書に語を手で足すとき、Apple Foundation Models にカタカナの読みを出させ、置き換え元の候補にする
/// (設計書「辞書の形と使い方」。段階2)。判定は Mac の中で終わり、外へは何も送らない
public enum ReadingSuggester {
    @Generable
    struct Proposal {
        @Guide(description: "その表記を日本人が会話で読み上げたときのカタカナの読み。よく使われる読み方から順に。別の読み方が無ければ1つだけ", .maximumCount(2))
        var readings: [String]
    }

    static let instructions = """
    あなたは日本語の音声入力の辞書づくりを手伝う。英語の製品名・ライブラリ名・技術用語を、日本人のエンジニアが会話で読み上げるときのカタカナに直す。
    読みはカタカナと長音「ー」だけで書き、空白や中黒は入れない。略語はアルファベットを1字ずつ読む。英単語は、ふつうの英語の発音をカタカナにする。
    例: Next.js → ネクストジェイエス / GitHub → ギットハブ / ESLint → イーエスリント、エスリント / PR → ピーアール / Playwright → プレイライト / TypeScript → タイプスクリプト / Vercel → バーセル、ヴァーセル
    """

    /// Apple Intelligence が有効で、端末の中の LLM を使えるか
    public static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    /// 読みの候補。カタカナだけのもの(置き換えに使えるもの)に絞り、すでにある置き換え元は除く
    public static func suggest(for surface: String, excluding existing: [String] = []) async throws -> [String] {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(
            to: "「\(surface)」の読み",
            generating: Proposal.self,
            options: GenerationOptions(sampling: .greedy)
        )
        var seen = Set(existing)
        return response.content.readings
            .map { $0.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "・", with: "") }
            // 数を埋めるために長音を重ねたもの(タンスタックーー)は捨てる
            .filter { !$0.contains("ーー") }
            .filter { TermReplacer.kind(of: $0) == .katakana && seen.insert(trimmingLongVowels($0)).inserted }
    }

    /// 末尾の長音を除いた形。「タンスタック」と「タンスタックー」を同じ読みとみなすため
    static func trimmingLongVowels(_ reading: String) -> String {
        var trimmed = reading
        while trimmed.hasSuffix("ー") { trimmed.removeLast() }
        return trimmed
    }
}
