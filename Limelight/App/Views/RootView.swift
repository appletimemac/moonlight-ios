import SwiftUI

struct RootView: View {
    @Environment(HostLibrary.self) private var library
    @Environment(\.openURL) private var openURL
    @State private var compactColumn = NavigationSplitViewColumn.sidebar
    @State private var showsSettings = false
    @State private var showsAddHost = false

    var body: some View {
        @Bindable var library = library

        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            HostSidebar(showsAddHost: $showsAddHost, showsSettings: $showsSettings)
        } detail: {
            if let host = library.selectedHost {
                HostDetailView(host: host)
            } else {
                ContentUnavailableView("Select a PC", systemImage: "desktopcomputer", description: Text("Your gaming PCs appear here."))
            }
        }
        .onChange(of: library.selectedHostID) { _, id in
            compactColumn = id == nil ? .sidebar : .detail
        }
        .overlay(alignment: .bottom) {
            if let message = library.busyMessage {
                BusyIndicator(message: message)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: library.busyMessage)
        .sheet(item: $library.pairing) { session in
            PairingSheet(session: session)
        }
        .sheet(isPresented: $showsAddHost) {
            AddHostSheet()
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView()
        }
        .alert(library.alert?.title ?? "", isPresented: alertIsPresented, presenting: library.alert) { alert in
            if let helpURL = alert.helpURL {
                Button("Help") { openURL(helpURL) }
            }
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
        .confirmationDialog(
            library.conflict.map { "\($0.running.name) is running" } ?? "",
            isPresented: conflictIsPresented,
            titleVisibility: .visible,
            presenting: library.conflict
        ) { conflict in
            Button("Resume \(conflict.running.name)") { library.resumeRunningApp() }
            Button("Quit \(conflict.running.name) and Start \(conflict.requested.name)", role: .destructive) {
                library.quitRunningAppAndStartRequested()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var alertIsPresented: Binding<Bool> {
        Binding(get: { library.alert != nil }, set: { if !$0 { library.alert = nil } })
    }

    private var conflictIsPresented: Binding<Bool> {
        Binding(get: { library.conflict != nil }, set: { if !$0 { library.conflict = nil } })
    }
}

private struct BusyIndicator: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(message)
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}
