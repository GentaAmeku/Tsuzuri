import Foundation
import Testing
@testable import TsuzuriCore

@Suite("右⌘の操作")
struct HotkeyStateMachineTests {
    @Test("押した瞬間は手元で録るだけで、まだつながない")
    func pressStartsCaptureOnly() {
        var machine = HotkeyStateMachine()
        #expect(machine.handle(.keyDown(at: 0)) == .init([.startCapture]))
        #expect(machine.state == .armed(pressedAt: 0))
    }

    @Test("0.2秒以内に C を押したら ⌘C とみなして録音を捨てる")
    func chordDiscards() {
        var machine = HotkeyStateMachine()
        _ = machine.handle(.keyDown(at: 0))
        #expect(machine.handle(.otherKeyDown(at: 0.1)) == .init([.discard]))
        #expect(machine.state == .idle)
    }

    @Test("短く押して離したらつなぎ、もう一度押した瞬間に止める")
    func shortPressToggles() {
        var machine = HotkeyStateMachine()
        _ = machine.handle(.keyDown(at: 0))
        #expect(machine.handle(.keyUp(at: 0.1)) == .init([.connect]))
        #expect(machine.handle(.keyUp(at: 3)) == .init())
        #expect(machine.handle(.keyDown(at: 5)) == .init([.stop]))
        #expect(machine.state == .finishing)
    }

    @Test("0.2秒たったらつなぎ、0.5秒以上押して離したら止める")
    func longPressHolds() {
        var machine = HotkeyStateMachine()
        _ = machine.handle(.keyDown(at: 0))
        #expect(machine.handle(.chordWindowElapsed) == .init([.connect]))
        #expect(machine.handle(.keyUp(at: 4)) == .init([.stop]))
    }

    @Test("0.2秒を過ぎて0.5秒未満で離したら、押すたびの切り替えとして録り続ける")
    func mediumPressKeepsRecording() {
        var machine = HotkeyStateMachine()
        _ = machine.handle(.keyDown(at: 0))
        _ = machine.handle(.chordWindowElapsed)
        #expect(machine.handle(.keyUp(at: 0.3)) == .init())
        #expect(machine.state == .recording(pressedAt: 0, keyHeld: false))
        #expect(machine.handle(.keyDown(at: 2)) == .init([.stop]))
    }

    @Test("録音中にほかのキーを押しても止めない")
    func otherKeyWhileRecordingIsIgnored() {
        var machine = HotkeyStateMachine()
        _ = machine.handle(.keyDown(at: 0))
        _ = machine.handle(.chordWindowElapsed)
        #expect(machine.handle(.otherKeyDown(at: 1)) == .init())
        #expect(machine.state == .recording(pressedAt: 0, keyHeld: true))
    }

    @Test("録音中の Esc は取り消し、相手のアプリに届けない")
    func escapeCancels() {
        var machine = HotkeyStateMachine()
        _ = machine.handle(.keyDown(at: 0))
        _ = machine.handle(.keyUp(at: 0.1))
        #expect(machine.handle(.escape) == .init([.cancel], consume: true))
        #expect(machine.state == .idle)
    }

    @Test("待機中の Esc はそのまま相手のアプリに届ける")
    func escapeWhileIdlePassesThrough() {
        var machine = HotkeyStateMachine()
        #expect(machine.handle(.escape) == .init())
    }

    @Test("確定を待つ間は右⌘を押しても始めず、終わったら待機へ戻る")
    func finishingIgnoresPress() {
        var machine = HotkeyStateMachine()
        _ = machine.handle(.keyDown(at: 0))
        _ = machine.handle(.keyUp(at: 0.1))
        _ = machine.handle(.keyDown(at: 1))
        #expect(machine.handle(.keyDown(at: 1.5)) == .init())
        _ = machine.handle(.finished)
        #expect(machine.state == .idle)
        #expect(machine.handle(.keyDown(at: 2)) == .init([.startCapture]))
    }

