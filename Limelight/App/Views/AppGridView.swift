import SwiftUI
import UIKit

struct AppGridView: View {
    let host: HostSnapshot
    let apps: [AppSnapshot]
    @Environment(HostLibrary.self) private var library
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ScaledMetric private var compactMinTile: CGFloat = 104
    @ScaledMetric private var regularMinTile: CGFloat = 144
    @State private var containerWidth: CGFloat = 0

    private let spacing: CGFloat = 16

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let access = host.apolloAccess, !access.missing.isEmpty {
                    AccessBanner(access: access)
                }
                if let running = library.runningApp(on: host) {
                    NowPlayingCard(app: running)
                }
                if visibleApps.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
            .animation(.smooth, value: visibleApps.map(\.id))
            .animation(.smooth, value: host.runningAppID)
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .contentMargins(.vertical, 8, for: .scrollContent)
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(visibleApps) { app in
                AppTile(app: app, isRunning: app.appID == host.runningAppID)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let hasHiddenApps = apps.contains { $0.isHidden }
        ContentUnavailableView {
            Label("No Apps", systemImage: "gamecontroller")
        } description: {
            Text(hasHiddenApps ? "Every app on this PC is hidden." : "This PC isn't sharing any apps.")
        } actions: {
            if hasHiddenApps {
                Button("Show Hidden Apps", systemImage: "eye") { library.showsHiddenApps = true }
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(.vertical, 24)
    }

    private var visibleApps: [AppSnapshot] {
        library.showsHiddenApps ? apps : apps.filter { !$0.isHidden }
    }

    private var minTile: CGFloat {
        horizontalSizeClass == .regular ? regularMinTile : compactMinTile
    }

    // An even count divides cleanly at the iPhone Duo fold
    private var columnCount: Int {
        var count = max(2, Int(((containerWidth + spacing) / (minTile + spacing)).rounded(.down)))
        if count > 2 && !count.isMultiple(of: 2) {
            count -= 1
        }
        return count
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnCount)
    }
}

private struct AppTile: View {
    let app: AppSnapshot
    let isRunning: Bool
    @Environment(HostLibrary.self) private var library
    @State private var confirmsQuit = false

    private let cornerRadius: CGFloat = 14

