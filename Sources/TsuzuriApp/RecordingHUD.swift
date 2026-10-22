import AppKit
import Observation
import SwiftUI
import TsuzuriCore

/// 録音中の表示(画面の下のカード)。フォーカスを奪わない窓に出し、貼り付け先がずれないようにする。
/// 色はテーマ(青と白・黒)で変え、並びと大きさは同じ(設計書「録音中の表示は段階4で直す」)
@Observable
final class RecordingHUD {
    enum Mode: Equatable {
        case hidden
        case recording
        case finishing
        case notice(String)
    }

    fileprivate(set) var mode: Mode = .hidden
    fileprivate(set) var finalText = ""
    fileprivate(set) var tentativeText = ""
    fileprivate(set) var startedAt = Date()
    var level: Float = 0
    /// 録音中に分かった失敗(つながらないなど)。録音は続ける
    var warning: String?
    /// 使っている認識(Soniox・Mac 内)
    private(set) var engineLabel = "Soniox"
    /// 確定を待つ間に出す文
    private(set) var finishingMessage = "確定を待っています"
    /// 色
    var theme: HUDTheme = .blueWhite
    /// 録音中に Return が押され、貼ったあとに送る
    var willSubmit = false

    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    func showRecording(engine: String) {
        engineLabel = engine
        finalText = ""
        tentativeText = ""
        warning = nil
        willSubmit = false
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

    fileprivate static let size = CGSize(width: 720, height: 104)

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
        panel.setFrameOrigin(CGPoint(x: frame.midX - Self.size.width / 2, y: frame.minY + 40))
    }
}

/// テーマごとの色
struct HUDPalette {
    let background: Color
    let border: Color?
    let label: Color
    let text: Color
    let secondary: Color
    let bars: Color
    let barsOff: Color
    let spinner: Color

    init(_ theme: HUDTheme) {
        switch theme {
        case .blueWhite:
            let blue = Color(red: 0.18, green: 0.42, blue: 1.0)
            background = .white
            border = blue
            label = Color(red: 0.12, green: 0.31, blue: 0.85)
            text = Color(red: 0.06, green: 0.14, blue: 0.25)
            secondary = Color(red: 0.29, green: 0.37, blue: 0.50)
            bars = blue
            barsOff = blue.opacity(0.18)
            spinner = blue
        case .dark:
            background = Color.black.opacity(0.88)
            border = nil
            label = .white
            text = .white
            secondary = .white.opacity(0.65)
            bars = .green
            barsOff = .white.opacity(0.2)
            spinner = .white
        }
    }
}

struct HUDView: View {
    let hud: RecordingHUD

    private var palette: HUDPalette { HUDPalette(hud.theme) }

    var body: some View {
        HStack(spacing: 18) {
            switch hud.mode {
            case let .notice(message):
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(hud.theme == .dark ? .yellow : palette.label)
                Text(message)
                    .font(.system(size: 17))
                    .foregroundStyle(palette.text)
                    .lineLimit(2)
                Spacer(minLength: 0)
            case .finishing:
                Spinner(color: palette.spinner)
                Text(hud.finishingMessage)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(palette.label)
                transcript(dimmed: true)
                Spacer(minLength: 0)
                submitBadge
            default:
                RecordingDot()
                VStack(alignment: .leading, spacing: 2) {
                    Text("録音中")
                        .font(.system(size: 21, weight: .heavy))
                        .foregroundStyle(palette.label)
                    TimelineView(.periodic(from: hud.startedAt, by: 1)) { context in
                        Text(Self.elapsed(from: hud.startedAt, to: context.date))
                            .font(.system(size: 17))
                            .monospacedDigit()
                            .foregroundStyle(palette.secondary)
                    }
                }
                .fixedSize()
                transcript(dimmed: false)
                Spacer(minLength: 0)
                submitBadge
                LevelBars(level: hud.level, on: palette.bars, off: palette.barsOff)
                Text(hud.warning == nil ? hud.engineLabel : "\(hud.engineLabel) ✕")
                    .font(.system(size: 13))
                    .foregroundStyle(hud.warning == nil ? palette.secondary : .orange)
            }
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(palette.background)
                .overlay {
                    if let border = palette.border {
                        RoundedRectangle(cornerRadius: 22).strokeBorder(border, lineWidth: 2)
                    }
                }
        )
    }

    /// 録音中に Return が押されたら、貼ったあとに送ることを示す
    @ViewBuilder private var submitBadge: some View {
        if hud.willSubmit {
            Text("↩ 貼ったあと送信")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.label)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().strokeBorder(palette.label.opacity(0.5)))
                .fixedSize()
        }
    }

    /// 確定した文字は濃く、まだ変わりうる文字は薄く出す。長いときは後ろを見せる
    private func transcript(dimmed: Bool) -> some View {
        let strong = dimmed ? palette.secondary : palette.text
        var text = AttributedString(hud.finalText)
        text.foregroundColor = strong
        var tentative = AttributedString(hud.tentativeText)
        tentative.foregroundColor = strong.opacity(0.5)
        text += tentative
        if let warning = hud.warning {
            var note = AttributedString(text.characters.isEmpty ? warning : "  \(warning)")
            note.foregroundColor = .orange
            text += note
        }
        if text.characters.isEmpty, !dimmed {
            var placeholder = AttributedString("話してください")
            placeholder.foregroundColor = palette.secondary
            text = placeholder
        }
        return Text(text)
            .font(.system(size: 17))
            .lineLimit(2)
            .truncationMode(.head)
            .frame(maxWidth: 380, alignment: .leading)
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// 確定を待つ間の回る輪(テーマの色で描く)
struct Spinner: View {
    let color: Color
    @State private var turning = false

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: 4)
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(turning ? 360 : 0))
        }
        .frame(width: 28, height: 28)
        .onAppear {
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { turning = true }
        }
    }
}

/// 録音中だけ出す赤い円。外側の輪が脈打つ
struct RecordingDot: View {
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.18))
                .frame(width: 46, height: 46)
                .scaleEffect(pulsing ? 1.0 : 0.72)
                .opacity(pulsing ? 0.6 : 1)
            Circle()
                .fill(Color(red: 1.0, green: 0.23, blue: 0.19))
                .frame(width: 26, height: 26)
        }
        .frame(width: 46, height: 46)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulsing = true }
        }
    }
}

/// 音量の棒
struct LevelBars: View {
    let level: Float
    let on: Color
    let off: Color

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<7) { index in
                let threshold = Float(index) / 7
                RoundedRectangle(cornerRadius: 2)
                    .fill(level > threshold ? on : off)
                    .frame(width: 5, height: CGFloat(10 + index * 3))
            }
        }
        .animation(.linear(duration: 0.08), value: level)
    }
}

extension RecordingHUD {
    /// 動作の確かめ用。テーマごとに、録音中と確定待ちの表示を PNG に描き出す
    static func renderSamples(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for theme in HUDTheme.allCases {
            for finishing in [false, true] {
                let hud = RecordingHUD()
                hud.theme = theme
                hud.mode = finishing ? .finishing : .recording
                hud.startedAt = Date().addingTimeInterval(-7)
                hud.finalText = "テストの件、午後に"
                hud.tentativeText = "確認します"
                hud.level = 0.6
                hud.willSubmit = finishing
                let view = HUDView(hud: hud).frame(width: size.width, height: size.height).padding(20).background(Color(white: 0.85))
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
                try? png.write(to: directory.appending(path: "hud-\(theme.rawValue)-\(finishing ? "finishing" : "recording").png"))
            }
        }
    }
}
