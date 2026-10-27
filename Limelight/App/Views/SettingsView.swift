import AVFoundation
import SwiftUI
import VideoToolbox

struct SettingsView: View {
    @Environment(HostLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var model = SettingsModel()
    @FocusState private var focusedField: Field?

    @AppStorage(AppPreferences.resolutionModeKey) private var resolutionMode = ResolutionMode.matchDisplay
    @AppStorage(AppPreferences.useVirtualDisplayKey) private var useVirtualDisplay = false
    @AppStorage(AppPreferences.virtualDisplayScaleKey) private var virtualDisplayScale = 100
    @AppStorage(AppPreferences.pairingDeviceNameKey) private var deviceName = ""
    @AppStorage(AppPreferences.tabletopPanelKey) private var tabletopPanel = TabletopPanel.trackpad

    private enum Field: Hashable {
        case width, height, deviceName
    }

    var body: some View {
        NavigationStack {
            Form {
                resolutionSection
                videoSection
                bitrateSection
                inputSection
                audioSection
                hostSection
                apolloSection
                duoSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { saveAndDismiss() }
                }
                ToolbarItem(placement: .keyboard) {
                    Button("Dismiss Keyboard", systemImage: "keyboard.chevron.compact.down") { focusedField = nil }
                }
            }
            .onChange(of: focusedField) { commitCustomResolution() }
        }
        .onDisappear { save() }
    }

    private func save() {
        commitCustomResolution()
        model.save()
    }

    private func saveAndDismiss() {
        save()
        dismiss()
    }

    private var matchedSize: PixelSize? {
        guard let window = library.presenter.window else { return nil }
        return StreamResolution.matchingDisplay(
            points: window.bounds.size,
            scale: window.traitCollection.displayScale,
            landscapeOnly: window.traitCollection.userInterfaceIdiom == .phone,
            maxDimension: VideoSupport.maxResolutionDimension)
    }

    private var streamSize: PixelSize {
        if resolutionMode == .matchDisplay, let matchedSize {
            return matchedSize
        }
        return model.values.size
    }

    private var currentResolutionChoice: ResolutionChoice {
        resolutionMode == .matchDisplay ? .matchDisplay : model.fixedChoice
    }

    private var resolutionChoices: [ResolutionChoice] {
        let current = currentResolutionChoice
        return ResolutionChoice.allCases.filter { $0 != .p2160 || VideoSupport.hevc || $0 == current }
    }

    private var resolutionChoice: Binding<ResolutionChoice> {
        Binding(
            get: { currentResolutionChoice },
            set: { choice in
                let previous = streamSize
                if choice == .matchDisplay {
                    resolutionMode = .matchDisplay
                } else {
                    resolutionMode = .fixed
                    model.selectFixed(choice)
                }
                let size = choice == .matchDisplay ? (matchedSize ?? model.values.size) : model.values.size
                if size != previous {
                    model.resetBitrate(for: size)
                }
            })
    }

    private func commitCustomResolution() {
        guard resolutionMode == .fixed, model.fixedChoice == .custom else { return }
        if model.commitCustomResolution() {
            model.resetBitrate(for: model.values.size)
        }
    }

    private var resolutionSection: some View {
        Section {
            Picker("Resolution", selection: resolutionChoice) {
                ForEach(resolutionChoices, id: \.self) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.menu)

            LabeledContent("Stream Size", value: streamSize.label)

            if currentResolutionChoice == .custom {
                LabeledContent("Width") {
                    TextField("Pixels", text: $model.customWidthText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .width)
                }
                LabeledContent("Height") {
                    TextField("Pixels", text: $model.customHeightText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .height)
                }
            }
        } header: {
            Text("Resolution")
        } footer: {
            switch currentResolutionChoice {
            case .matchDisplay:
                Text("Streams at this display's shape and resolution. On a PC running Apollo, the virtual display matches it too. If you fold or unfold iPhone Duo mid-game, the picture is rescaled.")
            case .custom:
                Text("Sizes are rounded down to even numbers from 256 to \(String(VideoSupport.maxResolutionDimension)) pixels. Custom resolutions are not officially supported by GeForce Experience, so it will not set your host display resolution. You will need to set it manually while in game. Resolutions that are not supported by your client or host PC may cause streaming errors.")
            default:
                EmptyView()
            }
        }
    }

    private var maxFrameRate: Int {
        library.presenter.window?.windowScene?.screen.maximumFramesPerSecond ?? 60
    }

