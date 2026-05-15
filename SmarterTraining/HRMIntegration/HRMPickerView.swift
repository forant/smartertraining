import SwiftUI

struct HRMPickerView: View {
    var manager: HRMManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                statusHeader

                if case .error(let msg) = manager.connectionState {
                    errorBanner(msg)
                }

                deviceList
                controls
            }
            .padding()
            .navigationTitle("Heart Rate Monitor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if !manager.connectionState.isConnected && !manager.connectionState.isScanning {
                    manager.startScanning()
                }
            }
            .onDisappear {
                manager.stopScanning()
            }
            .onChange(of: manager.connectionState) { _, newValue in
                if newValue.isConnected {
                    dismiss()
                }
            }
        }
    }

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
            if case .connecting = manager.connectionState {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.top, 16)
    }

    private var statusIcon: String {
        switch manager.connectionState {
        case .connected: "checkmark.circle.fill"
        case .scanning, .connecting: "heart.fill"
        case .error: "xmark.circle.fill"
        default: "heart"
        }
    }

    private var statusColor: Color {
        switch manager.connectionState {
        case .connected: .green
        case .scanning, .connecting: .red.opacity(0.7)
        case .error: .orange
        default: .secondary
        }
    }

    private var deviceList: some View {
        Group {
            if manager.discoveredDevices.isEmpty && manager.connectionState.isScanning {
                Text("Looking for heart rate monitors...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 32)
            } else {
                ForEach(manager.discoveredDevices) { device in
                    Button {
                        manager.connect(to: device)
                    } label: {
                        HStack {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red.opacity(0.7))
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

    @ViewBuilder
    private var controls: some View {
        if manager.connectionState.isConnected {
            Button(role: .destructive) {
                manager.disconnect()
            } label: {
                Text("Disconnect")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        } else {
            Button {
                if manager.connectionState.isScanning {
                    manager.stopScanning()
                } else {
                    manager.startScanning()
                }
            } label: {
                Text(manager.connectionState.isScanning ? "Stop Scanning" : "Scan")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }

        if RememberedDeviceStore.shared.hrm != nil && !manager.connectionState.isConnected {
            Button {
                RememberedDeviceStore.shared.forgetHRM()
            } label: {
                Text("Forget saved monitor")
                    .font(.subheadline)
            }
        }
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
