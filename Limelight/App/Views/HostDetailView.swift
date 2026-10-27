import SwiftUI

struct HostDetailView: View {
    let host: HostSnapshot
    @Environment(HostLibrary.self) private var library

    var body: some View {
        content
            .navigationTitle(host.name)
            .toolbar {
                if host.pairing == .paired && host.reachability == .online {
                    ToolbarItem {
                        Toggle("Show Hidden Apps", systemImage: "eye", isOn: showsHiddenApps)
                    }
                }
                ToolbarItem {
                    Menu("PC Options", systemImage: "ellipsis") {
                        if host.reachability != .online && host.canWake {
                            Button("Wake PC", systemImage: "power") { library.wake(hostID: host.id) }
                        }
                        if host.reachability == .online {
                            Button("Refresh", systemImage: "arrow.clockwise") { library.retry(hostID: host.id) }
                        }
                        Button("Test Network", systemImage: "network") { library.testNetwork() }
                    }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch (host.reachability, host.pairing) {
        case (.offline, _):
            ContentUnavailableView {
                Label("\(host.name) Is Offline", systemImage: "desktopcomputer.trianglebadge.exclamationmark")
            } description: {
                Text("Make sure the PC is awake and its streaming host (Apollo, Sunshine or GeForce Experience) is running.")
            } actions: {
                if host.canWake {
                    Button("Wake PC") { library.wake(hostID: host.id) }
                        .buttonStyle(.glassProminent)
                }
                Button("Test Network") { library.testNetwork() }
                    .buttonStyle(.glass)
            }
        case (.online, .unpaired):
            ContentUnavailableView {
                Label("Pair with \(host.name)", systemImage: "lock.desktopcomputer")
            } description: {
                Text("Moonlight shows a PIN to enter on your PC. In Apollo or Sunshine, enter it on the web UI's PIN page.")
            } actions: {
                Button("Pair") { library.retry(hostID: host.id) }
                    .buttonStyle(.glassProminent)
            }
        case (.online, .paired):
            let apps = library.apps(for: host.id)
            if apps.isEmpty && !library.loadedAppLists.contains(host.id) {
                ProgressView("Loading apps")
            } else {
                AppGridView(host: host, apps: apps)
            }
        default:
            ProgressView("Connecting to \(host.name)")
        }
    }

    private var showsHiddenApps: Binding<Bool> {
        Binding(get: { library.showsHiddenApps }, set: { library.showsHiddenApps = $0 })
    }
}
