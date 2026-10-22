import AppKit
import Observation
import SwiftUI
import TsuzuriCore

/// 録音中の表示。話し始めは小さなピルで、文字が出ると上に伸びるカードになる(設計書「録音中の表示は段階4で直す」)。
/// フォーカスを奪わない窓に出し、貼り付け先がずれないようにする。停止ボタンだけはクリックで押せる。
/// 出る・伸びる・字が届く・貼り終えるところに動きを付ける。システムの「視差効果を減らす」が入っていれば、動きは透明の変化だけにする
@Observable
final class RecordingHUD {
    enum Mode: Equatable {
        case hidden
        case recording
        case finishing
        /// 貼り終えた。チェックを描いてから消す
        case done
        case notice(String)
    }

    fileprivate(set) var mode: Mode = .hidden
    /// 出ている(出るときと消えるときの動きに使う)
    fileprivate(set) var presented = false
    fileprivate(set) var finalText = ""
    fileprivate(set) var tentativeText = ""
    /// 届いた時刻ごとの切れ端。新しく出た字だけを浮かび上がらせる
    fileprivate(set) var arriving = ArrivingText()
    /// 知らせを出した時刻(知らせの字も浮かび上がらせる)
    fileprivate(set) var noticeArrival = 0.0
    /// 音量。直近の値を波形として並べる
    var level: Float = 0 {
        didSet {
            levels.removeFirst()
            levels.append(level)
        }
    }
    fileprivate(set) var levels = [Float](repeating: 0, count: RecordingHUD.levelCount)
    /// 録音中に分かった失敗(つながらないなど)。録音は続ける
    var warning: String?
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
    /// 1字が浮かび上がるまでの秒数と、落ち着いたものとしてまとめるまでの秒数
    static let arrivalDuration = 0.45
    static let settleSeconds = 0.9

    @ObservationIgnored fileprivate var panel: NSPanel?
    @ObservationIgnored fileprivate var hostingView: NSHostingView<HUDView>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    @ObservationIgnored private var pointerTask: Task<Void, Never>?
    /// カードの下の辺の中央(画面の座標)。大きさが変わっても、ここを動かさずに上へ伸ばす
    @ObservationIgnored private var anchor = CGPoint.zero

    func showRecording(engine: String) {
        engineLabel = engine
        finalText = ""
        tentativeText = ""
        arriving = ArrivingText()
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
        showPartial(final: assembler.finalText, tentative: assembler.tentativeText)
    }

    /// 話している途中の文字を出す(確定した文字・まだ変わりうる文字)
    func showPartial(final: String, tentative: String) {
        guard mode == .recording || mode == .finishing else { return }
        finalText = final
        tentativeText = tentative
        arriving.update(to: final + tentative, at: Self.now, settleAfter: Self.settleSeconds)
    }

