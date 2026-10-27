import Observation
import UIKit

// The SwiftUI front end's model: the PCs Moonlight knows, their apps, and the
// flows that used to live in MainFrameViewController (connect, pair, launch, quit).
// Views read value snapshots; the Objective-C objects never leave this class.
@MainActor @Observable
final class HostLibrary {
    private(set) var hosts: [HostSnapshot] = []
    private(set) var appsByHost: [String: [AppSnapshot]] = [:]
    private(set) var selectedHostID: String?
    private(set) var busyMessage: String?
    var showsHiddenApps = false
    var pairing: PairingSession?
    var alert: LibraryAlert?
    var conflict: AppConflict?

    @ObservationIgnored let presenter: StreamPresenter
    @ObservationIgnored private let callbacks = CoreCallbacks()
    @ObservationIgnored private let discovery: DiscoveryManager
    @ObservationIgnored private let assets: AppAssetManager
    @ObservationIgnored private let clientCert: Data
    @ObservationIgnored private let operations = OperationQueue()
    @ObservationIgnored private var coreHosts: [String: TemporaryHost] = [:]
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var isForeground = false
    @ObservationIgnored private var shortcutHostIDs: [String] = []

    var selectedHost: HostSnapshot? {
        hosts.first { $0.id == selectedHostID }
    }

    func apps(for hostID: String) -> [AppSnapshot] {
        appsByHost[hostID] ?? []
    }

    func runningApp(on host: HostSnapshot) -> AppSnapshot? {
        guard let runningID = host.runningAppID else { return nil }
        return apps(for: host.id).first { $0.appID == runningID }
    }

    init(presenter: StreamPresenter) {
        self.presenter = presenter
        CryptoManager.generateKeyPairUsingSSL()
        clientCert = CryptoManager.readCertFromFile() ?? Data()
        assets = AppAssetManager(callback: callbacks)

        let saved = (DataManager().getHosts() ?? []).compactMap { $0 as? TemporaryHost }
        for host in saved where host.activeAddress == nil {
            host.activeAddress = host.localAddress ?? host.externalAddress ?? host.address ?? host.ipv6Address
        }
        discovery = DiscoveryManager(hosts: saved, andCallback: callbacks)
        callbacks.library = self
        adopt(saved)

        // A single known PC opens straight to its apps, as before
        if hosts.count == 1 {
            select(hosts[0].id, userInitiated: false)
        }
    }

    func enterForeground() {
        guard !isForeground else { return }
        isForeground = true
        if !presenter.isStreaming {
            resumeBrowsing()
        }
    }

    func enterBackground() {
        isForeground = false
        discovery.stopDiscovery()
        refreshTask?.cancel()
    }

    private func resumeBrowsing() {
        rebuildHosts()
        // Reset first so PCs removed earlier can be found again
        discovery.resetDiscoveryState()
        discovery.startDiscovery()
        startRefreshLoop()
        if let id = selectedHostID, let host = coreHosts[id], host.pairState == .paired {
            connect(host, userInitiated: false)
        }
    }

