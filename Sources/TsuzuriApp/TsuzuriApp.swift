import AppKit
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    /// 直前の文字をもう一度貼る。段階4で登録画面を出すまで初期値のまま使う
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
        NSApp.setActivationPolicy(.accessory)
        KeyboardShortcuts.onKeyUp(for: .pasteLast) { [controller] in
            controller.pasteLast()
        }
        controller.start()
    }
}