    /// 短い知らせを出し、少したったら消す
    func notice(_ message: String) {
        noticeArrival = Self.now
        setMode(.notice(message))
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, self?.mode == .notice(message) else { return }
            self?.hide()
        }
    }

    /// 貼り終えた。停止ボタンの場所にチェックを描いてから消す
    func complete() {
        guard mode == .recording || mode == .finishing else { return hide() }
        setMode(.done)
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, self?.mode == .done else { return }
            self?.hide()
        }
    }

    /// 縮めて薄くしてから窓を下げる
    func hide() {
        noticeTask?.cancel()
        guard mode != .hidden else { return }
        guard presented else {
            finishHiding()
            return
        }
        withAnimation(.easeIn(duration: 0.16)) { presented = false }
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self, !self.presented else { return }
            self.finishHiding()
        }
    }

    var hasText: Bool { !(finalText + tentativeText).isEmpty }

    static var now: Double { Date().timeIntervalSinceReferenceDate }

    private func finishHiding() {
        mode = .hidden
        pointerTask?.cancel()
        panel?.orderOut(nil)
    }

    private func setMode(_ mode: Mode) {
        noticeTask?.cancel()
        dismissTask?.cancel()
        let wasHidden = self.mode == .hidden
        self.mode = mode
        let panel = panel ?? makePanel()
        self.panel = panel
        if wasHidden {
            // 出る前の小さく薄い姿を一度描いてから、ばねで広げる
            anchor = Self.anchorPoint()
            presented = false
            panel.setFrame(CGRect(origin: CGPoint(x: anchor.x - HUDLayout.panelSize.width / 2, y: anchor.y - HUDLayout.bottomMargin), size: HUDLayout.panelSize), display: false)
            panel.ignoresMouseEvents = true
            panel.orderFrontRegardless()
            panel.displayIfNeeded()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.mode != .hidden else { return }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.74)) { self.presented = true }
            }
        } else if !presented {
            // 消えかけていたら、その場で戻す
            withAnimation(.spring(response: 0.38, dampingFraction: 0.74)) { presented = true }
        }
        trackPointer()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: HUDLayout.panelSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // 影はカードに付ける(窓の影は、大きさが動くあいだ追いつかない)
        panel.hasShadow = false
        // フォーカスは奪わない。クリックはカードの上だけで受ける(trackPointer)
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let hostingView = FirstMouseHostingView(rootView: HUDView(hud: self))
        self.hostingView = hostingView
        panel.contentView = hostingView
        return panel
    }

    /// 窓はカードが一番大きくなったときの大きさで固定し、カードは下の辺を動かさずに中で伸び縮みさせる。
    /// 透明なところのクリックは下の窓へ通したいので、マウスがカードの上にあるときだけクリックを受ける
    private func trackPointer() {
        pointerTask?.cancel()
        pointerTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.updatePointer()
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func updatePointer() {
        guard let panel, let hostingView, mode != .hidden else { return }
        let fitting = hostingView.fittingSize
        let card = CGSize(
            width: fitting.width - HUDLayout.sideMargin * 2,
            height: fitting.height - HUDLayout.topMargin - HUDLayout.bottomMargin
        )
        let rect = CGRect(x: anchor.x - card.width / 2, y: anchor.y, width: card.width, height: card.height)
        let inside = presented && rect.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
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

/// 窓の大きさと、カードのまわりの影のための余白
enum HUDLayout {
    static let sideMargin: CGFloat = 20
    static let topMargin: CGFloat = 14
    static let bottomMargin: CGFloat = 26
    /// カードが一番大きくなったとき(幅392・文字3行)に影まで収まる大きさ
    static let panelSize = CGSize(width: 392 + sideMargin * 2, height: 176)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var palette: HUDPalette { HUDPalette(hud.theme) }
    private var expanded: Bool {
        if case .notice = hud.mode { return true }
        return hud.hasText || hud.warning != nil
    }

    var body: some View {
        card
            .scaleEffect(hud.presented || reduceMotion ? 1 : 0.82, anchor: .bottom)
            .offset(y: hud.presented || reduceMotion ? 0 : 10)
            .opacity(hud.presented ? 1 : 0)
            .padding(.horizontal, HUDLayout.sideMargin)
            .padding(.top, HUDLayout.topMargin)
            .padding(.bottom, HUDLayout.bottomMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            // ピルからカードへ伸びる・行が増える・停止から確定待ちへ変わるところを、ばねでつなぐ。
            // カードの大きさと窓の中の位置を同じ動きにして、下の辺を動かさない
            .animation(.spring(response: 0.42, dampingFraction: 0.8), value: expanded)
            .animation(.smooth(duration: 0.3), value: hud.arriving.text)
            .animation(.spring(response: 0.36, dampingFraction: 0.78), value: hud.mode)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: hud.willSubmit)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            if expanded {
                message
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 2)
                    .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 8)))
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
        .shadow(color: .black.opacity(hud.theme == .dark ? 0.35 : 0.18), radius: 12, y: 5)
    }

    /// 下の段: 停止ボタン(止めたあとは回る輪、貼り終えたらチェック)・波形・マイク(または送信の札)
    private var controls: some View {
        HStack(spacing: 10) {
            ZStack {
                switch hud.mode {
                case .finishing:
                    Spinner(color: palette.accent)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                case .done:
                    CheckMark(color: palette.accent)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                default:
                    StopButton(pulsing: hud.mode == .recording && !reduceMotion) { hud.onStop?() }
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .frame(width: 28, height: 28)
            Waveform(levels: hud.levels, color: hud.mode == .recording ? palette.accent : palette.accentDim, flat: hud.mode != .recording)
                .frame(maxWidth: .infinity)
            if hud.willSubmit {
                Text("↩ 貼ったあと送信")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().strokeBorder(palette.accent.opacity(0.5)))
                    .fixedSize()
                    .transition(.scale(scale: 0.6, anchor: .trailing).combined(with: .opacity))
            } else {
                if hud.engineLabel != "Soniox" {
                    // Mac 内で認識していることが分かるようにする(途中の文字は Apple の認識、貼る文字は WhisperKit)
                    Text(hud.engineLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().strokeBorder(palette.accent.opacity(0.5)))
                        .fixedSize()
                        .help("Mac 内で認識しています。貼る文字は止めてから作ります")
                }
                Image(systemName: "mic.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(hud.mode == .recording ? palette.accent : palette.accentDim)
                    .frame(width: 18)
                    .transition(.opacity)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .frame(height: 44)
    }

    /// 上の段: 話している途中の文字(確定前は薄く)と知らせ。長いときは後ろを見せる。
    /// 新しく届いた字は、ぼかしと透明から1字ずつ浮かび上がる
    private var message: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !isTextMoving)) { timeline in
            composedText
                .font(.system(size: 14))
                .lineSpacing(3)
                .lineLimit(3)
                .truncationMode(.head)
                .contentTransition(.identity)
                .textRenderer(ArrivalRenderer(now: timeline.date.timeIntervalSinceReferenceDate, reduceMotion: reduceMotion))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var isTextMoving: Bool {
        let now = RecordingHUD.now
        if case .notice = hud.mode { return now - hud.noticeArrival < 1 }
        return hud.arriving.isAnimating(at: now, duration: RecordingHUD.settleSeconds)
    }

    /// 色と届いた時刻の印を付けた文字。切れ端ごとの Text を差し込みでつなぐ
    private var composedText: Text {
        if case let .notice(notice) = hud.mode {
            return Text(verbatim: notice)
                .foregroundStyle(palette.text)
                .customAttribute(ArrivalAttribute(time: hud.noticeArrival))
        }
        let strong = hud.mode == .recording ? palette.text : palette.secondary
        var text = Text(verbatim: "")
        for segment in hud.arriving.segments(finalLength: hud.finalText.count) {
            var piece = Text(verbatim: segment.text).foregroundStyle(segment.isFinal ? strong : strong.opacity(0.5))
            if let arrival = segment.arrival {
                piece = piece.customAttribute(ArrivalAttribute(time: arrival))
            }
            text = Text("\(text)\(piece)")
        }
        if let warning = hud.warning {
            let note = Text(verbatim: hud.hasText ? "  \(warning)" : warning).foregroundStyle(.orange)
            text = Text("\(text)\(note)")
        }
        return text
    }
}

/// 字に付ける、届いた時刻の印
struct ArrivalAttribute: TextAttribute {
    var time: Double
}

/// 届いた時刻の印が付いた字を、少しずつ遅らせながら、ぼかし・透明・少し下から浮かび上がらせる
struct ArrivalRenderer: TextRenderer {
    var now: Double
    var reduceMotion: Bool

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                guard let arrival = run[ArrivalAttribute.self]?.time else {
                    context.draw(run)
                    continue
                }
                // 長い切れ端でも、最後の字が0.35秒以内に動き出すよう、字ごとの遅れを詰める
                let stagger = min(0.03, 0.35 / Double(max(run.count, 1)))
                for (index, slice) in run.enumerated() {
                    let elapsed = now - arrival - Double(index) * stagger
                    let progress = min(1, max(0, elapsed / RecordingHUD.arrivalDuration))
                    guard progress < 1 else {
                        context.draw(slice)
                        continue
                    }
                    let eased = 1 - pow(1 - progress, 3)
                    var copy = context
                    copy.opacity = eased
                    if !reduceMotion {
                        copy.translateBy(x: 0, y: (1 - eased) * 6)
                        copy.addFilter(.blur(radius: (1 - eased) * 4))
                    }
                    copy.draw(slice)
                }
            }
        }
    }
}

