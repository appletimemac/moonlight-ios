import SwiftUI

struct PairingSheet: View {
    let session: PairingSession
    @Environment(HostLibrary.self) private var library

    var body: some View {
        NavigationStack {
            Text(session.hostName)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { library.cancelPairing() }
                    }
                }
        }
    }
}
