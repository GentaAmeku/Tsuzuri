import AppKit
import SwiftUI
import TsuzuriCore

/// メニューバーのアイコン。録音中だけ赤くする(テーマに依らない)
struct MenuBarIcon: View {
    let controller: DictationController

    var body: some View {
        switch controller.phase {
        case .idle: Image(systemName: controller.isReady ? "waveform" : "exclamationmark.triangle")
        case .recording: Image(nsImage: Self.redRecordIcon)
        case .finishing: Image(systemName: "ellipsis.circle")
        }
    }

    /// メニューバーのアイコンはふつう単色にされるので、色を付けた絵として渡す
    static let redRecordIcon: NSImage = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
        let image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "録音中")?
            .withSymbolConfiguration(configuration) ?? NSImage()
        image.isTemplate = false
        return image
    }()
}

struct MenuContent: View {
    let controller: DictationController

    var body: some View {
        Text(controller.statusLine)
        Divider()
        Text(controller.engineLine)
        Text(controller.store.sonioxCostLine)
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
        Menu("直前の録音を認識し直す") {
            Button("Soniox で") { controller.reRecognizeLast(locally: false) }
                .disabled(controller.hasAPIKey != true)
            Button("Mac 内で") { controller.reRecognizeLast(locally: true) }
                .disabled(!controller.local.isAvailable)
        }
        .disabled(controller.lastRecording == nil || controller.phase != .idle)
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
        if controller.candidates.isUnavailable {
            Text("Apple Intelligence が無効なので、辞書の候補を出していません")
        }
        Button("辞書の候補(\(controller.candidates.file.items.count)件)…") { controller.showCandidates() }
        Button("辞書を編集…") { controller.showDictionary() }
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
