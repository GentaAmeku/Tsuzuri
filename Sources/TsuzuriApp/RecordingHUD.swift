import AppKit
import Observation
import SwiftUI
import TsuzuriCore

/// 録音中の表示(画面の下の黒い帯)。フォーカスを奪わない窓に出し、貼り付け先がずれないようにする
@Observable
final class RecordingHUD {
    enum Mode: Equatable {
        case hidden
        case recording
        case finishing
        case notice(String)
    }

    private(set) var mode: Mode = .hidden
    private(set) var finalText = ""
    private(set) var tentativeText = ""
    private(set) var startedAt = Date()
    var level: Float = 0
    /// 録音中に分かった失敗(つながらないなど)。録音は続ける
    var warning: String?
    /// 使っている認識(Soniox・Mac 内)
    private(set) var engineLabel = "Soniox"
    /// 確定を待つ間に出す文
    private(set) var finishingMessage = "確定を待っています"

    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    func showRecording(engine: String) {
        engineLabel = engine
        finalText = ""
        tentativeText = ""
        warning = nil
        level = 0
        startedAt = Date()
        setMode(.recording)
    }

    func showFinishing(_ message: String) {
        finishingMessage = message
        setMode(.finishing)
    }

    func update(_ assembler: TranscriptAssembler) {
        guard mode == .recording || mode == .finishing else { return }
        finalText = assembler.finalText
        tentativeText = assembler.tentativeText
    }

    /// 短い知らせを出し、少したったら消す
    func notice(_ message: String) {
        setMode(.notice(message))
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, self?.mode == .notice(message) else { return }
            self?.hide()
        }
    }

    func hide() {
        noticeTask?.cancel()
        mode = .hidden
        panel?.orderOut(nil)
    }

    private func setMode(_ mode: Mode) {
        noticeTask?.cancel()
        self.mode = mode
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()
    }

    private static let size = CGSize(width: 620, height: 76)

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: Self.size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: HUDView(hud: self))
        return panel
    }

    /// マウスのある画面の下の中央に置く
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(CGPoint(x: frame.midX - Self.size.width / 2, y: frame.minY + 60))
    }
}

struct HUDView: View {
    let hud: RecordingHUD

    var body: some View {
        HStack(spacing: 14) {
            switch hud.mode {
            case let .notice(message):
                Image(systemName: "info.circle.fill").foregroundStyle(.yellow)
                Text(message).foregroundStyle(.white)
                Spacer(minLength: 0)
            default:
                indicator
                TimelineView(.periodic(from: hud.startedAt, by: 1)) { context in
                    Text(Self.elapsed(from: hud.startedAt, to: context.date))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.7))
                }
                transcript
                Spacer(minLength: 0)
                LevelBars(level: hud.level)
                Text(hud.warning == nil ? hud.engineLabel : "\(hud.engineLabel) ✕")
                    .font(.caption)
                    .foregroundStyle(hud.warning == nil ? .white.opacity(0.6) : .orange)
            }
        }
        .font(.system(size: 14))
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.85)))
    }

    @ViewBuilder private var indicator: some View {
        if hud.mode == .finishing {
            ProgressView().controlSize(.small).tint(.white)
        } else {
            Circle().fill(.red).frame(width: 10, height: 10)
        }
    }

    /// 確定した文字は白、まだ変わりうる文字は薄く出す。長いときは後ろを見せる
    private var transcript: some View {
        var text = AttributedString(hud.finalText)
        text.foregroundColor = .white
        var tentative = AttributedString(hud.tentativeText)
        tentative.foregroundColor = .white.opacity(0.45)
        text += tentative
        if let warning = hud.warning {
            var note = AttributedString(text.characters.isEmpty ? warning : "  \(warning)")
            note.foregroundColor = .orange
            text += note
        }
        if text.characters.isEmpty {
            var placeholder = AttributedString(hud.mode == .finishing ? hud.finishingMessage : "話してください")
            placeholder.foregroundColor = .white.opacity(0.45)
            text = placeholder
        }
        return Text(text)
            .lineLimit(2)
            .truncationMode(.head)
            .frame(maxWidth: 400, alignment: .leading)
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// 音量の棒
struct LevelBars: View {
    let level: Float

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<5) { index in
                let threshold = Float(index) / 5
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(level > threshold ? Color.green : Color.white.opacity(0.2))
                    .frame(width: 4, height: CGFloat(8 + index * 4))
            }
        }
        .animation(.linear(duration: 0.08), value: level)
    }
}
