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