/// 赤い停止ボタン(赤い丸に白い四角)。録音中は外へ広がる輪で脈打つ。押すと止めて貼り付ける
struct StopButton: View {
    var pulsing = false
    let action: () -> Void
    @State private var pulse = false

    private static let red = Color(red: 1.0, green: 0.23, blue: 0.19)

    var body: some View {
        Button(action: action) {
            ZStack {
                if pulsing {
                    Circle()
                        .stroke(Self.red.opacity(0.6), lineWidth: 2)
                        .scaleEffect(pulse ? 1.34 : 1)
                        .opacity(pulse ? 0 : 0.9)
                }
                Circle().fill(Self.red)
                RoundedRectangle(cornerRadius: 2.5).fill(.white).frame(width: 10, height: 10)
            }
            .frame(width: 28, height: 28)
            .contentShape(Circle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .help("止めて貼り付ける")
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

/// 押している間だけ少し縮める
struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// 点の波形。直近の音量を細い棒で並べる。止めたあとは平らにする。
/// 棒をまとめて1つの図形で描き、カードが伸び縮みする間も棒の並びがくずれないようにする
struct Waveform: View {
    let levels: [Float]
    let color: Color
    let flat: Bool

    var body: some View {
        WaveBars(levels: LevelVector(levels.map { Double(min(1, max(0, $0))) }), flatness: flat ? 1 : 0)
            .fill(color)
            .frame(width: WaveBars.width(count: levels.count), height: 20)
            .animation(.easeOut(duration: 0.09), value: levels)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: flat)
    }
}

/// 波形の棒の形。音量の並びと平らさを、動きの途中の値として補える
struct WaveBars: Shape {
    var levels: LevelVector
    /// 1で平ら
    var flatness: Double

    static let barWidth: CGFloat = 2
    static let spacing: CGFloat = 2.5

    static func width(count: Int) -> CGFloat {
        CGFloat(count) * barWidth + CGFloat(max(count - 1, 0)) * spacing
    }

    var animatableData: AnimatablePair<LevelVector, Double> {
        get { AnimatablePair(levels, flatness) }
        set {
            levels = newValue.first
            flatness = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (index, level) in levels.values.enumerated() {
            let height = 3 + CGFloat(min(1, max(0, level)) * (1 - min(1, max(0, flatness)))) * 15
            let x = rect.minX + CGFloat(index) * (Self.barWidth + Self.spacing)
            path.addRoundedRect(in: CGRect(x: x, y: rect.midY - height / 2, width: Self.barWidth, height: height), cornerSize: CGSize(width: 1, height: 1))
        }
        return path
    }
}

/// 音量の並び。動きの途中の値を補うための足し引きを持つ
nonisolated struct LevelVector: VectorArithmetic {
    var values: [Double]

    init(_ values: [Double]) {
        self.values = values
    }

    static var zero: LevelVector { LevelVector([]) }

    static func + (lhs: LevelVector, rhs: LevelVector) -> LevelVector {
        combine(lhs, rhs, +)
    }

    static func - (lhs: LevelVector, rhs: LevelVector) -> LevelVector {
        combine(lhs, rhs, -)
    }

    mutating func scale(by rhs: Double) {
        values = values.map { $0 * rhs }
    }

    var magnitudeSquared: Double {
        values.reduce(0) { $0 + $1 * $1 }
    }

    /// 長さが違うときは、足りない方を0とみなす
    private static func combine(_ lhs: LevelVector, _ rhs: LevelVector, _ operation: (Double, Double) -> Double) -> LevelVector {
        let count = max(lhs.values.count, rhs.values.count)
        return LevelVector((0..<count).map { index in
            operation(index < lhs.values.count ? lhs.values[index] : 0, index < rhs.values.count ? rhs.values[index] : 0)
        })
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

/// 貼り終えたときのチェック。線を引くように描く
struct CheckMark: View {
    let color: Color
    @State private var drawn = false

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.14))
            CheckShape()
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .frame(width: 11, height: 8)
        }
        .frame(width: 24, height: 24)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3).delay(0.08)) { drawn = true }
        }
    }
}

struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

extension RecordingHUD {
    /// 動作の確かめ用。テーマごとに、話し始め・文字が出たとき・止めたあと・知らせの表示を PNG に描き出す
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
                hud.presented = true
                if sample.text {
                    hud.finalText = "1回実演で見せます。仕事のメモっぽい文を読み上げるので、"
                    hud.tentativeText = "どう変換されるか"
                    hud.arriving.update(to: hud.finalText + hud.tentativeText, at: 0, settleAfter: 0)
                }
                hud.levels = (0..<levelCount).map { Float(abs(sin(Double($0) * 1.7))) * 0.8 }
                hud.willSubmit = sample.submit
                let view = HUDView(hud: hud).background(Color(white: 0.75))
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
                try? png.write(to: directory.appending(path: "hud-\(theme.rawValue)-\(sample.name).png"))
            }
        }
    }
}

extension RecordingHUD {
    /// 動作の確かめ用。本物の窓に出し、音量と文字を流しながら、窓の中身を PNG に写し取り、窓の大きさを書き出す。
    /// frames を付けると、動きを確かめるために 1/30 秒ごとの絵も残す
    static func simulate(to directory: URL, theme: HUDTheme, frames: Bool = false) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let hud = RecordingHUD()
        hud.theme = theme
        var frameIndex = 0
        func capture(_ name: String) {
            guard let panel = hud.panel, let view = panel.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "\(name).png"))
        }
        func snap(_ name: String) {
            capture(name)
            print("\(name): 窓 \(hud.panel?.frame.size ?? .zero) 中身の大きさ \(hud.hostingView?.fittingSize ?? .zero) 音量の列 \(hud.levels.suffix(4).map { String(format: "%.2f", $0) })")
        }
        /// 指定の秒数のあいだ待つ。frames のときは 1/30 秒ごとに絵を残す
        func film(_ seconds: Double) async {
            guard frames else {
                try? await Task.sleep(for: .seconds(seconds))
                return
            }
            let end = Date().addingTimeInterval(seconds)
            while Date() < end {
                capture(String(format: "frame-%04d", frameIndex))
                frameIndex += 1
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
        hud.showRecording(engine: "Soniox")
        let feeder = Task { @MainActor in
            var phase = 0.0
            while !Task.isCancelled {
                phase += 0.45
                hud.level = Float(0.15 + 0.45 * abs(sin(phase)) * Double.random(in: 0.6...1))
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        await film(1)
        snap("1-start-a")
        await film(0.3)
        snap("2-start-b")
        var assembler = TranscriptAssembler()
        assembler.apply([.init(text: "1回実演で見せます。", isFinal: true), .init(text: "仕事のメモ", isFinal: false)])
        hud.update(assembler)
        await film(0.12)
        snap("3a-text-arriving")
        await film(0.4)
        snap("3-text-short")
        assembler.apply([.init(text: "仕事のメモっぽい文を読み上げるので、", isFinal: true), .init(text: "どう変換されるかを見てください。長い文になったときの見え方も", isFinal: false)])
        hud.update(assembler)
        await film(0.8)
        snap("4-text-long")
        feeder.cancel()
        hud.willSubmit = true
        hud.showFinishing("確定を待っています")
        await film(0.8)
        snap("5-finishing")
        hud.complete()
        await film(0.25)
        snap("6-done")
        await film(0.8)
        hud.hide()
        await film(0.3)
    }
}
