import ArgumentParser
import Foundation
import TsuzuriEngines

struct SetKey: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set-key",
        abstract: "Soniox の API キーをキーチェーンに登録する(入力した文字は画面に出ない)"
    )

    func run() throws {
        guard let key = readSecret(prompt: "Soniox の API キー: ")?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw ValidationError("キーが空です")
        }
        try SonioxKeychain.save(key)
        print("キーチェーンに保存しました(サービス名: \(SonioxKeychain.service))")
    }
}
