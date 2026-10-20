import Darwin
import Foundation

/// 画面に出さずに1行を読む(API キーの入力用)
func readSecret(prompt: String) -> String? {
    var buffer = [CChar](repeating: 0, count: 1_024)
    guard readpassphrase(prompt, &buffer, buffer.count, RPP_ECHO_OFF) != nil else { return nil }
    return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}

/// 問いを出して1行を読む。Enter だけなら空文字、入力が閉じたら "q"
func ask(_ prompt: String) -> String {
    print(prompt, terminator: "")
    return (readLine() ?? "q").trimmingCharacters(in: .whitespaces)
}
