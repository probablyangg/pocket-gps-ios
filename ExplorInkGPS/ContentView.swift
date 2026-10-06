import SwiftUI
import UIKit

struct ContentView: View {
    @ObservedObject var bridge: GPSBridge
    @Environment(\.openURL) private var openURL
    private let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.57, green: 0.83, blue: 0.69, alpha: 1)
            : UIColor(red: 0.12, green: 0.25, blue: 0.20, alpha: 1)
    })

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PHONE IN POCKET.\nMAP IN HAND.")
                            .font(.system(.largeTitle, design: .serif, weight: .medium))
                        Text("GPS for your ExplorInk reader")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Label(bridge.status, systemImage: bridge.sharing ? "location.fill" : "map")
                            .font(.headline)
                        Text(bridge.detail).font(.subheadline).foregroundStyle(.secondary)
                        if bridge.connected || bridge.connecting {
                            Divider()
                            Text(bridge.readerName).font(.subheadline.monospaced())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20).background(.background, in: RoundedRectangle(cornerRadius: 20))

                    if bridge.sharing {
                        Button("Stop sharing", role: .destructive) { bridge.stopSharing() }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                    } else if bridge.connected {
                        Button("Start sharing location") { bridge.startSharing() }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                        Button("Disconnect reader") { bridge.disconnect() }
                    } else if bridge.connecting {
                        HStack { ProgressView(); Text("Connecting…") }
                        Button("Cancel") { bridge.disconnect() }
                    } else {
                        Button(bridge.scanning ? "Stop search" : "Find my reader") {
                            if bridge.scanning { bridge.cancelScan() } else { bridge.findReaders() }
                        }.buttonStyle(.borderedProminent).controlSize(.large)
                        if bridge.scanning { ProgressView("Searching nearby…") }
                        ForEach(bridge.readers) { reader in
                            Button { bridge.connect(to: reader) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(reader.name).font(.headline)
                                        Text(String(reader.id.uuidString.suffix(8)))
                                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("Connect").font(.subheadline)
                                }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain)
                        }
                    }

                    if bridge.needsSettings {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }

                    if let fix = bridge.lastFix {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Latest location").font(.headline)
                            Text(String(format: "%.5f, %.5f", fix.coordinate.latitude, fix.coordinate.longitude))
                                .font(.system(.title3, design: .monospaced)).textSelection(.enabled)
                            LabeledContent("Accuracy", value: String(format: "± %.0f m", fix.horizontalAccuracy))
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                LabeledContent("Fix age", value: "\(max(0, Int(context.date.timeIntervalSince(fix.timestamp)))) seconds")
                            }
                            LabeledContent("Acknowledged writes", value: "\(bridge.acknowledgedCount)")
                            if let acknowledged = bridge.lastAcknowledged {
                                LabeledContent("Last Bluetooth receipt", value: acknowledged.formatted(date: .omitted, time: .standard))
                            }
                            Text("A Bluetooth receipt confirms transport, not that the reader has redrawn its map.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 20))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Before your first walk").font(.headline)
                        Text("Your reader needs ExplorInk firmware and map tiles for your area already on its SD card. This prototype sends location; it does not download maps.")
                        Text("Start sharing with the app open, then lock your phone. Force-quitting the app ends sharing. GPS stops when you tap Stop or a reconnect times out.")
                    }.font(.subheadline).foregroundStyle(.secondary)

                    if !bridge.recentEvents.isEmpty {
                        DisclosureGroup("Connection details") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(bridge.recentEvents.enumerated()), id: \.offset) { _, event in
                                    Text(event).font(.caption.monospaced())
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                        }.font(.subheadline)
                    }
                    Text("Independent prototype · No account · No location history saved")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Pocket GPS").navigationBarTitleDisplayMode(.inline)
            .tint(ink)
        }
    }
}
