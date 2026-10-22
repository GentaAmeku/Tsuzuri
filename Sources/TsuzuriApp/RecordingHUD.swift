import AppKit
import Observation
import SwiftUI
import TsuzuriCore

/// 録音中の表示。話し始めは小さなピルで、文字が出ると上に伸びるカードになる(設計書「録音中の表示は段階4で直す」)。
/// フォーカスを奪わない窓に出し、貼り付け先がずれないようにする。停止ボタンだけはクリックで押せる
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
    /// 音量。直近の値を波形として並べる
    var level: Float = 0 {
        didSet {
            levels.removeFirst()
            levels.append(level)
        }
    }
    fileprivate(set) var levels = [Float](repeating: 0, count: RecordingHUD.levelCount)
    /// 録音中に分かった失敗(つながらないなど)。録音は続ける
    var warning: String? {
        didSet { if warning != oldValue { scheduleResize() } }
    }
    /// 使っている認識(Soniox・Mac 内)
    fileprivate(set) var engineLabel = "Soniox"
    /// 確定を待つ間に出す文
    private(set) var finishingMessage = "確定を待っています"
    /// 色
    var theme: HUDTheme = .blueWhite
    /// 録音中に Return が押され、貼ったあとに送る
    var willSubmit = false
    /// 停止ボタンが押されたとき
    @ObservationIgnored var onStop: (() -> Void)?

    static let levelCount = 22

    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var hostingView: NSHostingView<HUDView>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    /// 表示の下の辺の中央(画面の座標)。大きさが変わっても、ここを動かさずに上へ伸ばす
    @ObservationIgnored private var anchor = CGPoint.zero

    func showRecording(engine: String) {
        engineLabel = engine
        finalText = ""
        tentativeText = ""
        warning = nil
        willSubmit = false
        levels = [Float](repeating: 0, count: Self.levelCount)
        setMode(.recording)
    }

    func showFinishing(_ message: String) {
        finishingMessage = message
        setMode(.finishing)
    }

    func update(_ assembler: TranscriptAssembler) {
        guard mode == .recording || mode == .finishing else { return }
        let hadText = hasText
        finalText = assembler.finalText
        tentativeText = assembler.tentativeText
        // 行の数が変わりうるので、文字が変わるたびに大きさを合わせる(ピルからカードへ伸びるときも)
        if hadText != hasText || hasText { scheduleResize() }
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

    var hasText: Bool { !(finalText + tentativeText).isEmpty }

    private func setMode(_ mode: Mode) {
        noticeTask?.cancel()
        let wasHidden = self.mode == .hidden
        self.mode = mode
        let panel = panel ?? makePanel()
        self.panel = panel
        if wasHidden { anchor = Self.anchorPoint() }
        resize()
        panel.orderFrontRegardless()
        scheduleResize()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 252, height: 44),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        // 停止ボタンを押せるようにする。フォーカスは奪わない(nonactivating・キーの窓にならない)
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let hostingView = FirstMouseHostingView(rootView: HUDView(hud: self))
        self.hostingView = hostingView
        panel.contentView = hostingView
        return panel
    }

    /// 中身の大きさに合わせる。SwiftUI が新しい中身で組み直してから測るため、次の回で行う
    private func scheduleResize() {
        DispatchQueue.main.async { [weak self] in self?.resize() }
    }

    private func resize() {
        guard let panel, let hostingView, mode != .hidden else { return }
        let size = hostingView.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        let frame = CGRect(x: anchor.x - size.width / 2, y: anchor.y, width: size.width, height: size.height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    /// マウスのある画面の下の中央(Dock の上)
    private static func anchorPoint() -> CGPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return .zero }
        return CGPoint(x: frame.midX, y: frame.minY + 24)
    }
}

/// キーの窓でなくても、最初のクリックをボタンに届ける
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// テーマごとの色
struct HUDPalette {
    let background: Color
    let border: Color?
    let text: Color
    let secondary: Color
    let accent: Color
    let accentDim: Color

    init(_ theme: HUDTheme) {
        switch theme {
        case .blueWhite:
            let blue = Color(red: 0.18, green: 0.42, blue: 1.0)
            background = .white
            border = blue
            text = Color(red: 0.06, green: 0.14, blue: 0.25)
            secondary = Color(red: 0.36, green: 0.42, blue: 0.52)
            accent = blue
            accentDim = blue.opacity(0.3)
        case .dark:
            background = Color(red: 0.055, green: 0.055, blue: 0.063).opacity(0.94)
            border = nil
            text = .white
            secondary = .white.opacity(0.55)
            accent = .white.opacity(0.9)
            accentDim = .white.opacity(0.3)
        }
    }
}

struct HUDView: View {
    let hud: RecordingHUD

