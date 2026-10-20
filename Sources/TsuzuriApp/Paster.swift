import AppKit
import ApplicationServices
import TsuzuriCore

/// クリップボードを借りて ⌘V で貼り、0.3秒後に元の中身へ戻す(設計書「貼り付けはクリップボードを借りて、すぐ戻す」)
enum Paster {
    enum Outcome {
        case pasted
        case clipboardOnly
    }

    /// クリップボード履歴のアプリに残さないための印(nspasteboard.org)
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    static let restoreDelay = Duration.milliseconds(300)

    static func paste(_ text: String) async -> Outcome {
        let pasteboard = NSPasteboard.general
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard PasteDecision.decide(focus: focusedElement(), appBundleID: app) == .paste else {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return .clipboardOnly
        }
        let saved = snapshot(pasteboard)
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: transientType)
        pasteboard.writeObjects([item])
        let ours = pasteboard.changeCount
        sendCommandV()
        try? await Task.sleep(for: restoreDelay)
        // 戻す前に本人が別のものをコピーしていたら、戻さない
        if pasteboard.changeCount == ours {
            pasteboard.clearContents()
            if !saved.isEmpty {
                pasteboard.writeObjects(saved)
            }
        }
        return .pasted
    }

    /// 元の中身を、型ごとのデータで写し取る。戻すときも履歴のアプリに二重に残さないよう印を付ける
    static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { original in
            let copy = NSPasteboardItem()
            for type in original.types {
                if let data = original.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            copy.setData(Data(), forType: transientType)
            return copy
        }
    }

    static func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        // 送っている間に本人が押している修飾キーが混ざらないようにする
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        let vKey: CGKeyCode = 9
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: keyDown) else { continue }
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: KeyMonitor.syntheticMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    /// フォーカスのある要素をアクセシビリティ API で読む。読めなければ nil
    static func focusedElement() -> PasteDecision.Focus? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.3)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        var range: CFTypeRef?
        let hasRange = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success
        return PasteDecision.Focus(role: role as? String ?? "", acceptsText: settable.boolValue || hasRange)
    }
}
