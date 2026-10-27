import Foundation

// Windows virtual-key codes, which is what the host expects
enum HostKey: Int16, CaseIterable, Identifiable {
    case escape = 0x1B
    case tab = 0x09
    case windows = 0x5B
    case enter = 0x0D
    case backspace = 0x08

    var id: Int16 { rawValue }

    var title: String {
        switch self {
        case .escape: "Esc"
        case .tab: "Tab"
        case .windows: "Win"
        case .enter: "Enter"
        case .backspace: "Delete"
        }
    }

    var symbol: String {
        switch self {
        case .escape: "escape"
        case .tab: "arrow.right.to.line"
        case .windows: "square.grid.2x2"
        case .enter: "return"
        case .backspace: "delete.left"
        }
    }
}

enum HostKeyboard {
    private static let leftAlt: Int16 = 0xA4

    static func press(_ key: HostKey) {
        send(key.rawValue, modifiers: 0)
    }

    static func switchWindows() {
        let alt = CChar(MODIFIER_ALT)
        LiSendKeyboardEvent(leftAlt, CChar(KEY_ACTION_DOWN), alt)
        send(HostKey.tab.rawValue, modifiers: alt)
        LiSendKeyboardEvent(leftAlt, CChar(KEY_ACTION_UP), 0)
    }

    private static func send(_ code: Int16, modifiers: CChar) {
        LiSendKeyboardEvent(code, CChar(KEY_ACTION_DOWN), modifiers)
        LiSendKeyboardEvent(code, CChar(KEY_ACTION_UP), modifiers)
    }
}
