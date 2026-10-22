import AppKit
import SwiftUI
import TsuzuriCore

/// メニューバーのアイコン。録音中だけ赤くする(テーマに依らない)
struct MenuBarIcon: View {
    let controller: DictationController

    var body: some View {
        switch controller.phase {
        case .idle:
            if controller.isReady {
                Image(nsImage: Self.glyph)
            } else {
                Image(systemName: "exclamationmark.triangle")
            }
        case .recording: Image(nsImage: Self.redRecordIcon)
        case .finishing: Image(systemName: "ellipsis.circle")
        }
    }

    /// 待機中のアイコン。一目で声の入力と分かるよう、マイクを単色の線で描く(質問票 sheet_20261022_006 で本人が選んだ)。
    /// テンプレートの絵にして、メニューバーの明るさに合わせた色で出させる
    static let glyph: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setStroke()
            func stroke(_ path: NSBezierPath, _ width: CGFloat) {
                path.lineWidth = width
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            }
            func line(_ from: NSPoint, _ to: NSPoint, _ width: CGFloat) {
                let path = NSBezierPath()
                path.move(to: from)
                path.line(to: to)
                stroke(path, width)
            }
            // マイクの頭と、中の2本の網目
            stroke(NSBezierPath(roundedRect: NSRect(x: 6.4, y: 1.8, width: 5.2, height: 9.4), xRadius: 2.6, yRadius: 2.6), 1.35)
            for y: CGFloat in [4.8, 7.6] {
                line(NSPoint(x: 7.9, y: y), NSPoint(x: 10.1, y: y), 1.2)
            }
            // U字の支えと台
            let holder = NSBezierPath()
            holder.appendArc(withCenter: NSPoint(x: 9, y: 8.6), radius: 4.9, startAngle: 180, endAngle: 0, clockwise: true)
            stroke(holder, 1.35)
            line(NSPoint(x: 9, y: 13.5), NSPoint(x: 9, y: 15.6), 1.35)
            line(NSPoint(x: 6.6, y: 15.8), NSPoint(x: 11.4, y: 15.8), 1.35)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Tsuzuri"
        return image
    }()

    /// 録音中は赤い丸だけを出す。メニューバーのアイコンはふつう単色にされるので、色を付けた絵として渡す
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
        // 認識は印を付けて選ぶ。どちらも話しながら文字が出る(Mac 内は設定で切れる)。違いは通信するかどうか
        Picker("認識", selection: Binding(
            get: { controller.store.localOnly },
            set: { controller.store.localOnly = $0 }
        )) {
            Text("Soniox(通信して認識する。精度が高い)").tag(false)
            Text("Mac 内(通信しない)").tag(true)
        }
        .pickerStyle(.inline)
        if let until = controller.fallbackUntil, until > Date(), !controller.store.localOnly {
            Text("Soniox の失敗のあと、\(until.formatted(date: .omitted, time: .shortened)) まで Mac 内で認識します")
        }
        if !controller.local.isAvailable {
            Text("Mac 内の認識: \(controller.local.stateDescription)")
        }
        Text(controller.store.sonioxCostLine)
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
