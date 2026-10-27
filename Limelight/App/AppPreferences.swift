import Foundation

// Settings added by this fork live in UserDefaults; the original ones stay in the
// Core Data Settings entity so no model migration is needed.
enum ResolutionMode: String, CaseIterable, Sendable {
    // Size the stream to the display it starts on (Apollo builds a matching virtual display)
    case matchDisplay
    // Use the width and height stored in the Settings entity
    case fixed
}

// Mirrors the anonymous enum behind TemporarySettings.preferredCodec, which Swift cannot see
enum CodecPreference: UInt32, CaseIterable, Sendable {
    case automatic = 0
    case h264 = 1
    case hevc = 2
    case av1 = 3
}

enum TabletopPanel: String, CaseIterable, Sendable {
    case trackpad, gamepad, controls
}

enum AppPreferences {
    static let resolutionModeKey = "ResolutionMode"
    static let useVirtualDisplayKey = "UseVirtualDisplay"
    static let virtualDisplayScaleKey = "VirtualDisplayScale"
    static let tabletopPanelKey = "TabletopPanel"
    // Read by Utils.m when pairing
    static let pairingDeviceNameKey: String = pairingDeviceNameKey

    static var resolutionMode: ResolutionMode {
        UserDefaults.standard.string(forKey: resolutionModeKey).flatMap(ResolutionMode.init) ?? .matchDisplay
    }

    static var useVirtualDisplay: Bool {
        UserDefaults.standard.bool(forKey: useVirtualDisplayKey)
    }

    // Percent; 100 means the virtual display matches the stream exactly
    static var virtualDisplayScale: Int {
        let scale = UserDefaults.standard.integer(forKey: virtualDisplayScaleKey)
        return scale > 0 ? scale : 100
    }

    static var tabletopPanel: TabletopPanel {
        UserDefaults.standard.string(forKey: tabletopPanelKey).flatMap(TabletopPanel.init) ?? .trackpad
    }

    static var pairingDeviceName: String? {
        let name = UserDefaults.standard.string(forKey: pairingDeviceNameKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return name?.isEmpty == false ? name : nil
    }
}
