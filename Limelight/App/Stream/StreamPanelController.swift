import SwiftUI
import UIKit

// Implemented by StreamFrameViewController, which owns the stream itself
@objc protocol StreamControlsDelegate: AnyObject {
    func streamControlsStatsText() -> String?
    func streamControlsToggleKeyboard()
    func streamControlsDisconnect()
    func streamControlsQuitApp()
    func streamControlsRestartToFit()
}

// The stream screen's controls: the iPhone Duo panel under the video when the
// stream is split, or a floating glass card opened from the left edge otherwise.
@objc(StreamPanelController)
final class StreamPanelController: UIViewController {
    @objc(StreamPanelStyle)
    enum Style: Int {
        case panel, overlay
    }

    private let style: Style
    private let model: StreamControlsModel
    private let gamepadView: UIView?
    private let trackpadView: UIView?

    @objc init(style: Style, configuration: StreamConfiguration, gamepadView: UIView?, trackpadView: UIView?, delegate: StreamControlsDelegate) {
        self.style = style
        self.model = StreamControlsModel(configuration: configuration, delegate: delegate)
        self.gamepadView = gamepadView
        self.trackpadView = trackpadView
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        model.window = { [weak self] in self?.view.window }

        let content: AnyView
        switch style {
        case .panel:
            content = AnyView(StreamPanelView(model: model, gamepadView: gamepadView, trackpadView: trackpadView))
        case .overlay:
            content = AnyView(StreamOverlayCard(model: model))
        }
        let host = UIHostingController(rootView: content.environment(\.colorScheme, .dark))
        host.view.backgroundColor = .clear
        host.sizingOptions = style == .overlay ? .intrinsicContentSize : []
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    // Recheck what Restart to Fit would do after the stream screen changes size
    @objc func refresh() {
        model.refreshRestartSize()
    }
}

@MainActor @Observable
private final class StreamControlsModel {
    let configuration: StreamConfiguration
    @ObservationIgnored weak var delegate: StreamControlsDelegate?
    @ObservationIgnored var window: () -> UIWindow? = { nil }

    var statsText: String?
    var restartSize: PixelSize?
    var clipboardStatus: String?

    init(configuration: StreamConfiguration, delegate: StreamControlsDelegate) {
        self.configuration = configuration
        self.delegate = delegate
    }

    var appName: String {
        configuration.appName ?? "the app"
    }

    var supportsClipboard: Bool {
        configuration.supportsClipboard
    }

    func refreshStats() {
        statsText = delegate?.streamControlsStatsText()
    }

    func refreshRestartSize() {
        guard AppPreferences.resolutionMode == .matchDisplay, let window = window() else {
            restartSize = nil
            return
        }
        let size = StreamResolution.matchingDisplay(
            points: window.bounds.size,
            scale: window.traitCollection.displayScale,
            landscapeOnly: window.traitCollection.userInterfaceIdiom == .phone,
            maxDimension: 8192)
        let current = PixelSize(width: Int(configuration.width), height: Int(configuration.height))
        restartSize = size == current ? nil : size
    }

    func toggleKeyboard() { delegate?.streamControlsToggleKeyboard() }
    func disconnect() { delegate?.streamControlsDisconnect() }
    func quitApp() { delegate?.streamControlsQuitApp() }
    func restartToFit() { delegate?.streamControlsRestartToFit() }

    func sendClipboard(_ text: String?) {
        guard let text, !text.isEmpty else {
            clipboardStatus = "There's no text on the clipboard."
            return
        }
        let http = Unchecked(httpManager())
        Task {
            let status = await Background.run { () -> Int in
                var status = 0
                _ = http.value.executeRawRequestSynchronously(http.value.newClipboardUpdateRequest(text), statusCode: &status)
                return status
            }
            clipboardStatus = Self.message(for: status, success: "Sent your clipboard to the PC.")
        }
    }

    func fetchClipboard() {
        let http = Unchecked(httpManager())
        Task {
            let (status, text) = await Background.run { () -> (Int, String?) in
                var status = 0
                let body = http.value.executeRawRequestSynchronously(http.value.newClipboardRequest(), statusCode: &status)
                return (status, body.flatMap { String(data: $0, encoding: .utf8) })
            }
            guard status == 200 else {
                clipboardStatus = Self.message(for: status, success: "")
                return
            }
            guard let text, !text.isEmpty else {
                clipboardStatus = "The PC's clipboard has no text."
                return
            }
            UIPasteboard.general.string = text
            clipboardStatus = "Copied the PC's clipboard to this device."
        }
    }

    private func httpManager() -> HttpManager {
        HttpManager(address: configuration.host, httpsPort: configuration.httpsPort, serverCert: configuration.serverCert)
    }

