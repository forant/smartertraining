import SwiftUI

struct TrainerConnectionView: View {
    var manager: FTMSManager
    var onConnected: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            statusHeader

            if case .error(let msg) = manager.connectionState {
                errorBanner(msg)
            }

            if manager.connectionState == .bluetoothOff || manager.connectionState == .bluetoothUnauthorized {
                bluetoothUnavailableView
            } else {
                deviceList
                scanButton
            }
        }
        .padding()
        .onChange(of: manager.connectionState) { _, newValue in
            if newValue.isConnected {
                onConnected()
            }
        }
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: statusIcon)
                .font(.system(size: 40))
                .foregroundStyle(statusColor)

            Text(manager.connectionState.displayText)
                .font(.headline)

            if case .scanning = manager.connectionState {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.top, 16)
    }

    private var statusIcon: String {
        switch manager.connectionState {
        case .connected: "checkmark.circle.fill"
        case .scanning, .connecting, .discoveringServices: "antenna.radiowaves.left.and.right"
        case .bluetoothOff, .bluetoothUnauthorized: "exclamationmark.triangle.fill"
        case .error: "xmark.circle.fill"
        case .disconnected: "antenna.radiowaves.left.and.right"
        }
    }

    private var statusColor: Color {
        switch manager.connectionState {
        case .connected: .green
        case .scanning, .connecting, .discoveringServices: .accentColor
        case .bluetoothOff, .bluetoothUnauthorized, .error: .orange
        case .disconnected: .secondary
        }
    }

    // MARK: - Device List

    private var deviceList: some View {
        Group {
            if manager.discoveredDevices.isEmpty && manager.connectionState.isScanning {
                Text("Looking for trainers nearby...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 32)
            } else {
                ForEach(manager.discoveredDevices) { device in
                    Button {
                        manager.connect(to: device)
                    } label: {
                        HStack {
                            Image(systemName: "bicycle")
                                .foregroundStyle(.tint)
                            Text(device.name)
                                .font(.body)
                            Spacer()
                            if case .connecting(let name) = manager.connectionState, name == device.name {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Controls

    private var scanButton: some View {
        Button {
            if manager.connectionState.isScanning {
                manager.stopScanning()
            } else {
                manager.startScanning()
            }
        } label: {
            Text(manager.connectionState.isScanning ? "Stop Scanning" : "Scan for Trainers")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(manager.connectionState == .bluetoothOff || manager.connectionState == .bluetoothUnauthorized)
    }

    private var bluetoothUnavailableView: some View {
        VStack(spacing: 12) {
            Text("Please enable Bluetooth in Settings to connect to your trainer.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
