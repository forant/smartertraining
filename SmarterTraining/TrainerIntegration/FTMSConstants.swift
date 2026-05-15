import CoreBluetooth

enum FTMS {
    static let serviceUUID = CBUUID(string: "1826")
    static let indoorBikeDataUUID = CBUUID(string: "2AD2")
    static let fitnessMachineFeatureUUID = CBUUID(string: "2ACC")
    static let fitnessMachineControlPointUUID = CBUUID(string: "2AD9")
    static let fitnessMachineStatusUUID = CBUUID(string: "2ADA")

    enum ControlPointOpCode: UInt8 {
        case requestControl = 0x00
        case reset = 0x01
        case setTargetPower = 0x05
        case startOrResume = 0x07
        case stopOrPause = 0x08
        case responseCode = 0x80
    }

    enum ControlPointResult: UInt8 {
        case success = 0x01
        case opCodeNotSupported = 0x02
        case invalidParameter = 0x03
        case operationFailed = 0x04
        case controlNotPermitted = 0x05
    }

    // Indoor Bike Data flag bits
    enum BikeDataFlag {
        static let moreData: UInt16              = 1 << 0  // 0 = instantaneous speed present
        static let averageSpeedPresent: UInt16   = 1 << 1
        static let cadencePresent: UInt16        = 1 << 2
        static let averageCadencePresent: UInt16 = 1 << 3
        static let totalDistancePresent: UInt16  = 1 << 4
        static let resistanceLevelPresent: UInt16 = 1 << 5
        static let powerPresent: UInt16          = 1 << 6
        static let averagePowerPresent: UInt16   = 1 << 7
        static let expendedEnergyPresent: UInt16 = 1 << 8
        static let heartRatePresent: UInt16      = 1 << 9
        static let elapsedTimePresent: UInt16    = 1 << 11
        static let remainingTimePresent: UInt16  = 1 << 12
    }

    // Fitness Machine Feature bit 14 in Target Setting Features = power target supported
    static let targetPowerSupportedBit: UInt32 = 1 << 3
}
