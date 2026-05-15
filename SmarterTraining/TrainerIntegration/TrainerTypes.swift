import CoreBluetooth
import Foundation

struct TrainerDevice: Identifiable {
    let id: UUID
    let name: String
    let peripheral: CBPeripheral
}

enum TrainerConnectionState: Equatable {
    case bluetoothOff
    case bluetoothUnauthorized
    case disconnected
    case scanning
    case connecting(deviceName: String)
    case discoveringServices
    case connected(deviceName: String)
    case error(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var isScanning: Bool {
        if case .scanning = self { return true }
        return false
    }

    var displayText: String {
        switch self {
        case .bluetoothOff: "Bluetooth is off"
        case .bluetoothUnauthorized: "Bluetooth permission required"
        case .disconnected: "Not connected"
        case .scanning: "Scanning..."
        case .connecting(let name): "Connecting to \(name)..."
        case .discoveringServices: "Setting up..."
        case .connected(let name): "Connected to \(name)"
        case .error(let msg): msg
        }
    }
}

struct TrainerMetrics {
    var power: Int?
    var cadence: Double?
    var speed: Double?
    var heartRate: Int?
    var timestamp: Date

    static let empty = TrainerMetrics(power: nil, cadence: nil, speed: nil, heartRate: nil, timestamp: .distantPast)
}

enum ERGState: Equatable {
    case off
    case enabling
    case active
    case unsupported
    case failed(String)

    var label: String {
        switch self {
        case .off: "Off"
        case .enabling: "Enabling..."
        case .active: "Active"
        case .unsupported: "Unsupported"
        case .failed: "Failed"
        }
    }
}

enum TrainerCommand {
    case requestControl
    case setTargetPower(watts: Int16)
    case startOrResume
    case stop
    case pause
    case reset

    var bytes: [UInt8] {
        switch self {
        case .requestControl:
            return [FTMS.ControlPointOpCode.requestControl.rawValue]
        case .setTargetPower(let watts):
            let low = UInt8(truncatingIfNeeded: watts)
            let high = UInt8(truncatingIfNeeded: watts >> 8)
            return [FTMS.ControlPointOpCode.setTargetPower.rawValue, low, high]
        case .startOrResume:
            return [FTMS.ControlPointOpCode.startOrResume.rawValue]
        case .stop:
            return [FTMS.ControlPointOpCode.stopOrPause.rawValue, 0x01]
        case .pause:
            return [FTMS.ControlPointOpCode.stopOrPause.rawValue, 0x02]
        case .reset:
            return [FTMS.ControlPointOpCode.reset.rawValue]
        }
    }
}
