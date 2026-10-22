import AppKit
import KeyboardShortcuts
import SwiftUI
import TsuzuriCore

extension KeyboardShortcuts.Name {
    /// 直前の文字をもう一度貼る。設定の窓で変えられる
    static let pasteLast = Self("pasteLast", default: .init(.v, modifiers: [.control, .option, .command]))
}

@main
struct TsuzuriApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: appDelegate.controller)
        } label: {
            MenuBarIcon(controller: appDelegate.controller)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = DictationController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 録音中の表示を画像に描き出して終わる(--render-hud <フォルダ>。画面の録画の権限が無くても見た目を確かめられる)。
        // キーの検知やキーチェーンの読み出しより前に終える
        if let index = CommandLine.arguments.firstIndex(of: "--render-hud"), index + 1 < CommandLine.arguments.count {
            RecordingHUD.renderSamples(to: URL(filePath: CommandLine.arguments[index + 1], directoryHint: .isDirectory))
            exit(0)
        }
        NSApp.setActivationPolicy(.accessory)
        KeyboardShortcuts.onKeyUp(for: .pasteLast) { [controller] in
            controller.pasteLast()
        }
        controller.start()
        // 動作の確かめ用: 起動時に窓を開く(open -a Tsuzuri --args --show-dictionary)
        if CommandLine.arguments.contains("--show-dictionary") { controller.showDictionary() }
        if CommandLine.arguments.contains("--show-settings") { controller.showSettings() }
        if CommandLine.arguments.contains("--show-candidates") { controller.showCandidates() }
        // 録音中の表示を見本の文字で出す(--preview-hud、黒は --preview-hud-dark)
        if let theme = [("--preview-hud", HUDTheme.blueWhite), ("--preview-hud-dark", .dark)].first(where: { CommandLine.arguments.contains($0.0) })?.1 {
            controller.previewHUD(theme: theme)
        }
    }
}
