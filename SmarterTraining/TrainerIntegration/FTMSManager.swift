import CoreBluetooth
import Foundation
import Observation

@Observable
final class FTMSManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    private(set) var connectionState: TrainerConnectionState = .disconnected
    private(set) var discoveredDevices: [TrainerDevice] = []
    private(set) var metrics: TrainerMetrics = .empty
    private(set) var supportsERG = false
    private(set) var hasControlPoint = false
    private(set) var controlAcquired = false

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var controlPointCharacteristic: CBCharacteristic?
    private var pendingReconnectIdentifier: UUID?
    private var reconnectTimer: Timer?
    private static let reconnectTimeout: TimeInterval = 10

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Public API

    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        discoveredDevices.removeAll()
        connectionState = .scanning
        centralManager.scanForPeripherals(withServices: [FTMS.serviceUUID], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    }

    func stopScanning() {
        centralManager.stopScan()
        if case .scanning = connectionState {
            connectionState = .disconnected
        }
    }

    func connect(to device: TrainerDevice) {
        centralManager.stopScan()
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
        cleanUpConnection()
    }

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

        let name = peripheral.name ?? "Trainer"
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
                #if DEBUG
                print("[FTMS] Reconnect timed out")
                #endif
                if let peripheral = self.connectedPeripheral {
                    self.centralManager.cancelPeripheralConnection(peripheral)
                }
                self.cleanUpConnection()
            }
        }
    }

    private func cancelReconnectTimer() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }

    func send(_ command: TrainerCommand) {
        guard let characteristic = controlPointCharacteristic else {
            #if DEBUG
            print("[FTMS] Cannot send \(command) — no control point characteristic")
            #endif
            return
        }

        let data = Data(command.bytes)
        connectedPeripheral?.writeValue(data, for: characteristic, type: .withResponse)

        #if DEBUG
        print("[FTMS] Sent: \(command) (\(command.bytes.map { String(format: "0x%02X", $0) }.joined(separator: " ")))")
        #endif
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        #if DEBUG
        print("[FTMS] Central state: \(central.state.rawValue)")
        #endif
        switch central.state {
        case .poweredOn:
            if case .bluetoothOff = connectionState {
                connectionState = .disconnected
            }
            if let identifier = pendingReconnectIdentifier {
                pendingReconnectIdentifier = nil
                attemptReconnect(identifier: identifier)
            }
        case .poweredOff:
            connectionState = .bluetoothOff
            cancelReconnectTimer()
            cleanUpConnection()
        case .unauthorized:
            connectionState = .bluetoothUnauthorized
        case .unsupported:
            connectionState = .error("Bluetooth LE not supported on this device")
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown Trainer"

        if !discoveredDevices.contains(where: { $0.peripheral.identifier == peripheral.identifier }) {
            #if DEBUG
            print("[FTMS] Discovered: \(name) (RSSI: \(RSSI))")
            #endif
            discoveredDevices.append(TrainerDevice(
                id: peripheral.identifier,
                name: name,
                peripheral: peripheral
            ))
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        cancelReconnectTimer()
        #if DEBUG
        print("[FTMS] Connected to \(peripheral.name ?? "unknown")")
        #endif
        connectionState = .discoveringServices
        peripheral.discoverServices([FTMS.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        cancelReconnectTimer()
        #if DEBUG
        print("[FTMS] Connection failed: \(error?.localizedDescription ?? "unknown")")
        #endif
        connectionState = .error("Connection failed: \(error?.localizedDescription ?? "unknown")")
        cleanUpConnection()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        let wasConnected = connectedPeripheral?.identifier == peripheral.identifier
        #if DEBUG
        print("[FTMS] Disconnected from \(peripheral.name ?? "unknown"), error: \(error?.localizedDescription ?? "none")")
        #endif
        cleanUpConnection()
        if wasConnected {
            connectionState = .error("Trainer disconnected")
        }
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        if let error {
            #if DEBUG
            print("[FTMS] Service discovery error: \(error.localizedDescription)")
            #endif
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == FTMS.serviceUUID }) else {
            connectionState = .error("FTMS service not found")
            return
        }
        #if DEBUG
        print("[FTMS] Found FTMS service, discovering characteristics...")
        #endif
        peripheral.discoverCharacteristics([
            FTMS.indoorBikeDataUUID,
            FTMS.fitnessMachineFeatureUUID,
            FTMS.fitnessMachineControlPointUUID,
            FTMS.fitnessMachineStatusUUID
        ], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        guard let characteristics = service.characteristics else {
            connectionState = .error("No characteristics found")
            return
        }

        #if DEBUG
        print("[FTMS] Discovered \(characteristics.count) characteristics:")
        for c in characteristics {
            print("[FTMS]   \(c.uuid) — properties: \(c.properties)")
        }
        #endif

        for characteristic in characteristics {
            switch characteristic.uuid {
            case FTMS.indoorBikeDataUUID:
                peripheral.setNotifyValue(true, for: characteristic)
                #if DEBUG
                print("[FTMS] Subscribed to indoor bike data (notify)")
                #endif

            case FTMS.fitnessMachineFeatureUUID:
                peripheral.readValue(for: characteristic)
                #if DEBUG
                print("[FTMS] Reading fitness machine features...")
                #endif

            case FTMS.fitnessMachineControlPointUUID:
                controlPointCharacteristic = characteristic
                hasControlPoint = true
                let supportsIndicate = characteristic.properties.contains(.indicate)
                let supportsNotify = characteristic.properties.contains(.notify)
                peripheral.setNotifyValue(true, for: characteristic)
                #if DEBUG
                print("[FTMS] Control point found — notify: \(supportsNotify), indicate: \(supportsIndicate)")
                #endif

            case FTMS.fitnessMachineStatusUUID:
                peripheral.setNotifyValue(true, for: characteristic)
                #if DEBUG
                print("[FTMS] Subscribed to machine status (notify)")
                #endif

            default:
                #if DEBUG
                print("[FTMS] Ignoring characteristic: \(characteristic.uuid)")
                #endif
            }
        }

        let deviceName = peripheral.name ?? "Trainer"
        connectionState = .connected(deviceName: deviceName)

        RememberedDeviceStore.shared.trainer = RememberedDevice(
            peripheralIdentifier: peripheral.identifier,
            displayName: deviceName,
            lastConnectedAt: Date()
        )
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        if let error {
            #if DEBUG
            print("[FTMS] Read error on \(characteristic.uuid): \(error.localizedDescription)")
            #endif
            return
        }
        guard let data = characteristic.value else { return }

        switch characteristic.uuid {
        case FTMS.indoorBikeDataUUID:
            metrics = FTMSParser.parseIndoorBikeData(data)

        case FTMS.fitnessMachineFeatureUUID:
            supportsERG = FTMSParser.supportsTargetPower(data)
            #if DEBUG
            print("[FTMS] Feature flags read — ERG (target power) supported: \(supportsERG)")
            #endif

        case FTMS.fitnessMachineControlPointUUID:
            if let response = FTMSParser.parseControlPointResponse(data) {
                let wasRequestControl = response.opCode == FTMS.ControlPointOpCode.requestControl.rawValue
                let wasSetTarget = response.opCode == FTMS.ControlPointOpCode.setTargetPower.rawValue
                #if DEBUG
                print("[FTMS] Control point response — opCode: 0x\(String(format: "%02X", response.opCode)), success: \(response.success)")
                #endif
                if wasRequestControl && response.success {
                    controlAcquired = true
                    #if DEBUG
                    print("[FTMS] Control acquired")
                    #endif
                }
                if wasRequestControl && !response.success {
                    #if DEBUG
                    print("[FTMS] Control request DENIED")
                    #endif
                }
                if wasSetTarget {
                    #if DEBUG
                    print("[FTMS] Set target power response — success: \(response.success)")
                    #endif
                }
            }

        case FTMS.fitnessMachineStatusUUID:
            #if DEBUG
            print("[FTMS] Machine status update: \(data.map { String(format: "0x%02X", $0) }.joined(separator: " "))")
            #endif

        default:
            break
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        #if DEBUG
        if let error {
            print("[FTMS] Write error on \(characteristic.uuid): \(error.localizedDescription)")
        } else {
            print("[FTMS] Write succeeded on \(characteristic.uuid)")
        }
        #endif
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?) {
        #if DEBUG
        if let error {
            print("[FTMS] Notification setup error on \(characteristic.uuid): \(error.localizedDescription)")
        } else {
            print("[FTMS] Notifications \(characteristic.isNotifying ? "enabled" : "disabled") for \(characteristic.uuid)")
        }
        #endif
    }

    // MARK: - Private

    private func cleanUpConnection() {
        connectedPeripheral = nil
        controlPointCharacteristic = nil
        hasControlPoint = false
        controlAcquired = false
        supportsERG = false
        metrics = .empty
        if connectionState != .bluetoothOff && connectionState != .bluetoothUnauthorized {
            connectionState = .disconnected
        }
    }
}
