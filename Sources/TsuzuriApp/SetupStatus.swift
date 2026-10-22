import AppKit
import ApplicationServices
import AVFoundation
import ServiceManagement

/// セットアップの doctor(`scripts/doctor.sh`)が読む、アプリの権限と状態(`setup-status.json`)。
/// 権限は OS の外から読めないので、アプリが数秒ごとに書き出す。秘密の情報は入れない
struct SetupStatus: Codable, Equatable {
    /// アプリを作ったリポジトリのコミット(Info.plist の TsuzuriSourceRevision)
    var revision: String
    /// マイク: authorized・denied・notDetermined・restricted
    var microphone: String
    var accessibility: Bool
    /// 録音キーの検知が動いているか
    var listening: Bool
    /// ログイン時の起動: enabled・notRegistered・requiresApproval・notFound
    var loginItem: String

    static func current(listening: Bool) -> SetupStatus {
        let microphone: String = switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: "authorized"
        case .denied: "denied"
        case .restricted: "restricted"
        case .notDetermined: "notDetermined"
        @unknown default: "unknown"
        }
        let loginItem: String = switch SMAppService.mainApp.status {
        case .enabled: "enabled"
        case .notRegistered: "notRegistered"
        case .requiresApproval: "requiresApproval"
        case .notFound: "notFound"
        @unknown default: "unknown"
        }
        return SetupStatus(
            revision: Bundle.main.object(forInfoDictionaryKey: "TsuzuriSourceRevision") as? String ?? "dev",
            microphone: microphone,
            accessibility: AXIsProcessTrusted(),
            listening: listening,
            loginItem: loginItem
        )
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