    private var frameRates: [Int] {
        // Only offer 120 FPS on a display that can show more than 60-ish Hz
        maxFrameRate > 62 ? [30, 60, 120] : [30, 60]
    }

    private var frameRate: Binding<Int> {
        Binding(
            get: { frameRates.contains(model.values.framerate) ? model.values.framerate : 60 },
            set: { rate in
                model.values.framerate = rate
                model.resetBitrate(for: streamSize)
            })
    }

    private var codecs: [CodecPreference] {
        CodecPreference.allCases.filter { codec in
            switch codec {
            case .automatic, .h264: true
            case .hevc: VideoSupport.hevc
            case .av1: VideoSupport.av1
            }
        }
    }

    private var codec: Binding<CodecPreference> {
        Binding(
            get: { codecs.contains(model.values.codec) ? model.values.codec : .automatic },
            set: { model.values.codec = $0 })
    }

    private var hdrSupported: Bool {
        VideoSupport.hevc && AVPlayer.eligibleForHDRPlayback
    }

    private var videoSection: some View {
        Section {
            SegmentedPicker("Frame Rate", selection: frameRate) {
                ForEach(frameRates, id: \.self) { rate in
                    Text("\(rate) FPS").tag(rate)
                }
            }

            Picker("Codec", selection: codec) {
                ForEach(codecs, id: \.self) { codec in
                    Text(codec.title).tag(codec)
                }
            }
            .pickerStyle(.menu)

            Picker("Frame Pacing", selection: $model.values.useFramePacing) {
                Text("Lowest Latency").tag(false)
                Text("Smoothest Video").tag(true)
            }
            .pickerStyle(.menu)

            Toggle("Statistics Overlay", isOn: $model.values.statsOverlay)

            Toggle("HDR (Beta)", isOn: hdrSupported ? $model.values.enableHdr : .constant(false))
                .disabled(!hdrSupported)
        } header: {
            Text("Video")
        } footer: {
            if !hdrSupported {
                Text("HDR is unsupported on this device.")
            }
        }
    }

    private var bitrateIndex: Binding<Double> {
        Binding(
            get: { Double(Bitrate.sliderIndex(for: model.values.bitrate)) },
            set: { index in
                // Settle a pending custom size first so it cannot reset this choice later
                commitCustomResolution()
                model.values.bitrate = Bitrate.table[min(max(Int(index.rounded()), 0), Bitrate.lastIndex)]
            })
    }

    private var bitrateText: String {
        let megabits = (Double(model.values.bitrate) / 1000).formatted(.number.precision(.fractionLength(1)))
        return "\(megabits) Mbps"
    }

    private var bitrateSection: some View {
        Section {
            LabeledContent("Bitrate", value: bitrateText)
            Slider(value: bitrateIndex, in: 0...Double(Bitrate.lastIndex), step: 1) {
                Text("Bitrate")
            }
            .accessibilityValue(bitrateText)
        } footer: {
            Text("Changing the resolution or frame rate resets the bitrate to the recommended value.")
        }
    }

    private var inputSection: some View {
        Section {
            SegmentedPicker("Touch Mode", selection: $model.values.absoluteTouchMode) {
                Text("Trackpad").tag(false)
                Text("Touchscreen").tag(true)
            }

            Picker("On-Screen Controls", selection: $model.values.onscreenControls) {
                Text("Off").tag(0)
                Text("Auto").tag(1)
                Text("Simple").tag(2)
                Text("Full").tag(3)
            }
            .pickerStyle(.menu)
            .disabled(model.values.absoluteTouchMode)

            SegmentedPicker("Multi-Controller Mode", selection: $model.values.multiController) {
                Text("Single").tag(false)
                Text("Automatic").tag(true)
            }

            Toggle("Swap A/B and X/Y Buttons", isOn: $model.values.swapABXYButtons)

            Toggle("Citrix X1 Mouse Support", isOn: $model.values.btMouseSupport)
        } header: {
            Text("Input")
        } footer: {
            if model.values.absoluteTouchMode {
                Text("On-screen controls are not available in Touchscreen mode.")
            }
        }
    }

    private var audioSection: some View {
        Section("Audio") {
            Toggle("Play Audio on PC", isOn: $model.values.playAudioOnPC)
        }
    }

    private var hostSection: some View {
        Section("Host") {
            Toggle("Optimize Game Settings", isOn: $model.values.optimizeGames)
        }
    }

