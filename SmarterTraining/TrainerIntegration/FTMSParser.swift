import Foundation

enum FTMSParser {

    // FTMS Indoor Bike Data characteristic (0x2AD2).
    // Fields are conditionally present based on a 16-bit flags word.
    // Bit 0 ("More Data") = 0 means instantaneous speed IS present (inverted logic).
    static func parseIndoorBikeData(_ data: Data) -> TrainerMetrics {
        guard data.count >= 2 else { return .empty }

        let flags = readUInt16(data, offset: 0)
        var offset = 2
        var metrics = TrainerMetrics(timestamp: Date())

        // Instantaneous speed: present when bit 0 is 0
        if flags & FTMS.BikeDataFlag.moreData == 0 {
            if offset + 2 <= data.count {
                let raw = readUInt16(data, offset: offset)
                metrics.speed = Double(raw) * 0.01 // km/h
                offset += 2
            }
        }

        // Average speed
        if flags & FTMS.BikeDataFlag.averageSpeedPresent != 0 {
            offset += 2
        }

        // Instantaneous cadence: uint16, resolution 0.5 rpm
        if flags & FTMS.BikeDataFlag.cadencePresent != 0 {
            if offset + 2 <= data.count {
                let raw = readUInt16(data, offset: offset)
                metrics.cadence = Double(raw) * 0.5
                offset += 2
            }
        }

        // Average cadence
        if flags & FTMS.BikeDataFlag.averageCadencePresent != 0 {
            offset += 2
        }

        // Total distance: uint24
        if flags & FTMS.BikeDataFlag.totalDistancePresent != 0 {
            offset += 3
        }

        // Resistance level: sint16
        if flags & FTMS.BikeDataFlag.resistanceLevelPresent != 0 {
            offset += 2
        }

        // Instantaneous power: sint16, watts
        if flags & FTMS.BikeDataFlag.powerPresent != 0 {
            if offset + 2 <= data.count {
                metrics.power = Int(readSInt16(data, offset: offset))
                offset += 2
            }
        }

        // Average power
        if flags & FTMS.BikeDataFlag.averagePowerPresent != 0 {
            offset += 2
        }

        // Expended energy: total (uint16) + per hour (uint16) + per minute (uint8)
        if flags & FTMS.BikeDataFlag.expendedEnergyPresent != 0 {
            offset += 5
        }

        // Heart rate: uint8
        if flags & FTMS.BikeDataFlag.heartRatePresent != 0 {
            if offset + 1 <= data.count {
                metrics.heartRate = Int(data[offset])
                offset += 1
            }
        }

        return metrics
    }

    // Fitness Machine Feature characteristic (0x2ACC): 4 bytes machine features + 4 bytes target setting features.
    static func supportsTargetPower(_ data: Data) -> Bool {
        guard data.count >= 8 else { return false }
        let targetSettingFeatures = readUInt32(data, offset: 4)
        return targetSettingFeatures & FTMS.targetPowerSupportedBit != 0
    }

    // Control point response: [0x80, requestOpCode, resultCode]
    static func parseControlPointResponse(_ data: Data) -> (opCode: UInt8, success: Bool)? {
        guard data.count >= 3, data[0] == FTMS.ControlPointOpCode.responseCode.rawValue else {
            return nil
        }
        return (data[1], data[2] == FTMS.ControlPointResult.success.rawValue)
    }

    // MARK: - Byte helpers (little-endian)

    private static func readUInt16(_ data: Data, offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func readSInt16(_ data: Data, offset: Int) -> Int16 {
        Int16(bitPattern: readUInt16(data, offset: offset))
    }

    private static func readUInt32(_ data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset])
        | UInt32(data[offset + 1]) << 8
        | UInt32(data[offset + 2]) << 16
        | UInt32(data[offset + 3]) << 24
    }
}
