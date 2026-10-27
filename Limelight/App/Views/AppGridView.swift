import SwiftUI

struct AppGridView: View {
    let host: HostSnapshot
    let apps: [AppSnapshot]
    @Environment(HostLibrary.self) private var library

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 16)], spacing: 20) {
                ForEach(visibleApps) { app in
                    Button(app.name) { library.play(app) }
                }
            }
            .padding()
        }
    }

    private var visibleApps: [AppSnapshot] {
        library.showsHiddenApps ? apps : apps.filter { !$0.isHidden }
    }
}
