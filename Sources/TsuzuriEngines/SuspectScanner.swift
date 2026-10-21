import Foundation
import FoundationModels
import TsuzuriCore

/// 辞書の候補の洗い出しの2段目(挙げる)。文全体と印の付いた語を Apple Foundation Models に渡し、
/// 誤って認識したらしい語と表記の案を答えさせる(設計書「挙げる」)。Mac の中で終わり、外へは何も送らない
public enum SuspectScanner {
    @Generable
    struct SuspectAnswer {
        @Guide(description: "文の中にそのまま出てくる、誤って認識したらしい語")
        var heard: String
        @Guide(description: "本来の表記の案。よく使われる表記から順に", .maximumCount(2))
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
    - heard には、文の中の字をそのまま写す
    - 製品名・ライブラリ名・技術用語は、公式の英字の表記にする。例: ドッカーコンポーズ → Docker Compose / スーパーベース → Supabase / ぷりずま → Prisma / Type オーム → TypeORM
    - 同じ読みの別の漢字は、文脈に合う漢字にする。例: 「処理が以上終了した」の「以上」→「異常」
    - ふつうの日本語や、文脈に合っているカタカナ語(タスク・ファイル・メモリ・ボタン・リリース・ブランチ)は挙げない
    - 誤りが無ければ空にする
    印の付いた語は、怪しいかもしれない語の手がかり。印の無い語を挙げてもよく、印の付いた語でも誤りでなければ挙げない。
    """

    /// Apple Intelligence が有効で、端末の中の LLM を使えるか
    public static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    public static func scan(_ text: String, marked: [String]) async throws -> [Suspect] {
        let session = LanguageModelSession(instructions: instructions)
        let markedLine = marked.isEmpty ? "(なし)" : marked.joined(separator: "、")
        let response = try await session.respond(
            to: "文: \(text)\n印の付いた語: \(markedLine)",
            generating: ScanAnswer.self,
            options: GenerationOptions(sampling: .greedy)
        )
        return response.content.suspects.map { Suspect(heard: $0.heard, surfaces: $0.surfaces) }
    }
}
