import AVKit
import CrookcookedCore
import SwiftUI

struct PhoneDashboardView: View {
    @ObservedObject var model: PhoneModel
    @State private var isScanning = false
    @State private var showManualPairing = false
    @State private var scanError: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Pair with your Mac") {
                    Button {
                        scanError = nil
                        isScanning = true
                    } label: {
                        Label("Scan the code on your Mac", systemImage: "qrcode.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .listRowSeparator(.hidden)

                    if let scanError {
                        Label(scanError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    HStack {
                        Label(model.connectionState, systemImage: "network")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Verify: \(model.pairingCode)").font(.caption.monospacedDigit())
                    }

                    // Typing a 16-character secret is the step people get wrong, so
                    // it stays available but folded out of the way.
                    DisclosureGroup("Enter details manually", isExpanded: $showManualPairing) {
                        TextField("wss://relay.example.com", text: $model.relayURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Pairing secret from Mac", text: $model.pairingSecret)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        Button("Connect") { model.connect() }
                    }
                    .font(.subheadline)
                }

                Section("Mac") {
                    HStack {
                        Label(statusTitle, systemImage: statusIcon)
                            .foregroundStyle(model.macStatus == .triggered ? .red : .primary)
                        Spacer()
                        Button(model.macStatus == .disarmed ? "Arm" : "Disarm") {
                            model.macStatus == .disarmed ? model.arm() : model.disarm()
                        }
                    }
                }

                Section("Live camera") {
                    Group {
                        if let image = model.liveImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            ContentUnavailableView("No camera frame", systemImage: "video.slash", description: Text("Start live view or request a snapshot."))
                                .frame(height: 220)
                        }
                    }
                    HStack {
                        Button(model.isStreaming ? "Stop live view" : "Start live view") { model.toggleStream() }
                        Spacer()
                        Button("Snapshot") { model.requestSnapshot() }
                    }
                }

                if let url = model.latestClipURL {
                    Section("Latest evidence clip") {
                        VideoPlayer(player: AVPlayer(url: url)).frame(height: 230)
                        ShareLink(item: url) { Label("Save or share clip", systemImage: "square.and.arrow.up") }
                    }
                }

                Section("Alerts") {
                    if model.events.isEmpty {
                        Text("No alerts yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(model.events) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.event.kind.title).fontWeight(.semibold)
                                Text(item.event.occurredAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                                if let image = item.image {
                                    Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("crookcooked")
            .tint(Color(red: 0.949, green: 0.243, blue: 0.196))
        }
        .sheet(isPresented: $isScanning) { scannerSheet }
    }

    @ViewBuilder
    private var scannerSheet: some View {
        NavigationStack {
            PairingScannerView(
                onFound: { payload in
                    model.apply(payload)
                    isScanning = false
                },
                onFailure: { message in
                    scanError = message
                    isScanning = false
                }
            )
            .ignoresSafeArea()
            .overlay(alignment: .bottom) {
                Text("Point at the QR code shown in crookcooked on your Mac.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(22)
            }
            .navigationTitle("Scan to pair")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isScanning = false }
                }
            }
        }
    }

    private var statusTitle: String {
        switch model.macStatus {
        case .disarmed: return "disarmed"
        case .arming: return "arming"
        case .armed: return "armed"
        case .triggered: return "alert triggered"
        }
    }

    private var statusIcon: String {
        switch model.macStatus {
        case .disarmed: return "shield"
        case .arming: return "timer"
        case .armed: return "shield.fill"
        case .triggered: return "exclamationmark.shield.fill"
        }
    }
}
