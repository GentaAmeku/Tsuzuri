import Foundation
import FoundationModels
import TsuzuriCore

/// 辞書の候補の洗い出しの2段目(挙げる)。文全体と印の付いた語を Apple Foundation Models に渡し、
/// 誤って認識したらしい語と表記の案を答えさせる(設計書「挙げる」)。Mac の中で終わり、外へは何も送らない
public enum SuspectScanner {
    @Generable
    enum SuspectKind {
        /// 製品名・サービス名・ライブラリ名・コマンド名など、本来は英字で書く固有の名前
        case productName
        /// 同じ読みの別の漢字
        case homophone
        /// それ以外(ふつうの語の言い換え・訳・書き下し)。候補にしない
        case other
    }

    @Generable
    struct SuspectAnswer {
        @Guide(description: "文の中にそのまま出てくる、誤って認識したらしい1語。助詞(の・で・を)は含めない")
        var heard: String
        @Guide(description: "誤りの種類")
        var kind: SuspectKind
        @Guide(description: "本来の表記の案。公式の大文字・小文字のとおりに書く。よく使われる表記から順に", .maximumCount(2))
        var surfaces: [String]
    }

    @Generable
    struct ScanAnswer {
        @Guide(description: "誤って認識したらしい語。無ければ空", .maximumCount(5))
        var suspects: [SuspectAnswer]
    }

    // 例には評価セット(eval/)の語を使わない。使うと測る数が甘くなる
    static let instructions = """
    あなたは日本語の音声入力の誤りを見つける。渡す文は、日本人のソフトウェアエンジニアが話した言葉を、音声認識が文字にしたもの。
    音声認識は、英語の製品名・ライブラリ名・技術用語をカタカナやひらがな、崩れた英字で出したり、同じ読みの別の漢字を出したりする。
    文の中から誤って認識したらしい語を挙げ、本来の表記の案を出す。
    - heard には、文の中の字をそのまま、1語だけ写す
    - 製品名・ライブラリ名・サービス名は、公式の英字の表記にする(kind は productName)。大文字・小文字も公式のとおりにする。例: ドッカーコンポーズ → Docker Compose / スーパーベース → Supabase / ぷりずま → Prisma / ギットラボ → GitLab / アイオーエス → iOS / Kubernetis → Kubernetes
    - 同じ読みの別の漢字は、文脈に合う漢字にする(kind は homophone)。例: 「処理が以上終了した」の「以上」→「異常」
    - 日本語の文章でふつうにカタカナや漢字で書く語は、誤りではない。英語に訳さない(ファイル → File、ユーザー → User、保存 → save は誤った直し)
    - 略語を書き下さない(API → Application Programming Interface は誤った直し)。語を足したり削ったりしない
    - 誤りが無ければ空にする
    印の付いた語は、怪しいかもしれない語の手がかり。印の無い語を挙げてもよく、印の付いた語でも誤りでなければ挙げない。
    """

    /// Apple Intelligence が有効で、端末の中の LLM を使えるか
    public static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    /// 洗い出しの結果。印は確かめ用(測定の表示)に返す
    public struct Outcome: Sendable {
        public let marked: [String]
        public let candidates: [SuggestionCandidate]
    }

    /// 拾う → 挙げる → 除く を通して、辞書の候補を出す。アプリと測定(tsuzuri-eval suggest)で同じ流れを使う
    public static func candidates(for text: String, dictionary surfaces: [String], settled: Set<DiscardedPair> = []) async throws -> Outcome {
        let marked = SuspectMarker.mark(text, dictionary: surfaces)
        let suspects = try await scan(text, marked: marked)
        return Outcome(
            marked: marked,
            candidates: CandidateFilter.candidates(from: suspects, in: text, dictionary: surfaces, marked: marked, discarded: settled)
        )
    }

    public static func scan(_ text: String, marked: [String]) async throws -> [Suspect] {
        let session = LanguageModelSession(instructions: instructions)
        let markedLine = marked.isEmpty ? "(なし)" : marked.joined(separator: "、")
        let response = try await session.respond(
            to: "文: \(text)\n印の付いた語: \(markedLine)",
            generating: ScanAnswer.self,
            options: GenerationOptions(sampling: .greedy)
        )
        return response.content.suspects
            .filter { $0.kind != .other }
            .map { Suspect(heard: $0.heard, surfaces: $0.surfaces) }
    }
}