    private var palette: HUDPalette { HUDPalette(hud.theme) }
    private var expanded: Bool {
        if case .notice = hud.mode { return true }
        return hud.hasText || hud.warning != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if expanded {
                message
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 2)
            }
            if case .notice = hud.mode {
                Spacer().frame(height: 10)
            } else {
                controls
            }
        }
        .frame(width: expanded ? 392 : 252)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(palette.background)
                .overlay {
                    if let border = palette.border {
                        RoundedRectangle(cornerRadius: 22).strokeBorder(border, lineWidth: 1.5)
                    }
                }
        )
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    /// 下の段: 停止ボタン(止めたあとは回る輪)・波形・マイク(または送信の札)
    private var controls: some View {
        HStack(spacing: 10) {
            if hud.mode == .finishing {
                Spinner(color: palette.accent).frame(width: 28, height: 28)
            } else {
                StopButton { hud.onStop?() }
            }
            Waveform(levels: hud.levels, color: hud.mode == .finishing ? palette.accentDim : palette.accent, flat: hud.mode == .finishing)
                .frame(maxWidth: .infinity)
            if hud.willSubmit {
                Text("↩ 貼ったあと送信")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().strokeBorder(palette.accent.opacity(0.5)))
                    .fixedSize()
            } else {
                if hud.engineLabel != "Soniox" {
                    Text(hud.engineLabel).font(.system(size: 11)).foregroundStyle(palette.secondary).fixedSize()
                }
                Image(systemName: "mic.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(hud.mode == .finishing ? palette.accentDim : palette.accent)
                    .frame(width: 18)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .frame(height: 44)
    }

    /// 上の段: 話している途中の文字(確定前は薄く)と知らせ。長いときは後ろを見せる
    private var message: some View {
        var text = AttributedString()
        if case let .notice(notice) = hud.mode {
            text = AttributedString(notice)
            text.foregroundColor = palette.text
        } else {
            let strong = hud.mode == .finishing ? palette.secondary : palette.text
            var final = AttributedString(hud.finalText)
            final.foregroundColor = strong
            var tentative = AttributedString(hud.tentativeText)
            tentative.foregroundColor = strong.opacity(0.5)
            text = final + tentative
            if let warning = hud.warning {
                var note = AttributedString(text.characters.isEmpty ? warning : "  \(warning)")
                note.foregroundColor = .orange
                text += note
            }
        }
        return Text(text)
            .font(.system(size: 14))
            .lineSpacing(3)
            .lineLimit(3)
            .truncationMode(.head)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 赤い停止ボタン(赤い丸に白い四角)。押すと止めて貼り付ける
struct StopButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color(red: 1.0, green: 0.23, blue: 0.19))
                RoundedRectangle(cornerRadius: 2.5).fill(.white).frame(width: 10, height: 10)
            }
            .frame(width: 28, height: 28)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("止めて貼り付ける")
    }
}

/// 点の波形。直近の音量を細い棒で並べる。止めたあとは平らにする
struct Waveform: View {
    let levels: [Float]
    let color: Color
    let flat: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 2, height: flat ? 3 : CGFloat(3 + min(1, max(0, level)) * 11))
            }
        }
        .frame(height: 20)
        .animation(.linear(duration: 0.08), value: levels)
    }
}

/// 確定を待つ間の回る輪(テーマの色で描く)
struct Spinner: View {
    let color: Color
    @State private var turning = false

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(turning ? 360 : 0))
        }
        .frame(width: 22, height: 22)
        .onAppear {
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { turning = true }
        }
    }
}

extension RecordingHUD {
    /// 動作の確かめ用。テーマごとに、話し始め・文字が出たとき・止めたあとの表示を PNG に描き出す
    static func renderSamples(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let samples: [(name: String, mode: Mode, text: Bool, submit: Bool)] = [
            ("start", .recording, false, false),
            ("text", .recording, true, false),
            ("finishing", .finishing, true, true),
            ("notice", .notice("入力欄が無いので、クリップボードに残しました"), false, false),
        ]
        for theme in HUDTheme.allCases {
            for sample in samples {
                let hud = RecordingHUD()
                hud.theme = theme
                hud.mode = sample.mode
                if sample.text {
                    hud.finalText = "1回実演で見せます。仕事のメモっぽい文を読み上げるので、"
                    hud.tentativeText = "どう変換されるか"
                }
                hud.levels = (0..<levelCount).map { Float(abs(sin(Double($0) * 1.7))) * 0.8 }
                hud.willSubmit = sample.submit
                let view = HUDView(hud: hud).padding(20).background(Color(white: 0.75))
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
                try? png.write(to: directory.appending(path: "hud-\(theme.rawValue)-\(sample.name).png"))
            }
        }
    }
}
