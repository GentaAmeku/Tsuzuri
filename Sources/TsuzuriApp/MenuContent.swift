import AppKit
import SwiftUI
import TsuzuriCore

/// メニューバーのアイコン。録音中は赤い丸にする
struct MenuBarIcon: View {
    let controller: DictationController

    var body: some View {
        switch controller.phase {
        case .idle: Image(systemName: controller.isReady ? "waveform" : "exclamationmark.triangle")
        case .recording: Image(systemName: "record.circle.fill")
        case .finishing: Image(systemName: "ellipsis.circle")
        }
    }
}

struct MenuContent: View {
    let controller: DictationController

    var body: some View {
        Text(controller.statusLine)
        Divider()
        Text(controller.engineLine)
        Toggle("Mac 内だけで認識する", isOn: Binding(
            get: { controller.store.localOnly },
            set: { controller.store.localOnly = $0 }
        ))
        .disabled(!controller.local.isAvailable)
        if !controller.local.isAvailable {
            Text("Mac 内の認識: \(controller.local.stateDescription)")
        }
        Button("直前の文字を貼り付け") { controller.pasteLast() }
            .keyboardShortcut("v", modifiers: [.control, .option, .command])
            .disabled(controller.lastText == nil)
        Menu("履歴") {
            let recent = controller.store.history.suffix(10).reversed()
            if recent.isEmpty {
                Text("まだありません")
            }
            ForEach(Array(recent.enumerated()), id: \.offset) { _, entry in
                Button(Self.title(of: entry)) { controller.copy(entry) }
                    .disabled(entry.text.isEmpty)
            }
            Divider()
            Button("履歴のフォルダを開く") { controller.store.revealInFinder() }
        }
        Divider()
        Button("設定…") { controller.showSettings() }
            .keyboardShortcut(",")
        Button("Tsuzuri を終了") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// 履歴の1行。押すとクリップボードに写す
    static func title(of entry: HistoryEntry) -> String {
        let time = entry.date.formatted(date: .omitted, time: .shortened)
        if let error = entry.error { return "\(time) 失敗: \(error)" }
        let text = entry.text.count > 40 ? entry.text.prefix(40) + "…" : entry.text
        return "\(time) \(text)"
    }
}