    private var apolloSection: some View {
        Section {
            Toggle("Use Virtual Display", isOn: $useVirtualDisplay)

            Picker("Virtual Display Scale", selection: $virtualDisplayScale) {
                ForEach([100, 125, 150, 200], id: \.self) { percent in
                    Text("\(percent)%").tag(percent)
                }
            }
            .pickerStyle(.menu)
            .disabled(!useVirtualDisplay)

            LabeledContent("Device Name") {
                TextField("Name this device", text: $deviceName)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focusedField, equals: .deviceName)
            }
        } header: {
            Text("Apollo")
        } footer: {
            Text("The PC shows this name in its client list. A changed name applies the next time this device pairs.")
        }
    }

    private var duoSection: some View {
        Section {
            Picker("Tabletop Panel", selection: $tabletopPanel) {
                ForEach(TabletopPanel.allCases, id: \.self) { panel in
                    Text(panel.title).tag(panel)
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text("iPhone Duo")
        } footer: {
            Text("When iPhone Duo is half folded or upright in portrait, the game plays on the top half and this panel fills the bottom half.")
        }
    }
}

private struct SettingsValues: Equatable {
    var bitrate: Int
    var framerate: Int
    var width: Int
    var height: Int
    var onscreenControls: Int
    var codec: CodecPreference
    var useFramePacing: Bool
    var multiController: Bool
    var swapABXYButtons: Bool
    var playAudioOnPC: Bool
    var optimizeGames: Bool
    var enableHdr: Bool
    var btMouseSupport: Bool
    var absoluteTouchMode: Bool
    var statsOverlay: Bool

    var size: PixelSize {
        PixelSize(width: width, height: height)
    }

    init(_ settings: TemporarySettings) {
        // Land exactly on a slider notch, as the UIKit screen did
        bitrate = Bitrate.table[Bitrate.sliderIndex(for: settings.bitrate.intValue)]
        let rate = settings.framerate.intValue
        framerate = [30, 60, 120].contains(rate) ? rate : 60
        width = settings.width.intValue
        height = settings.height.intValue
        onscreenControls = min(max(settings.onscreenControls.intValue, 0), 3)
        codec = CodecPreference(rawValue: settings.preferredCodec) ?? .automatic
        useFramePacing = settings.useFramePacing
        multiController = settings.multiController
        swapABXYButtons = settings.swapABXYButtons
        playAudioOnPC = settings.playAudioOnPC
        optimizeGames = settings.optimizeGames
        enableHdr = settings.enableHdr
        btMouseSupport = settings.btMouseSupport
        absoluteTouchMode = settings.absoluteTouchMode
        statsOverlay = settings.statsOverlay
    }
}

@MainActor @Observable
private final class SettingsModel {
    var values: SettingsValues
    var customWidthText: String
    var customHeightText: String
    private var usesCustomResolution = false
    @ObservationIgnored private var lastSaved: SettingsValues?

    init() {
        let loaded = SettingsValues(DataManager().getSettings()!)
        values = loaded
        customWidthText = String(loaded.width)
        customHeightText = String(loaded.height)
    }

    var fixedChoice: ResolutionChoice {
        if usesCustomResolution {
            return .custom
        }
        return ResolutionChoice.allCases.first { $0.size == values.size } ?? .custom
    }

    func selectFixed(_ choice: ResolutionChoice) {
        if let size = choice.size {
            values.width = size.width
            values.height = size.height
            usesCustomResolution = false
        } else {
            usesCustomResolution = true
            customWidthText = String(values.width)
            customHeightText = String(values.height)
        }
    }

    // Applies the typed custom size, returning whether it changed the stream size
    func commitCustomResolution() -> Bool {
        let width = clampedDimension(customWidthText, fallback: values.width)
        let height = clampedDimension(customHeightText, fallback: values.height)
        customWidthText = String(width)
        customHeightText = String(height)
        guard width != values.width || height != values.height else { return false }
        values.width = width
        values.height = height
        return true
    }

    private func clampedDimension(_ text: String, fallback: Int) -> Int {
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)), value > 0 else { return fallback }
        // 4:2:0 video needs even dimensions
        return min(max(value & ~1, 256), VideoSupport.maxResolutionDimension)
    }

    func resetBitrate(for size: PixelSize) {
        values.bitrate = Bitrate.recommended(for: size, frameRate: values.framerate)
    }

    func save() {
        guard values != lastSaved else { return }
        lastSaved = values
        DataManager().saveSettings(
            withBitrate: values.bitrate,
            framerate: values.framerate,
            height: values.height,
            width: values.width,
            audioConfig: 2,
            onscreenControls: values.onscreenControls,
            optimizeGames: values.optimizeGames,
            multiController: values.multiController,
            swapABXYButtons: values.swapABXYButtons,
            audioOnPC: values.playAudioOnPC,
            preferredCodec: values.codec.rawValue,
            useFramePacing: values.useFramePacing,
            enableHdr: values.enableHdr,
            btMouseSupport: values.btMouseSupport,
            absoluteTouchMode: values.absoluteTouchMode,
            statsOverlay: values.statsOverlay)
    }
}