    // Discovery workers change host state without telling anyone, so poll the snapshots
    private func startRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                self?.rebuildHosts()
            }
        }
    }

    func select(_ id: String?, userInitiated: Bool = true) {
        guard id != selectedHostID else { return }
        selectedHostID = id
        showsHiddenApps = false
        assets.stopRetrieving()
        guard let id, let host = coreHosts[id] else { return }

        if host.state == .online && host.pairState == .paired && host.appList.count > 0 {
            refreshApps(host, userInitiated: userInitiated)
        } else if host.state != .offline {
            connect(host, userInitiated: userInitiated)
        }
    }

    func retry(hostID: String) {
        guard let host = coreHosts[hostID] else { return }
        connect(host, userInitiated: true)
    }

    private func connect(_ host: TemporaryHost, userInitiated: Bool) {
        let hostID = HostSnapshot.identifier(for: host)
        if userInitiated {
            busyMessage = "Connecting to \(host.name)"
        }
        let core = Unchecked(host)
        let discovery = Unchecked(discovery)
        Task {
            let info = await Background.run { () -> Unchecked<ServerInfoResponse>? in
                // Give the first poll a moment to learn whether the PC is up
                var waited = 0
                while core.value.state == .unknown && waited < 15 {
                    sleep(1)
                    waited += 1
                }
                guard core.value.state != .offline else { return nil }

                let http: HttpManager = HttpManager(host: core.value)
                let response = ServerInfoResponse()
                discovery.value.pauseDiscovery(for: core.value)
                http.executeRequestSynchronously(HttpRequest(
                    for: response,
                    with: http.newServerInfoRequest(false),
                    fallbackError: 401,
                    fallbackRequest: http.newHttpServerInfoRequest()))
                discovery.value.resumeDiscovery(for: core.value)
                return Unchecked(response)
            }
            if userInitiated {
                busyMessage = nil
            }
            guard selectedHostID == hostID else { return }
            guard let response = info?.value else {
                rebuildHosts()
                return
            }
            guard response.isStatusOk() else {
                host.state = .offline
                rebuildHosts()
                if userInitiated {
                    alert = LibraryAlert(title: "Connection Failed", message: response.statusMessage ?? "", helpURL: LibraryAlert.troubleshootingURL)
                }
                return
            }
            response.populateHost(host)
            rebuildHosts()
            if host.pairState == .paired {
                refreshApps(host, userInitiated: userInitiated)
            } else if userInitiated {
                beginPairing(host)
            }
        }
    }

    private func beginPairing(_ host: TemporaryHost) {
        let hostID = HostSnapshot.identifier(for: host)
        // Ask for a device name once, so hosts like Apollo can tell this device apart
        if AppPreferences.pairingDeviceName == nil {
            pairing = PairingSession(hostID: hostID, hostName: host.name, phase: .naming)
        } else {
            pairing = PairingSession(hostID: hostID, hostName: host.name, phase: .requesting)
            startPairManager(host)
        }
    }

    func confirmPairing(deviceName: String) {
        let name = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            UserDefaults.standard.set(name, forKey: AppPreferences.pairingDeviceNameKey)
        }
        guard var session = pairing, let host = coreHosts[session.hostID] else { return }
        session.phase = .requesting
        pairing = session
        startPairManager(host)
    }

    func cancelPairing() {
        pairing = nil
        discovery.startDiscovery()
    }

    private func startPairManager(_ host: TemporaryHost) {
        let discovery = Unchecked(discovery)
        Task {
            // Polling the PC while it pairs makes it fail
            await Background.run { discovery.value.stopDiscoveryBlocking() }
            guard pairing != nil else { return }
            let manager = PairManager(manager: HttpManager(host: host), clientCert: clientCert, callback: callbacks)
            operations.addOperation(manager!)
        }
    }

    func pairingShowsPIN(_ pin: String) {
        guard var session = pairing else { return }
        session.phase = .showingPIN(pin)
        pairing = session
    }

    func pairingSucceeded(serverCert: Data?) {
        guard let session = pairing else { return }
        pairing = nil
        discovery.startDiscovery()
        guard let host = coreHosts[session.hostID] else { return }
        if let serverCert {
            host.serverCert = serverCert
        }
        refreshApps(host, userInitiated: true)
    }

    func pairingFailed(_ message: String) {
        // A cancelled session can still fail later; the user already moved on
        guard pairing != nil else { return }
        pairing = nil
        discovery.startDiscovery()
        alert = LibraryAlert(title: "Pairing Failed", message: message, helpURL: LibraryAlert.troubleshootingURL)
    }

    private func refreshApps(_ host: TemporaryHost, userInitiated: Bool) {
        let hostID = HostSnapshot.identifier(for: host)
        rebuildApps(hostID: hostID)
        let core = Unchecked(host)
        let discovery = Unchecked(discovery)
        Task {
            let response = await Background.run { () -> Unchecked<AppListResponse?> in
                discovery.value.pauseDiscovery(for: core.value)
                let response = ConnectionHelper.getAppList(for: core.value)
                discovery.value.resumeDiscovery(for: core.value)
                return Unchecked(response)
            }.value

            let fresh = (response?.getAppList() ?? []).compactMap { $0 as? TemporaryApp }
            guard let response, response.isStatusOk(), response.getAppList() != nil else {
                host.state = .offline
                rebuildHosts()
                if selectedHostID == hostID {
                    alert = LibraryAlert(title: "Connection Interrupted", message: response?.statusMessage ?? "", helpURL: LibraryAlert.troubleshootingURL)
                }
                return
            }
            mergeApps(fresh, into: host)
            if selectedHostID == hostID {
                assets.stopRetrieving()
                assets.retrieveAssets(from: host)
            }
        }
    }

    // Port of MainFrameViewController's updateApplist:forHost:. Hidden is kept from
    // the local copy; apps the host no longer lists are deleted.
    private func mergeApps(_ fresh: [TemporaryApp], into host: TemporaryHost) {
        let database = DataManager()
        var merged = host.appList.compactMap { $0 as? TemporaryApp }
        for app in fresh {
            if let saved = merged.first(where: { $0.id == app.id }) {
                saved.name = app.name
                saved.hdrSupported = app.hdrSupported
            } else {
                app.host = host
                merged.append(app)
            }
        }
        let freshIDs = Set(fresh.compactMap(\.id))
        for app in merged where !freshIDs.contains(app.id ?? "") {
            // Leaving it would violate the store's app list constraint
            database.remove(app)
        }
        merged.removeAll { !freshIDs.contains($0.id ?? "") }
        host.appList = Set(merged.map { $0 as AnyHashable })
        database.updateApps(forExisting: host)

        rebuildApps(hostID: HostSnapshot.identifier(for: host))
        updateShortcuts()
    }

    func setHidden(_ hidden: Bool, for app: AppSnapshot) {
        guard let host = coreHosts[app.hostID], let core = coreApp(app) else { return }
        core.hidden = hidden
        DataManager().updateApps(forExisting: host)
        rebuildApps(hostID: app.hostID)
    }

    func boxArtArrived(forHostID hostID: String) {
        rebuildApps(hostID: hostID)
    }

    func play(_ app: AppSnapshot) {
        guard let host = hosts.first(where: { $0.id == app.hostID }) else { return }
        if let running = runningApp(on: host), running.appID != app.appID {
            conflict = AppConflict(requested: app, running: running)
            return
        }
        startStream(app)
    }

    func resumeRunningApp() {
        guard let conflict else { return }
        self.conflict = nil
        startStream(conflict.running)
    }

    func quitRunningAppAndStartRequested() {
        guard let conflict else { return }
        self.conflict = nil
        quitRunningApp(onHostID: conflict.requested.hostID, thenStart: conflict.requested)
    }

    private func startStream(_ app: AppSnapshot) {
        guard let host = coreHosts[app.hostID], let core = coreApp(app) else { return }
        let configuration = StreamConfigurationFactory.make(app: core, host: host, window: presenter.window)
        assets.stopRetrieving()
        discovery.stopDiscovery()
        refreshTask?.cancel()
        presenter.present(configuration) { [weak self] action in
            guard let self else { return }
            if self.isForeground {
                self.resumeBrowsing()
            }
            switch action {
            case .quitApp:
                self.quitRunningApp(onHostID: app.hostID)
            case .restartToFit:
                self.quitRunningApp(onHostID: app.hostID, thenStart: app)
            default:
                break
            }
        }
    }

    #if DEBUG
    // Shows the stream screen against the first PC so its layout can be checked without
    // a paired host; the connection fails and reports it, which is expected here.
    func debugPresentStream() {
        guard let host = coreHosts.values.first else { return }
        let app = TemporaryApp()
        app.id = "0"
        app.name = "Layout Check"
        app.host = host
        presenter.present(StreamConfigurationFactory.make(app: app, host: host, window: presenter.window)) { _ in }
    }
    #endif

    func quitRunningApp(onHostID hostID: String, thenStart next: AppSnapshot? = nil) {
        guard let host = coreHosts[hostID] else { return }
        busyMessage = "Quitting app"
        let core = Unchecked(host)
        let discovery = Unchecked(discovery)
        Task {
            let status = await Background.run { () -> Int in
                let http: HttpManager = HttpManager(host: core.value)
                discovery.value.pauseDiscovery(for: core.value)
                defer { discovery.value.resumeDiscovery(for: core.value) }

                let quit = HttpResponse()
                http.executeRequestSynchronously(HttpRequest(for: quit, with: http.newQuitAppRequest()))
                guard quit.statusCode == 200 else { return quit.statusCode }

                // Newer hosts report success even when another client's app keeps running
                let info = ServerInfoResponse()
                http.executeRequestSynchronously(HttpRequest(
                    for: info,
                    with: http.newServerInfoRequest(false),
                    fallbackError: 401,
                    fallbackRequest: http.newHttpServerInfoRequest()))
                if !info.isStatusOk() || (info.getStringTag("state") ?? "").hasSuffix("_SERVER_BUSY") {
                    return 599
                }
                info.populateHost(core.value)
                return 200
            }
            busyMessage = nil
            guard status == 200 else {
                rebuildHosts()
                if status == 403 {
                    alert = Self.permissionAlert(action: "quit apps")
                } else {
                    alert = LibraryAlert(title: "Quitting App Failed", message: "Failed to quit app. If this app was started by another device, you'll need to quit from that device.")
                }
                return
            }
            host.currentGame = "0"
            rebuildHosts()
            if let next {
                startStream(next)
            }
        }
    }

    static func permissionAlert(action: String) -> LibraryAlert {
        LibraryAlert(
            title: "Permission Denied",
            message: "Your PC hasn't given this device permission to \(action). In Apollo's web UI, open Clients, select this device and turn on Launch Apps.")
    }

    func addHost(address: String) async -> String? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Enter your PC's IP address or host name." }
        let discovery = Unchecked(discovery)
        let (found, error) = await withCheckedContinuation { (continuation: CheckedContinuation<(Unchecked<TemporaryHost?>, String?), Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                discovery.value.discoverHost(trimmed) { host, error in
                    continuation.resume(returning: (Unchecked(host), error))
                }
            }
        }
        guard let host = found.value else {
            return error ?? "Could not connect to host."
        }
        adopt(Array(coreHosts.values) + [host])
        return nil
    }

    func remove(hostID: String) {
        guard let host = coreHosts[hostID] else { return }
        discovery.removeHost(fromDiscovery: host)
        DataManager().remove(host)
        coreHosts[hostID] = nil
        appsByHost[hostID] = nil
        if selectedHostID == hostID {
            selectedHostID = nil
        }
        rebuildHosts()
        updateShortcuts()
    }

    func showAllApps(hostID: String) {
        select(hostID)
        showsHiddenApps = true
    }

    func wake(hostID: String) {
        guard let host = coreHosts[hostID] else { return }
        guard HostSnapshot(host).canWake else {
            alert = LibraryAlert(title: "Wake-on-LAN", message: "This PC's MAC address is unknown, so Moonlight can't send a wake-up request.")
            return
        }
        let core = Unchecked(host)
        Task { await Background.run { WakeOnLanManager.wake(core.value) } }
        alert = LibraryAlert(title: "Wake-on-LAN", message: "Sent a wake-up request. It may take a few moments for the PC to wake. If it never wakes up, make sure it's set up for Wake-on-LAN.")
    }

    func testNetwork() {
        busyMessage = "Testing your network"
        Task {
            let result = await Background.run { CoreUtilities.testAllPorts() }
            busyMessage = nil
            let message: String
            if result == 0 {
                message = "This network does not appear to be blocking Moonlight. If you still have trouble connecting, check your PC's firewall settings.\n\nVisit the Moonlight Setup Guide on GitHub for additional setup help and troubleshooting steps."
            } else if CoreUtilities.isInconclusiveTestResult(result) {
                message = "The network test could not be performed because none of Moonlight's connection testing servers were reachable. Check your Internet connection or try again later."
            } else {
                message = "Your current network connection seems to be blocking Moonlight. Streaming may not work while connected to this network.\n\nThe following network ports were blocked:\n\(CoreUtilities.describePortFlags(result))"
            }
            alert = LibraryAlert(title: "Network Test Complete", message: message)
        }
    }

    @discardableResult
    func handleShortcut(_ item: UIApplicationShortcutItem) -> Bool {
        guard let uuid = item.userInfo?["UUID"] as? String, coreHosts[uuid] != nil else { return false }
        select(uuid, userInitiated: false)
        return true
    }

    private func updateShortcuts() {
        // Paired PCs keep their app list even before the first poll says so
        let eligible = hosts.filter(\.hasCachedApps)
        let ids = eligible.map(\.id)
        guard ids != shortcutHostIDs else { return }
        shortcutHostIDs = ids
        UIApplication.shared.shortcutItems = eligible.map { host in
            UIApplicationShortcutItem(
                type: "PC",
                localizedTitle: host.name,
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(type: .play),
                userInfo: ["UUID": host.id as NSString])
        }
    }

    func discoveryFound(_ found: [TemporaryHost]) {
        adopt(found)
    }

    private func adopt(_ found: [TemporaryHost]) {
        coreHosts = Dictionary(found.map { (HostSnapshot.identifier(for: $0), $0) }, uniquingKeysWith: { _, latest in latest })
        rebuildHosts()
        for id in coreHosts.keys {
            rebuildApps(hostID: id)
        }
        updateShortcuts()
    }

    private func rebuildHosts() {
        let snapshots = coreHosts.values
            .map(HostSnapshot.init)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if snapshots != hosts {
            hosts = snapshots
        }
    }

    private func rebuildApps(hostID: String) {
        guard let host = coreHosts[hostID] else { return }
        let snapshots = host.appList
            .compactMap { $0 as? TemporaryApp }
            .compactMap { app -> AppSnapshot? in
                guard let appID = app.id else { return nil }
                let path = AppAssetManager.boxArtPath(for: app)
                return AppSnapshot(
                    hostID: hostID,
                    appID: appID,
                    name: app.name ?? appID,
                    isHidden: app.hidden,
                    supportsHDR: app.hdrSupported,
                    boxArtPath: path.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil })
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if snapshots != appsByHost[hostID] {
            appsByHost[hostID] = snapshots
        }
    }

    private func coreApp(_ app: AppSnapshot) -> TemporaryApp? {
        coreHosts[app.hostID]?.appList
            .compactMap { $0 as? TemporaryApp }
            .first { $0.id == app.appID }
    }
}
