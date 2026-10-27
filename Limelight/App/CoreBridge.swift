import Foundation
import os

// The Objective-C Log() is variadic, which Swift cannot call
let appLog = Logger(subsystem: "com.RRGSyndicate.Moonlight", category: "App")

// Moves Objective-C core objects (hosts, apps, managers) across threads. They are
// not Sendable, but the core already shares them across its own worker threads
// behind atomic properties, exactly as the old UIKit front end did.
struct Unchecked<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

enum Background {
    // The core's network calls block, so they run on a global queue, never the main thread.
    static func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: work())
            }
        }
    }
}

// Receives the core's delegate callbacks, which arrive on arbitrary threads, and
// replays them on the main actor in the order they were sent (pairing relies on
// startPairing landing before any failure).
final class CoreCallbacks: NSObject, DiscoveryCallback, PairCallback, AppAssetCallback, @unchecked Sendable {
    @MainActor weak var library: HostLibrary?

    private func onMain(_ body: @escaping @MainActor @Sendable (HostLibrary) -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                if let library { body(library) }
            }
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let library = self.library { body(library) }
                }
            }
        }
    }

    func updateAllHosts(_ hosts: [Any]!) {
        let found = Unchecked((hosts ?? []).compactMap { $0 as? TemporaryHost })
        onMain { $0.discoveryFound(found.value) }
    }

    func startPairing(_ PIN: String!) {
        let pin = PIN ?? ""
        onMain { $0.pairingShowsPIN(pin) }
    }

    func pairSuccessful(_ serverCert: Data!) {
        let cert = serverCert
        onMain { $0.pairingSucceeded(serverCert: cert) }
    }

    func pairFailed(_ message: String!) {
        let message = message ?? "Pairing failed."
        onMain { $0.pairingFailed(message) }
    }

    func alreadyPaired() {
        onMain { $0.pairingSucceeded(serverCert: nil) }
    }

    func receivedAsset(for app: TemporaryApp!) {
        let hostID = app?.host.map(HostSnapshot.identifier(for:))
        onMain { library in
            if let hostID { library.boxArtArrived(forHostID: hostID) }
        }
    }
}
