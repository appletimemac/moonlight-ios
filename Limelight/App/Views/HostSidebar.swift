import SwiftUI

struct HostSidebar: View {
    @Environment(HostLibrary.self) private var library
    @Binding var showsAddHost: Bool
    @Binding var showsSettings: Bool
    @State private var hostPendingRemoval: HostSnapshot?

    var body: some View {
        List(selection: selection) {
            ForEach(library.hosts) { host in
                HostRow(host: host)
                    .tag(host.id)
                    .contextMenu { actions(for: host) }
            }
        }
        .overlay {
            if library.hosts.isEmpty {
                ContentUnavailableView {
                    Label("Looking for PCs", systemImage: "antenna.radiowaves.left.and.right")
                } description: {
                    Text("Moonlight finds PCs running Apollo, Sunshine or GeForce Experience on your network.")
                } actions: {
                    Button("Add PC Manually") { showsAddHost = true }
                        .buttonStyle(.glassProminent)
                }
            }
        }
        .navigationTitle("PCs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add PC", systemImage: "plus") { showsAddHost = true }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Settings", systemImage: "gearshape") { showsSettings = true }
            }
        }
        .confirmationDialog(
            hostPendingRemoval.map { "Remove \($0.name)?" } ?? "",
            isPresented: removalIsPresented,
            titleVisibility: .visible,
            presenting: hostPendingRemoval
        ) { host in
            Button("Remove PC", role: .destructive) { library.remove(hostID: host.id) }
        } message: { _ in
            Text("You'll need to pair again to stream from it. The PC keeps this device in its client list until you remove it there.")
        }
    }

    private var selection: Binding<String?> {
        Binding(get: { library.selectedHostID }, set: { library.select($0) })
    }

    private var removalIsPresented: Binding<Bool> {
        Binding(get: { hostPendingRemoval != nil }, set: { if !$0 { hostPendingRemoval = nil } })
    }

    @ViewBuilder
    private func actions(for host: HostSnapshot) -> some View {
        if host.reachability != .online && host.canWake {
            Button("Wake PC", systemImage: "power") { library.wake(hostID: host.id) }
        }
        if host.pairing == .paired {
            Button("Show All Apps", systemImage: "eye") { library.showAllApps(hostID: host.id) }
        }
        Button("Test Network", systemImage: "network") { library.testNetwork() }
        Divider()
        Button("Remove PC", systemImage: "trash", role: .destructive) { hostPendingRemoval = host }
    }
}

struct HostRow: View {
    let host: HostSnapshot
    @Environment(HostLibrary.self) private var library

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(host.name)
                    .font(.body.weight(.medium))
                Text(status)
                    .font(.caption)
                    .foregroundStyle(host.apolloAccess?.missing.isEmpty == false ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            }
        } icon: {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(host.reachability == .online ? Color.accentColor : .secondary)
        }
        .padding(.vertical, 4)
    }

    private var symbol: String {
        switch (host.reachability, host.pairing) {
        case (.offline, _): "desktopcomputer.trianglebadge.exclamationmark"
        case (.online, .unpaired): "lock.desktopcomputer"
        case (.online, _) where host.runningAppID != nil: "play.desktopcomputer"
        default: "desktopcomputer"
        }
    }

    private var status: String {
        switch host.reachability {
        case .unknown:
            return "Connecting"
        case .offline:
            return "Offline"
        case .online:
            if host.pairing == .unpaired {
                return "Not paired"
            }
            if let missing = host.apolloAccess?.missing, !missing.isEmpty {
                return "Limited access"
            }
            if let running = library.runningApp(on: host) {
                return "Playing \(running.name)"
            }
            return host.runningAppID == nil ? "Online" : "Streaming"
        }
    }
}