    private static func message(for status: Int, success: String) -> String {
        switch status {
        case 200: success
        case 401: "Apollo hasn't given this device clipboard permission. Turn on clipboard access for it in Apollo's web UI, under Clients."
        case 403: "The PC only shares its clipboard with a device that is streaming from it."
        case 404: "This PC's streaming host doesn't support clipboard sync."
        default: "Clipboard sync failed (error \(status))."
        }
    }
}

private struct StreamPanelView: View {
    let model: StreamControlsModel
    let gamepadView: UIView?
    let trackpadView: UIView?
    @AppStorage(AppPreferences.tabletopPanelKey) private var panelName = TabletopPanel.trackpad.rawValue

    var body: some View {
        VStack(spacing: 12) {
            Picker("Panel", selection: panel) {
                Label("Trackpad", systemImage: "hand.point.up.left").tag(TabletopPanel.trackpad)
                Label("Gamepad", systemImage: "gamecontroller").tag(TabletopPanel.gamepad)
                Label("Controls", systemImage: "slider.horizontal.3").tag(TabletopPanel.controls)
            }
            .pickerStyle(.segmented)

            switch panel.wrappedValue {
            case .trackpad:
                TrackpadPanel(model: model, trackpadView: trackpadView)
            case .gamepad:
                if let gamepadView {
                    HostedView(view: gamepadView)
                }
            case .controls:
                StreamControlsView(model: model)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }

    private var panel: Binding<TabletopPanel> {
        Binding(get: { TabletopPanel(rawValue: panelName) ?? .trackpad }, set: { panelName = $0.rawValue })
    }
}

private struct TrackpadPanel: View {
    let model: StreamControlsModel
    let trackpadView: UIView?

    var body: some View {
        VStack(spacing: 12) {
            if let trackpadView {
                HostedView(view: trackpadView)
                    .background(.white.opacity(0.08), in: .rect(cornerRadius: 20))
                    .overlay {
                        Text("Trackpad")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .allowsHitTesting(false)
                    }
                    .accessibilityLabel("Trackpad")
                    .accessibilityHint("Drag to move the pointer. Tap to click, tap with two fingers to right click.")
            }
            ScrollView(.horizontal) {
                GlassEffectContainer {
                    HStack(spacing: 8) {
                        Button("Keyboard", systemImage: "keyboard") { model.toggleKeyboard() }
                        ForEach(HostKey.allCases) { key in
                            Button(key.title, systemImage: key.symbol) { HostKeyboard.press(key) }
                        }
                        Button("Alt+Tab", systemImage: "rectangle.on.rectangle") { HostKeyboard.switchWindows() }
                    }
                    .buttonStyle(.glass)
                    .labelStyle(.titleAndIcon)
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct StreamControlsView: View {
    let model: StreamControlsModel
    @State private var confirmsQuit = false
    @State private var confirmsRestart = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let stats = model.statsText, !stats.isEmpty {
                    Text(stats)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                GlassEffectContainer {
                    VStack(alignment: .leading, spacing: 10) {
                        Button("Keyboard", systemImage: "keyboard") { model.toggleKeyboard() }
                        if let size = model.restartSize {
                            Button("Restart at \(size.width) × \(size.height)", systemImage: "arrow.up.left.and.arrow.down.right") {
                                confirmsRestart = true
                            }
                        }
                        if model.supportsClipboard {
                            PasteButton(payloadType: String.self) { strings in
                                Task { @MainActor in model.sendClipboard(strings.first) }
                            }
                            .labelStyle(.titleAndIcon)
                            Button("Get PC Clipboard", systemImage: "doc.on.clipboard") { model.fetchClipboard() }
                        }
                        Button("Disconnect", systemImage: "xmark") { model.disconnect() }
                        Button("Quit \(model.appName)", systemImage: "power", role: .destructive) { confirmsQuit = true }
                    }
                    .buttonStyle(.glass)
                }

                if let status = model.clipboardStatus {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            model.refreshRestartSize()
            while !Task.isCancelled {
                model.refreshStats()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .confirmationDialog("Quit \(model.appName)?", isPresented: $confirmsQuit, titleVisibility: .visible) {
            Button("Quit App", role: .destructive) { model.quitApp() }
        } message: {
            Text("Unsaved progress in \(model.appName) may be lost.")
        }
        .confirmationDialog("Restart to fit this display?", isPresented: $confirmsRestart, titleVisibility: .visible) {
            Button("Restart \(model.appName)", role: .destructive) { model.restartToFit() }
        } message: {
            Text("This quits \(model.appName) on your PC and starts it again at this display's size. Unsaved progress may be lost.")
        }
    }
}

private struct StreamOverlayCard: View {
    let model: StreamControlsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.appName)
                .font(.headline)
            StreamControlsView(model: model)
        }
        .padding(20)
        .frame(width: 340)
        .frame(maxHeight: 520)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }
}

private struct HostedView: UIViewRepresentable {
    let view: UIView

    func makeUIView(context: Context) -> UIView {
        view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