    var body: some View {
        Button {
            library.play(app)
        } label: {
            VStack(spacing: 8) {
                BoxArt(path: app.boxArtPath, title: app.name, cornerRadius: cornerRadius)
                    .opacity(app.isHidden ? 0.45 : 1)
                    .overlay(alignment: .bottomLeading) {
                        if isRunning {
                            RunningBadge()
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if app.isHidden {
                            HiddenBadge()
                        }
                    }
                Text(app.name)
                    .font(.footnote)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .opacity(app.isHidden ? 0.45 : 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(TilePressStyle())
        .contentShape(.contextMenuPreview, .rect(cornerRadius: cornerRadius))
        .contextMenu {
            Button(isRunning ? "Resume" : "Play", systemImage: "play.fill") { library.play(app) }
            if isRunning {
                Button("Quit", systemImage: "xmark.circle", role: .destructive) { confirmsQuit = true }
            }
            Button(app.isHidden ? "Show App" : "Hide App", systemImage: app.isHidden ? "eye" : "eye.slash") {
                library.setHidden(!app.isHidden, for: app)
            }
        }
        .quitConfirmation($confirmsQuit, for: app)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var states: [String] = []
        if isRunning {
            states.append("running")
        }
        if app.isHidden {
            states.append("hidden")
        }
        return ([app.name] + states).joined(separator: ", ")
    }
}

private struct TilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

private struct RunningBadge: View {
    var body: some View {
        Label("Running", systemImage: "play.fill")
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassEffect(.regular, in: .capsule)
            .padding(6)
    }
}

private struct HiddenBadge: View {
    var body: some View {
        Image(systemName: "eye.slash")
            .font(.caption.weight(.semibold))
            .padding(6)
            .background(.regularMaterial, in: .circle)
            .padding(6)
    }
}

private struct NowPlayingCard: View {
    let app: AppSnapshot
    @Environment(HostLibrary.self) private var library
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric private var thumbnailWidth: CGFloat = 56
    @State private var confirmsQuit = false

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.fill.quaternary, in: .rect(cornerRadius: 24))
            .quitConfirmation($confirmsQuit, for: app)
            .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var content: some View {
        if dynamicTypeSize.isAccessibilitySize {
            stacked
        } else {
            ViewThatFits(in: .horizontal) {
                inline
                stacked
            }
        }
    }

    private var inline: some View {
        HStack(spacing: 16) {
            summary
            Spacer(minLength: 0)
            actions(fillsWidth: false)
        }
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 16) {
            summary
            actions(fillsWidth: true)
        }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            BoxArt(path: app.boxArtPath, title: app.name, cornerRadius: 8)
                .frame(width: thumbnailWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Now Playing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(app.name)
                    .font(.headline)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func actions(fillsWidth: Bool) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Button("Resume", systemImage: "play.fill") { library.play(app) }
                .buttonStyle(.glassProminent)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .accessibilityLabel("Resume \(app.name)")
            Button("Quit", systemImage: "xmark") { confirmsQuit = true }
                .buttonStyle(.glass)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .accessibilityLabel("Quit \(app.name)")
        }
        .controlSize(fillsWidth ? .large : .regular)
    }
}

private struct AccessBanner: View {
    let access: ApolloAccess

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Limited Access")
                    .font(.headline)
                Group {
                    Text(summary)
                    if access.hasNoInput {
                        Text("Touch, mouse, keyboard and controller input is being ignored.")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.fill.quaternary, in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        let titles = access.missing.map(\.title).joined(separator: ", ")
        return "This PC hasn't given this device: \(titles). Turn them on for this device in Apollo's web UI, under Clients."
    }
}

private struct QuitConfirmation: ViewModifier {
    @Binding var isPresented: Bool
    let app: AppSnapshot
    @Environment(HostLibrary.self) private var library

    func body(content: Content) -> some View {
        content.confirmationDialog("Quit \(app.name)?", isPresented: $isPresented, titleVisibility: .visible) {
            Button("Quit \(app.name)", role: .destructive) {
                library.quitRunningApp(onHostID: app.hostID)
            }
        } message: {
            Text("The app closes on your PC and any unsaved progress is lost.")
        }
    }
}

private extension View {
    func quitConfirmation(_ isPresented: Binding<Bool>, for app: AppSnapshot) -> some View {
        modifier(QuitConfirmation(isPresented: isPresented, app: app))
    }
}

private struct LoadedArt {
    let path: String
    let image: UIImage
}

private struct BoxArt: View {
    let path: String?
    let title: String
    let cornerRadius: CGFloat
    @State private var loaded: LoadedArt?

    // Box art is 628 by 888 points
    private static let aspectRatio: CGFloat = 628.0 / 888.0

    var body: some View {
        Color.clear
            .aspectRatio(Self.aspectRatio, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    BoxArtPlaceholder(title: title)
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
            .task(id: path) {
                guard let path else {
                    loaded = nil
                    return
                }
                if let image = await BoxArtLoader.load(path: path) {
                    loaded = LoadedArt(path: path, image: image)
                }
            }
    }

    // Reading the cache here avoids a placeholder flash for art that was already decoded
    private var image: UIImage? {
        guard let path else { return nil }
        return BoxArtCache.shared.image(for: path) ?? (loaded?.path == path ? loaded?.image : nil)
    }
}

private struct BoxArtPlaceholder: View {
    let title: String

    var body: some View {
        LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.45, brightness: 0.78),
                Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.55, brightness: 0.5),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing)
            .overlay {
                Image(systemName: "gamecontroller.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.white.opacity(0.85))
                    .accessibilityHidden(true)
            }
    }

    // Stable per title, unlike hashValue, so a tile keeps its color across launches
    private var hue: Double {
        Double(title.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 360 }) / 360
    }
}

private final class BoxArtCache: @unchecked Sendable {
    static let shared = BoxArtCache()

    private let storage: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    func image(for path: String) -> UIImage? {
        storage.object(forKey: path as NSString)
    }

    func insert(_ image: UIImage, for path: String) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        storage.setObject(image, forKey: path as NSString, cost: cost)
    }
}

private enum BoxArtLoader {
    @concurrent
    static func load(path: String) async -> UIImage? {
        if let cached = BoxArtCache.shared.image(for: path) {
            return cached
        }
        guard let image = UIImage(contentsOfFile: path) else { return nil }
        let prepared = await image.byPreparingForDisplay() ?? image
        BoxArtCache.shared.insert(prepared, for: path)
        return prepared
    }
}
