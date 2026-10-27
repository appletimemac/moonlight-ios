import SwiftUI

struct AddHostSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(HostLibrary.self) private var library
    @State private var address = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @FocusState private var fieldFocused: Bool

    private var canAdd: Bool {
        !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isConnecting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("IP Address or Host Name", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($fieldFocused)
                        .onSubmit(add)
                        .disabled(isConnecting)
                } footer: {
                    Text("Moonlight finds PCs on your local network by itself. Add one here if it's on another subnet or you reach it through a VPN such as Tailscale (use its 100.x.y.z address). Add :port if your host uses a non-default port.")
                }

                if isConnecting {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Connecting")
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add PC")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", systemImage: "plus", action: add)
                        .disabled(!canAdd)
                }
            }
            .onChange(of: address) {
                errorMessage = nil
            }
            .onAppear {
                fieldFocused = true
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func add() {
        guard canAdd else { return }
        errorMessage = nil
        isConnecting = true
        Task {
            let error = await library.addHost(address: address)
            isConnecting = false
            if let error {
                errorMessage = error
                AccessibilityNotification.Announcement(error).post()
            } else {
                dismiss()
            }
        }
    }
}