    @Test("押している間だけ録る方式では、短すぎる押下を捨てる")
    func holdModeDiscardsTap() {
        var machine = HotkeyStateMachine(settings: HotkeySettings(mode: .hold))
        _ = machine.handle(.keyDown(at: 0))
        #expect(machine.handle(.keyUp(at: 0.1)) == .init([.discard]))
    }

    @Test("押すたびに切り替える方式では、長く押しても離したときに止めない")
    func toggleModeIgnoresLongPress() {
        var machine = HotkeyStateMachine(settings: HotkeySettings(mode: .toggle))
        _ = machine.handle(.keyDown(at: 0))
        _ = machine.handle(.chordWindowElapsed)
        #expect(machine.handle(.keyUp(at: 3)) == .init())
        #expect(machine.handle(.keyDown(at: 5)) == .init([.stop]))
    }
}

@Suite("録音中の Return(段階4)")
struct HotkeyReturnTests {
    func recording() -> HotkeyStateMachine {
        var machine = HotkeyStateMachine()
        _ = machine.handle(.keyDown(at: 0))
        _ = machine.handle(.keyUp(at: 0.1))
        return machine
    }

    @Test("録音中に Return を押すと止め、貼り付けたあとに送る。Return は相手のアプリに届けない")
    func submitsWhileRecording() {
        var machine = recording()
        #expect(machine.handle(.returnKey(at: 3)) == .init([.stop, .submitAfterPaste], consume: true))
        #expect(machine.state == .finishing)
        #expect(machine.submitRequested)
    }

    @Test("確定を待つ間の Return も送る。何度押しても送るのは1回")
    func submitsOnceWhileFinishing() {
        var machine = recording()
        _ = machine.handle(.keyDown(at: 3))
        #expect(machine.handle(.returnKey(at: 3.2)) == .init([.submitAfterPaste], consume: true))
        #expect(machine.handle(.returnKey(at: 3.3)) == .init(consume: true))
    }

    @Test("押してすぐの Return は ⌘Return とみなし、録音を捨てて相手のアプリへ届ける")
    func chordWithReturn() {
        var machine = HotkeyStateMachine()
        _ = machine.handle(.keyDown(at: 0))
        #expect(machine.handle(.returnKey(at: 0.1)) == .init([.discard]))
        #expect(machine.state == .idle)
    }

    @Test("待機中の Return には何もしない")
    func ignoresWhenIdle() {
        var machine = HotkeyStateMachine()
        #expect(machine.handle(.returnKey(at: 0)) == .init())
    }

    @Test("貼り終えたら、次の録音では送らない")
    func resetsAfterFinished() {
        var machine = recording()
        _ = machine.handle(.returnKey(at: 3))
        _ = machine.handle(.finished)
        #expect(!machine.submitRequested)
        _ = machine.handle(.keyDown(at: 10))
        _ = machine.handle(.keyUp(at: 10.1))
        #expect(machine.handle(.keyDown(at: 12)) == .init([.stop]))
        #expect(!machine.submitRequested)
    }

    @Test("Esc で取り消したら、送らない")
    func cancelClearsSubmit() {
        var machine = recording()
        _ = machine.handle(.returnKey(at: 3))
        #expect(machine.handle(.escape) == .init([.cancel], consume: true))
        #expect(!machine.submitRequested)
    }
}

@Suite("キーの設定(段階4)")
struct HotkeySettingsTests {
    @Test("保存した設定は、録音キーを足したあとも読める")
    func decodesSavedSettings() throws {
        let saved = #"{"key":"rightCommand","mode":"hybrid","longPressSeconds":0.5,"chordWindowSeconds":0.2}"#
        let settings = try JSONDecoder().decode(HotkeySettings.self, from: Data(saved.utf8))
        #expect(settings == HotkeySettings())
    }

    @Test("録音キーと方式は、画面に出す名前を持つ")
    func labels() {
        #expect(HotkeySettings.Key.allCases.map(\.label) == ["右⌘", "右⌥", "fn"])
        #expect(HUDTheme.allCases.map(\.label) == ["青と白", "黒"])
    }
}
