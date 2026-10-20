import AppKit
import ApplicationServices
import AVFoundation
import Observation
import SwiftUI

/// 2つの権限(マイク・アクセシビリティ)の状態
@Observable
final class Permissions {
    private(set) var microphone: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    private(set) var accessibility = AXIsProcessTrusted()

    var allGranted: Bool { microphone == .authorized && accessibility }

    func refresh() {
        microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        accessibility = AXIsProcessTrusted()
    }

    /// まだ聞いていなければ OS の確認を出し、断ったあとならシステム設定を開く
    func requestMicrophone() {
        guard microphone == .notDetermined else {
            return Self.openPrivacy("Privacy_Microphone")
        }
        Task {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            refresh()
        }
    }

    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            Self.openPrivacy("Privacy_Accessibility")
        }
    }

    static func openPrivacy(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// 設定の窓。メニューバーのアプリなので、開くときに前へ出す
final class SettingsWindow {
    private let controller: DictationController
    private var window: NSWindow?

    init(controller: DictationController) {
        self.controller = controller
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(controller: controller)))
        window.title = "Tsuzuri の設定"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

struct SettingsView: View {
    @Bindable var controller: DictationController
    @State private var draftKey = ""
    @State private var keyMessage: String?

    var body: some View {
        @Bindable var store = controller.store
        Form {
            Section("権限") {
                PermissionRow(
                    title: "マイク",
                    detail: "話した声を録るため",
                    granted: controller.permissions.microphone == .authorized,
                    action: controller.permissions.requestMicrophone
                )
                PermissionRow(
                    title: "アクセシビリティ",
                    detail: "右⌘の検知・Esc の取り消し・⌘V の貼り付けのため。許可したら、この窓が自動で更新されます",
                    granted: controller.permissions.accessibility,
                    action: controller.permissions.requestAccessibility
                )
            }
            Section("Soniox") {
                LabeledContent("API キー") {
                    switch controller.hasAPIKey {
                    case true?: Text("登録済み").foregroundStyle(.green)
                    case false?: Text("未登録").foregroundStyle(.orange)
                    case nil: Text("確認中(キーチェーンの画面で「許可」を押してください)").foregroundStyle(.secondary)
                    }
                }
                HStack {
                    SecureField("新しいキーを貼り付け", text: $draftKey)
                    Button("保存") { save() }
                        .disabled(draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let keyMessage {
                    Text(keyMessage).font(.caption).foregroundStyle(.secondary)
                }
                Text("キーはキーチェーン(Tsuzuri.Soniox)に置き、画面やファイルには出しません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("辞書") {
                LabeledContent("語の数") {
                    Text("\(controller.dictionary.dictionary.entries.count) 語(ヒントに使う語は最大100語)")
                }
                if let error = controller.dictionary.loadError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Text("置き換え元(from)に聞き違いを足すと、正しい表記に直して貼ります。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("辞書を編集…") { controller.showDictionary() }
                    Button("ファイルを開く") { controller.dictionary.openInEditor() }
                }
                Toggle("日本語と英字のあいだに半角スペースを入れる", isOn: $store.waObunSpacing)
            }
            Section("音声") {
                Toggle("録音を7日間残す", isOn: $store.keepAudio)
                Text("メニューの「直前の録音を認識し直す」と、精度の評価に使います。失敗したときの録音もここに残ります。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("使い方") {
                Text("右⌘を短く押すと録音を始め、もう一度押すと止めて貼り付けます。長く押すと、押している間だけ録ります。")
                Text("録音中に Esc で取り消します。⌃⌥⌘V で直前の文字をもう一度貼ります。")
            }
            .font(.callout)
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            // 権限はシステム設定で変わるので、窓を開いている間は見直す
            while !Task.isCancelled {
                controller.permissions.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func save() {
        let key = draftKey
        Task {
            do {
                try await controller.saveAPIKey(key)
                draftKey = ""
                keyMessage = "保存しました"
            } catch {
                keyMessage = "保存できませんでした(\(error))"
            }
        }
    }
}

struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("許可する", action: action)
            }
        }
    }
}
