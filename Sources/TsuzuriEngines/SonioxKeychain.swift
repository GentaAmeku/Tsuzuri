import Foundation
import Security

public enum KeychainError: Error, CustomStringConvertible {
    case notFound
    case unexpectedStatus(OSStatus)

    public var description: String {
        switch self {
        case .notFound:
            "Soniox の API キーがキーチェーンにありません。`swift run tsuzuri-eval set-key` で登録してください"
        case let .unexpectedStatus(status):
            "キーチェーンの操作に失敗しました(\(status): \(SecCopyErrorMessageString(status, nil) as String? ?? "不明"))"
        }
    }
}

/// Soniox の API キーを、ログインキーチェーンの汎用パスワードとして持つ。
/// 評価の CLI とアプリが同じ項目を読む
public enum SonioxKeychain {
    public static let service = "Tsuzuri.Soniox"
    static let account = "api-key"

    static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    public static func save(_ key: String) throws {
        let data = Data(key.utf8)
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            let addStatus = SecItemAdd(baseQuery.merging([kSecValueData as String: data]) { $1 } as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        default:
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    public static func load() throws -> String {
        let query = baseQuery.merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]) { $1 }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else { throw KeychainError.notFound }
        guard status == errSecSuccess, let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedStatus(status)
        }
        return key
    }
}
