import ArgumentParser
import Foundation
import TsuzuriEngines

/// Mac 内の認識に使うモデルを取得する。アプリはモデルを取得しないので、使い始める前に1回だけ実行する
struct FetchModel: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fetch-model",
        abstract: "Mac 内の認識のモデル(WhisperKit、約600MB)を ~/Library/Caches/Tsuzuri/models に取得する。--apple で、話している途中の文字に使う Apple の日本語のモデルもシステムに取得させる"
    )

    @Flag(help: "Apple の日本語の認識モデルも取得する(システムが置き場所と大きさを決める)")
    var apple = false

    func run() async throws {
        print("WhisperKit のモデル(\(WhisperKitEngine.defaultModel))を取得しています。数分かかります…")
        _ = try await WhisperKitEngine.load(model: WhisperKitEngine.defaultModel, allowDownload: true)
        print("取得しました: \(try ModelCache.directory().path)")
        if apple {
            print("Apple の日本語の認識モデルを取得しています…")
            try await AppleSpeechLive.installJapaneseModel()
            // セットアップの doctor が確かめる印(Apple のモデルの有無は、アプリの外からは確かめにくい)
            let marker = try ModelCache.directory().appending(path: "apple-japanese.json")
            try Data("{\"installedAt\": \"\(Date().ISO8601Format())\"}\n".utf8).write(to: marker, options: .atomic)
            print("取得しました")
        }
    }
}
