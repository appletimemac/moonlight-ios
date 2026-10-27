import Foundation

enum HostReachability: Sendable {
    case unknown, offline, online
}

enum HostPairing: Sendable {
    case unknown, unpaired, paired
}

struct HostSnapshot: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var reachability: HostReachability
    var pairing: HostPairing
    var runningAppID: String?
    var address: String?
    var canWake: Bool
    var isNvidiaGameStream: Bool
    var apolloAccess: ApolloAccess?
    var virtualDisplayCapable: Bool
    var hasCachedApps: Bool

    nonisolated static func identifier(for host: TemporaryHost) -> String {
        host.uuid.isEmpty ? "address:\(host.activeAddress ?? host.name)" : host.uuid
    }

    init(_ host: TemporaryHost) {
        id = Self.identifier(for: host)
        name = host.name
        reachability = switch host.state {
        case .online: .online
        case .offline: .offline
        default: .unknown
        }
        pairing = switch host.pairState {
        case .paired: .paired
        case .unpaired: .unpaired
        default: .unknown
        }
        let game = host.currentGame ?? "0"
        runningAppID = game == "0" || game.isEmpty ? nil : game
        address = host.activeAddress
        canWake = host.mac != nil && host.mac != "00:00:00:00:00:00"
        isNvidiaGameStream = host.isNvidiaServerSoftware
        apolloAccess = host.apolloPermissions >= 0 ? ApolloAccess(mask: UInt32(host.apolloPermissions)) : nil
        virtualDisplayCapable = host.virtualDisplayCapable
        hasCachedApps = host.appList.count > 0
    }
}

struct AppSnapshot: Identifiable, Hashable, Sendable {
    var id: String { "\(hostID)/\(appID)" }
    let hostID: String
    let appID: String
    var name: String
    var isHidden: Bool
    var supportsHDR: Bool
    var boxArtPath: String?
}

// Apollo's per-client permission bits (Apollo src/crypto.h). Apollo grants the
// first paired client everything and later ones only view and list, which
// silently drops all of their input.
struct ApolloAccess: Hashable, Sendable {
    struct Permission: OptionSet, Hashable, Sendable {
        let rawValue: UInt32

        static let controllerInput = Permission(rawValue: 0x100)
        static let touchInput = Permission(rawValue: 0x200)
        static let penInput = Permission(rawValue: 0x400)
        static let mouseInput = Permission(rawValue: 0x800)
        static let keyboardInput = Permission(rawValue: 0x1000)
        static let clipboardSet = Permission(rawValue: 0x10000)
        static let clipboardRead = Permission(rawValue: 0x20000)
        static let serverCommands = Permission(rawValue: 0x100000)
        static let listApps = Permission(rawValue: 0x1000000)
        static let viewStreams = Permission(rawValue: 0x2000000)
        static let launchApps = Permission(rawValue: 0x4000000)
    }

    struct Gap: Hashable, Sendable {
        let permission: Permission
        let title: String
    }

    let granted: Permission

    init(mask: UInt32) {
        granted = Permission(rawValue: mask)
    }

    // What this device needs to stream and play, in the order Apollo's web UI lists it.
    private static let needed: [Gap] = [
        Gap(permission: .launchApps, title: "Launch Apps"),
        Gap(permission: .controllerInput, title: "Controller Input"),
        Gap(permission: .touchInput, title: "Touch Input"),
        Gap(permission: .mouseInput, title: "Mouse Input"),
        Gap(permission: .keyboardInput, title: "Keyboard Input"),
    ]

    var missing: [Gap] {
        Self.needed.filter { !granted.contains($0.permission) }
    }

    var canUseClipboard: Bool {
        granted.contains([.clipboardRead, .clipboardSet])
    }

    var hasNoInput: Bool {
        granted.isDisjoint(with: [.controllerInput, .touchInput, .penInput, .mouseInput, .keyboardInput])
    }
}

struct LibraryAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var helpURL: URL?

    static let troubleshootingURL = URL(string: "https://github.com/moonlight-stream/moonlight-docs/wiki/Troubleshooting")!
}

struct PairingSession: Identifiable {
    enum Phase: Equatable {
        case naming
        case requesting
        case showingPIN(String)
    }

    let id = UUID()
    let hostID: String
    let hostName: String
    var phase: Phase
}

// Another app is running on the host when the user picks one.
struct AppConflict: Identifiable {
    let id = UUID()
    let requested: AppSnapshot
    let running: AppSnapshot
}
