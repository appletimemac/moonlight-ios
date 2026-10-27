import SwiftUI
import UIKit

struct PairingSheet: View {
    let session: PairingSession
    @Environment(HostLibrary.self) private var library
    @State private var lastPhase: PairingSession?

    // Follows the library's phase changes, and keeps the last one while the sheet slides
    // away (the library clears the session first)
    private var current: PairingSession {
        library.pairing ?? lastPhase ?? session
    }

    var body: some View {
        NavigationStack {
            Group {
                switch current.phase {
                case .naming:
                    NamingForm()
                case .requesting:
                    RequestingView(hostName: current.hostName)
                case .showingPIN(let pin):
                    PINView(pin: pin, hostName: current.hostName)
                }
            }
            .animation(.smooth, value: current.phase)
            .navigationTitle("Pair with \(current.hostName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { library.cancelPairing() }
                }
            }
        }
        .interactiveDismissDisabled()
        .presentationDetents([.medium, .large])
        .onChange(of: library.pairing?.phase) {
            if let live = library.pairing {
                lastPhase = live
            }
        }
    }
}

private struct NamingForm: View {
    @Environment(HostLibrary.self) private var library
    @State private var deviceName = AppPreferences.pairingDeviceName ?? "Moonlight on " + UIDevice.current.model

    private var trimmedName: String {
        deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            Section {
                TextField("Device Name", text: $deviceName)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(confirm)
            } footer: {
                Text("Your PC lists this device under this name. Apollo uses it for per-device permissions and display settings.")
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Pair", systemImage: "link", action: confirm)
                    .disabled(trimmedName.isEmpty)
            }
        }
    }

    private func confirm() {
        guard !trimmedName.isEmpty else { return }
        library.confirmPairing(deviceName: trimmedName)
    }
}

private struct RequestingView: View {
    let hostName: String

    var body: some View {
        ProgressView("Contacting \(hostName)")
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PINView: View {
    let pin: String
    let hostName: String

    @ScaledMetric(relativeTo: .largeTitle) private var pinSize: CGFloat = 64
    @ScaledMetric(relativeTo: .largeTitle) private var pinTracking: CGFloat = 8

    // One digit at a time with pauses, so VoiceOver does not read "1234" as a number
    private var spokenPIN: String {
        pin.map(String.init).joined(separator: ", ")
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
                .frame(maxHeight: .infinity)
            ScrollView {
                content
            }
        }
    }

    private var content: some View {
        VStack(spacing: 24) {
            Text(pin)
                .font(.system(size: pinSize, weight: .semibold, design: .monospaced))
                .tracking(pinTracking)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .textSelection(.enabled)
                .accessibilityLabel("PIN")
                .accessibilityValue(spokenPIN)

            VStack(spacing: 8) {
                Text("On your PC, enter this PIN.")
                    .font(.headline)
                Text("Apollo and Sunshine: open the web UI and go to the PIN page. GeForce Experience shows a prompt on the PC.")
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            ProgressView("Waiting for \(hostName)")
                .controlSize(.small)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}
