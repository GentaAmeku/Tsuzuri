import CoreGraphics
import Foundation
import TsuzuriCore

/// 右⌘とほかのキー、録音中の Esc を見る能動的な CGEventTap。
/// 能動的なものはアクセシビリティの権限で動き、キーを相手のアプリに届けないこともできる(設計書「右⌘の操作と状態」)
final class KeyMonitor {
    /// このアプリが送ったキー(⌘V)の印。自分の出来事として数えない
    static let syntheticMarker: Int64 = 0x5453_5A52

    private static let rightCommandKeyCode: Int64 = 54
    private static let escapeKeyCode: Int64 = 53
    /// 修飾キーの keyCode と、押されているときに立つ機器ごとの印(IOKit の NX_DEVICE*KEYMASK)
    private static let modifierMasks: [Int64: UInt64] = [
        55: 0x0000_0008, // 左⌘
        56: 0x0000_0002, // 左 shift
        60: 0x0000_0004, // 右 shift
        58: 0x0000_0020, // 左 option
        61: 0x0000_0040, // 右 option
        59: 0x0000_0001, // 左 control
        62: 0x0000_2000, // 右 control
        63: CGEventFlags.maskSecondaryFn.rawValue // fn
    ]
    private static let rightCommandMask: UInt64 = 0x0000_0010

    private let handler: (HotkeyStateMachine.Event) -> Bool
    private var tap: CFMachPort?
    private var rightCommandDown = false

    init(handler: @escaping (HotkeyStateMachine.Event) -> Bool) {
        self.handler = handler
    }

    /// 権限が無いと作れずに false を返す
    func start() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: keyMonitorCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// 戻り値は、そのキーを相手のアプリに届けないか
    fileprivate func process(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // 処理が遅れて OS に止められたら、すぐ戻す
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard event.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        switch type {
        case .flagsChanged:
            if keyCode == Self.rightCommandKeyCode {
                let down = event.flags.rawValue & Self.rightCommandMask != 0
                guard down != rightCommandDown else { return false }
                rightCommandDown = down
                return handler(down ? .keyDown(at: now) : .keyUp(at: now))
            }
            // ほかの修飾キーは押したときだけ数える(⌘⇧4 などの同時押し)
            if let mask = Self.modifierMasks[keyCode], event.flags.rawValue & mask != 0 {
                return handler(.otherKeyDown(at: now))
            }
            return false
        case .keyDown:
            return handler(keyCode == Self.escapeKeyCode ? .escape : .otherKeyDown(at: now))
        default:
            return false
        }
    }
}

/// 出来事はメインの糸の run loop で届く
nonisolated private func keyMonitorCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    // run loop がメインの糸なので、ここはメインアクターの上で動いている
    nonisolated(unsafe) let pointer = userInfo
    nonisolated(unsafe) let unsafeEvent = event
    let consume = MainActor.assumeIsolated {
        Unmanaged<KeyMonitor>.fromOpaque(pointer).takeUnretainedValue().process(type, unsafeEvent)
    }
    return consume ? nil : Unmanaged.passUnretained(event)
}
