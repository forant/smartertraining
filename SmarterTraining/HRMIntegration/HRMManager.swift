import CoreBluetooth
import Foundation
import Observation

struct HRMDevice: Identifiable {
    let id: UUID
    let name: String
    let peripheral: CBPeripheral
}

@Observable
final class HRMManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    enum ConnectionState: Equatable {
        case bluetoothOff
        case bluetoothUnauthorized
        case disconnected
        case scanning
        case connecting(deviceName: String)
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
            case .connected(let name): "Connected to \(name)"
            case .error(let msg): msg
            }
        }
    }

    var connectionState: ConnectionState = .disconnected
    var discoveredDevices: [HRMDevice] = []
    var heartRate: Int?

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var pendingReconnectIdentifier: UUID?
    private var reconnectTimer: Timer?

    static let heartRateServiceUUID = CBUUID(string: "180D")
    static let heartRateMeasurementUUID = CBUUID(string: "2A37")
    private static let reconnectTimeout: TimeInterval = 10

    override init() {
        super.init()
        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
    }

    // MARK: - Scanning

    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        discoveredDevices.removeAll()
        connectionState = .scanning
        centralManager.scanForPeripherals(
            withServices: [Self.heartRateServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func stopScanning() {
        centralManager.stopScan()
        if case .scanning = connectionState {
            connectionState = .disconnected
        }
    }

    // MARK: - Connection

    func connect(to device: HRMDevice) {
        stopScanning()
        connectionState = .connecting(deviceName: device.name)
        connectedPeripheral = device.peripheral
        device.peripheral.delegate = self
        centralManager.connect(device.peripheral, options: nil)
    }

    func disconnect() {
        cancelReconnectTimer()
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        heartRate = nil
        connectionState = .disconnected
    }

    // MARK: - Reconnect

    func attemptReconnect(identifier: UUID) {
        guard centralManager.state == .poweredOn else {
            pendingReconnectIdentifier = identifier
            return
        }
        let peripherals = centralManager.retrievePeripherals(withIdentifiers: [identifier])
        guard let peripheral = peripherals.first else {
            connectionState = .disconnected
            return
        }

        let name = peripheral.name ?? "Heart rate monitor"
        connectionState = .connecting(deviceName: name)
        connectedPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
        startReconnectTimer()
    }

    private func startReconnectTimer() {
        cancelReconnectTimer()
        reconnectTimer = Timer.scheduledTimer(
            withTimeInterval: Self.reconnectTimeout,
            repeats: false
        ) { [weak self] _ in
            guard let self else { return }
            if case .connecting = self.connectionState {
                self.abortReconnect()
            }
        }
    }

    private func abortReconnect() {
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        connectionState = .disconnected
    }

    private func cancelReconnectTimer() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }

    // MARK: - HR Parsing

    static func parseBPM(from data: Data) -> Int? {
        guard data.count >= 2 else { return nil }
        let flags = data[0]
        let is16Bit = (flags & 0x01) != 0

        if is16Bit {
            guard data.count >= 3 else { return nil }
            return Int(UInt16(data[1]) | UInt16(data[2]) << 8)
        } else {
            return Int(data[1])
        }
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if let identifier = pendingReconnectIdentifier {
                pendingReconnectIdentifier = nil
                attemptReconnect(identifier: identifier)
            }
        case .poweredOff:
            connectionState = .bluetoothOff
            heartRate = nil
            cancelReconnectTimer()
        case .unauthorized:
            connectionState = .bluetoothUnauthorized
        default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard !discoveredDevices.contains(where: { $0.id == peripheral.identifier }) else { return }
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "Heart Rate Monitor"
        discoveredDevices.append(HRMDevice(id: peripheral.identifier, name: name, peripheral: peripheral))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        cancelReconnectTimer()
        peripheral.discoverServices([Self.heartRateServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        cancelReconnectTimer()
        connectionState = .error(error?.localizedDescription ?? "Connection failed")
        connectedPeripheral = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        heartRate = nil
        guard connectedPeripheral?.identifier == peripheral.identifier else { return }

        let name = peripheral.name ?? "Heart rate monitor"
        #if DEBUG
        print("[HRM] Disconnected from \(name), attempting reconnect...")
        #endif
        connectionState = .connecting(deviceName: name)
        centralManager.connect(peripheral, options: nil)
        startReconnectTimer()
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.heartRateServiceUUID }) else {
            connectionState = .error("Heart rate service not found")
            return
        }
        peripheral.discoverCharacteristics([Self.heartRateMeasurementUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        guard let characteristic = service.characteristics?.first(where: {
            $0.uuid == Self.heartRateMeasurementUUID
        }) else {
            connectionState = .error("Heart rate characteristic not found")
            return
        }
        peripheral.setNotifyValue(true, for: characteristic)
        let name = peripheral.name ?? "Heart rate monitor"
        connectionState = .connected(deviceName: name)

        RememberedDeviceStore.shared.hrm = RememberedDevice(
            peripheralIdentifier: peripheral.identifier,
            displayName: name,
            lastConnectedAt: Date()
        )

        #if DEBUG
        print("[HRM] Connected and subscribed to \(name)")
        #endif
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard characteristic.uuid == Self.heartRateMeasurementUUID,
              let data = characteristic.value,
              let bpm = Self.parseBPM(from: data) else { return }
        heartRate = bpm
    }
}
