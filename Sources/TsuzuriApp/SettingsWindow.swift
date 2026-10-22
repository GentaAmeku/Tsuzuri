import AppKit
import ApplicationServices
import AVFoundation
import KeyboardShortcuts
import Observation
import ServiceManagement
import SwiftUI
import TsuzuriCore

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

/// ログイン時の起動(`SMAppService`)。/Applications に置いた署名済みのアプリで効く
@Observable
final class LoginItem {
    private(set) var isEnabled = SMAppService.mainApp.status == .enabled
    private(set) var message: String?

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            message = nil
        } catch {
            message = "切り替えられませんでした(\(error.localizedDescription))"
        }
        refresh()
        if SMAppService.mainApp.status == .requiresApproval {
            message = "システム設定の「ログイン項目」で Tsuzuri を許可してください"
        }
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}

struct SettingsView: View {
    @Bindable var controller: DictationController
    @State private var draftKey = ""
    @State private var keyMessage: String?
    @State private var loginItem = LoginItem()

    enum Tab: Hashable {
        case general
        case keys
        case sonioxAndDictionary
    }

    @State var tab: Tab = .general

    var body: some View {
        // 上端に余白をとった切り替えと、背景を透かしたフォームで、窓の背景を1色にそろえる
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("一般").tag(Tab.general)
                Text("キー").tag(Tab.keys)
                Text("Soniox と辞書").tag(Tab.sonioxAndDictionary)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 18)
            .padding(.bottom, 2)
            switch tab {
            case .general: generalTab
            case .keys: keysTab
            case .sonioxAndDictionary: sonioxTab
            }
        }
        .frame(width: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            // 権限はシステム設定で変わるので、窓を開いている間は見直す
            while !Task.isCancelled {
                controller.permissions.refresh()
                loginItem.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// 権限・表示・音声
    private var generalTab: some View {
        @Bindable var store = controller.store
        return Form {
            Section("権限") {
                PermissionRow(
                    title: "マイク",
                    detail: "話した声を録るため",
                    granted: controller.permissions.microphone == .authorized,
                    action: controller.permissions.requestMicrophone
                )
                PermissionRow(
                    title: "アクセシビリティ",
                    detail: "キーの検知・Esc・Return・⌘V の貼り付けのため",
                    granted: controller.permissions.accessibility,
                    action: controller.permissions.requestAccessibility
                )
            }
            Section("表示と起動") {
                Picker("録音中の表示の色", selection: $store.hudTheme) {
                    ForEach(HUDTheme.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Toggle("ログイン時に起動する", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.set($0) }))
                if let message = loginItem.message {
                    Text(message).font(.caption).foregroundStyle(.orange)
                }
                Toggle("録音を7日間残す(認識し直しと評価に使う)", isOn: $store.keepAudio)
            }
            Section("Mac 内の認識") {
                Toggle("Mac 内でも話しながら文字を出す", isOn: $store.localLivePreview)
                Text("途中の文字は Apple の認識で出し、貼る文字は今までどおり WhisperKit で作ります。止めたあと、貼る文字が途中の文字と少し変わることがあります。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// 録音キー・操作の方式・ショートカット・使い方
    private var keysTab: some View {
        Form {
            Section("録音キー") {
                Picker("録音キー", selection: hotkey(\.key)) {
                    ForEach(HotkeySettings.Key.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                if controller.hotkeySettings.key == .fn {
                    Text("fn は、システム設定の「キーボード」で「🌐キーを押して」を「何もしない」にしてから使ってください。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Picker("操作の方式", selection: hotkey(\.mode)) {
                    ForEach(HotkeySettings.Mode.allCases, id: \.self) { Text($0.shortLabel).tag($0) }
                }
                if controller.hotkeySettings.mode == .hybrid {
                    LabeledContent("長押しとみなす秒数") {
                        Stepper(String(format: "%.1f 秒", controller.hotkeySettings.longPressSeconds), value: hotkey(\.longPressSeconds), in: 0.3...1.5, step: 0.1)
                    }
                }
                KeyboardShortcuts.Recorder("直前の文字をもう一度貼る", name: .pasteLast)
                if controller.phase != .idle {
                    Text("録音中は変えられません").font(.caption).foregroundStyle(.secondary)
                }
            }
            .disabled(controller.phase != .idle)
            Section("使い方") {
                Text(usage)
                Text("録音中に Return で、止めて貼ったあとに送信します。Esc で取り消します。")
            }
            .font(.callout)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Soniox の API キーと辞書
    private var sonioxTab: some View {
        @Bindable var store = controller.store
        return Form {
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
            }
            Section("辞書") {
                LabeledContent("語の数") {
                    Text("\(controller.dictionary.dictionary.entries.count) 語")
                }
                if let error = controller.dictionary.loadError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Button("辞書を編集…") { controller.showDictionary() }
                    Button("ファイルを開く") { controller.dictionary.openInEditor() }
                    Spacer()
                }
                Toggle("日本語と英字のあいだに半角スペースを入れる", isOn: $store.waObunSpacing)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func hotkey<Value>(_ keyPath: WritableKeyPath<HotkeySettings, Value>) -> Binding<Value> {
        Binding(
            get: { controller.hotkeySettings[keyPath: keyPath] },
            set: { value in
                var settings = controller.hotkeySettings
                settings[keyPath: keyPath] = value
                controller.hotkeySettings = settings
            }
        )
    }

    private var usage: String {
        let key = controller.keyLabel
        switch controller.hotkeySettings.mode {
        case .hybrid:
            return "\(key)を短く押すと録音を始め、もう一度押すと止めて貼り付けます。長く押すと、押している間だけ録ります。"
        case .toggle:
            return "\(key)を押すと録音を始め、もう一度押すと止めて貼り付けます。"
        case .hold:
            return "\(key)を押している間だけ録り、離すと止めて貼り付けます。"
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

extension SettingsWindow {
    /// 動作の確かめ用。設定の窓をタブごとに本物の窓へ出し、中身を PNG に写し取って大きさを書き出す
    static func renderTabs(controller: DictationController, to directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let tabs: [(String, SettingsView.Tab)] = [("general", .general), ("keys", .keys), ("soniox", .sonioxAndDictionary)]
        for (name, tab) in tabs {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(controller: controller, tab: tab)))
            window.title = "Tsuzuri の設定"
            window.styleMask = [.titled, .closable]
            window.center()
            window.orderFront(nil)
            try? await Task.sleep(for: .milliseconds(800))
            if let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "settings-\(name).png"))
                print("\(name): 窓の中身 \(view.bounds.size)")
            }
            window.close()
        }
    }
}