private enum VideoSupport {
    static let hevc = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
    static let av1 = VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)

    static var maxResolutionDimension: Int {
        hevc ? 8192 : 4096
    }
}

private enum Bitrate {
    static let table = [
        500, 1000, 1500, 2000, 2500, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 10000,
        12000, 15000, 18000, 20000, 30000, 40000, 50000, 60000, 70000, 80000, 100_000,
        120_000, 150_000,
    ]

    static var lastIndex: Int {
        table.count - 1
    }

    static func sliderIndex(for bitrate: Int) -> Int {
        table.firstIndex { bitrate <= $0 } ?? lastIndex
    }

    // Ported from Moonlight Qt's default bitrate, as the UIKit screen did
    static func recommended(for size: PixelSize, frameRate: Int) -> Int {
        let fps = Float(frameRate)
        // Bitrate does not scale linearly beyond 60 FPS
        let frameRateFactor = (frameRate <= 60 ? fps : sqrtf(fps / 60) * 60) / 30

        let factors: [(pixels: Int, factor: Float)] = [
            (640 * 360, 1),
            (854 * 480, 2),
            (1280 * 720, 5),
            (1920 * 1080, 10),
            (2560 * 1440, 20),
            (3840 * 2160, 40),
        ]
        let pixels = size.width * size.height
        var resolutionFactor = factors[factors.count - 1].factor
        for (index, entry) in factors.enumerated() {
            if pixels == entry.pixels || (pixels < entry.pixels && index == 0) {
                resolutionFactor = entry.factor
                break
            }
            if pixels < entry.pixels {
                let lower = factors[index - 1]
                let fraction = Float(pixels - lower.pixels) / Float(entry.pixels - lower.pixels)
                resolutionFactor = fraction * (entry.factor - lower.factor) + lower.factor
                break
            }
        }
        return min(Int((resolutionFactor * frameRateFactor).rounded()) * 1000, 100_000)
    }
}

private enum ResolutionChoice: CaseIterable, Hashable {
    case matchDisplay, p720, p1080, p1440, p2160, custom

    var title: LocalizedStringKey {
        switch self {
        case .matchDisplay: "Match Display"
        case .p720: "720p"
        case .p1080: "1080p"
        case .p1440: "1440p"
        case .p2160: "4K"
        case .custom: "Custom"
        }
    }

    var size: PixelSize? {
        switch self {
        case .matchDisplay, .custom: nil
        case .p720: PixelSize(width: 1280, height: 720)
        case .p1080: PixelSize(width: 1920, height: 1080)
        case .p1440: PixelSize(width: 2560, height: 1440)
        case .p2160: PixelSize(width: 3840, height: 2160)
        }
    }
}

private extension PixelSize {
    var label: String {
        "\(width) x \(height)"
    }
}

private extension CodecPreference {
    var title: LocalizedStringKey {
        switch self {
        case .automatic: "Automatic"
        case .h264: "H.264"
        case .hevc: "HEVC"
        case .av1: "AV1"
        }
    }
}

private extension TabletopPanel {
    var title: LocalizedStringKey {
        switch self {
        case .trackpad: "Trackpad and Keys"
        case .gamepad: "Gamepad"
        case .controls: "Stream Controls"
        }
    }
}

// A labeled segmented control, which becomes a menu once text is too large for segments
private struct SegmentedPicker<Selection: Hashable, Options: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let title: LocalizedStringKey
    private let selection: Binding<Selection>
    private let options: Options

    init(_ title: LocalizedStringKey, selection: Binding<Selection>, @ViewBuilder options: () -> Options) {
        self.title = title
        self.selection = selection
        self.options = options()
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Picker(title, selection: selection) { options }
                .pickerStyle(.menu)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .accessibilityHidden(true)
                Picker(title, selection: selection) { options }
                    .pickerStyle(.segmented)
                    .labelsHidden()
            }
        }
    }
}
