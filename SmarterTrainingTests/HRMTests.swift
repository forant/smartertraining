import Foundation
import Testing
@testable import SmarterTraining

// MARK: - HR Measurement Parsing

struct HRMParsingTests {

    @Test func parsesUInt8HeartRate() {
        // Flags: 0x00 (8-bit HR), HR value: 72
        let data = Data([0x00, 72])
        #expect(HRMManager.parseBPM(from: data) == 72)
    }

    @Test func parsesUInt16HeartRate() {
        // Flags: 0x01 (16-bit HR), HR value: 300 (0x012C)
        let data = Data([0x01, 0x2C, 0x01])
        #expect(HRMManager.parseBPM(from: data) == 300)
    }

    @Test func parsesUInt16NormalRange() {
        // Flags: 0x01 (16-bit HR), HR value: 150
        let low = UInt8(150 & 0xFF)
        let high = UInt8(150 >> 8)
        let data = Data([0x01, low, high])
        #expect(HRMManager.parseBPM(from: data) == 150)
    }

    @Test func parsesWithContactStatusBits() {
        // Flags: 0x06 (sensor contact detected + supported, 8-bit HR)
        let data = Data([0x06, 85])
        #expect(HRMManager.parseBPM(from: data) == 85)
    }

    @Test func parsesWithEnergyExpendedFlag() {
        // Flags: 0x08 (energy expended present, 8-bit HR)
        // HR: 90, followed by energy expended data
        let data = Data([0x08, 90, 0x00, 0x00])
        #expect(HRMManager.parseBPM(from: data) == 90)
    }

    @Test func parsesWithRRIntervalFlag() {
        // Flags: 0x10 (RR interval present, 8-bit HR)
        // HR: 65, followed by RR interval data
        let data = Data([0x10, 65, 0x00, 0x00])
        #expect(HRMManager.parseBPM(from: data) == 65)
    }

    @Test func parsesZeroHeartRate() {
        let data = Data([0x00, 0])
        #expect(HRMManager.parseBPM(from: data) == 0)
    }

    @Test func returnsNilForEmptyData() {
        let data = Data()
        #expect(HRMManager.parseBPM(from: data) == nil)
    }

    @Test func returnsNilForSingleByte() {
        let data = Data([0x00])
        #expect(HRMManager.parseBPM(from: data) == nil)
    }

    @Test func returnsNilForTruncated16Bit() {
        // Flags say 16-bit but only 2 bytes total
        let data = Data([0x01, 72])
        #expect(HRMManager.parseBPM(from: data) == nil)
    }

    @Test func parsesMaxUInt8HeartRate() {
        let data = Data([0x00, 255])
        #expect(HRMManager.parseBPM(from: data) == 255)
    }

    @Test func parsesMaxUInt16HeartRate() {
        let data = Data([0x01, 0xFF, 0xFF])
        #expect(HRMManager.parseBPM(from: data) == 65535)
    }
}

// MARK: - Heart Rate Source Priority

struct HeartRateResolverTests {

    @Test func trainerHRTakesPriority() {
        let result = HeartRateResolver.resolve(trainerHR: 120, hrmHR: 115, healthKitHR: 110)
        #expect(result.bpm == 120)
        #expect(result.source == .trainer)
    }

    @Test func hrmOverridesHealthKit() {
        let result = HeartRateResolver.resolve(trainerHR: nil, hrmHR: 130, healthKitHR: 125)
        #expect(result.bpm == 130)
        #expect(result.source == .hrm)
    }

    @Test func healthKitUsedAsFallback() {
        let result = HeartRateResolver.resolve(trainerHR: nil, hrmHR: nil, healthKitHR: 95)
        #expect(result.bpm == 95)
        #expect(result.source == .healthKit)
    }

    @Test func unavailableWhenAllNil() {
        let result = HeartRateResolver.resolve(trainerHR: nil, hrmHR: nil, healthKitHR: nil)
        #expect(result.bpm == nil)
        #expect(result.source == .none)
    }

    @Test func zeroTrainerHRFallsToHRM() {
        let result = HeartRateResolver.resolve(trainerHR: 0, hrmHR: 140, healthKitHR: nil)
        #expect(result.bpm == 140)
        #expect(result.source == .hrm)
    }

    @Test func zeroHRMFallsToHealthKit() {
        let result = HeartRateResolver.resolve(trainerHR: nil, hrmHR: 0, healthKitHR: 90)
        #expect(result.bpm == 90)
        #expect(result.source == .healthKit)
    }

    @Test func allZeroIsUnavailable() {
        let result = HeartRateResolver.resolve(trainerHR: 0, hrmHR: 0, healthKitHR: 0)
        #expect(result.bpm == nil)
        #expect(result.source == .none)
    }

    @Test func trainerHROverridesEvenIfLower() {
        let result = HeartRateResolver.resolve(trainerHR: 60, hrmHR: 150, healthKitHR: 145)
        #expect(result.bpm == 60)
        #expect(result.source == .trainer)
    }

    @Test func negativeValuesSkipped() {
        let result = HeartRateResolver.resolve(trainerHR: -1, hrmHR: -1, healthKitHR: 80)
        #expect(result.bpm == 80)
        #expect(result.source == .healthKit)
    }
}

// MARK: - Remembered Device Persistence

struct RememberedDeviceStoreTests {

    private func makeStore() -> RememberedDeviceStore {
        let suiteName = "com.smartertraining.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return RememberedDeviceStore(defaults: defaults)
    }

    @Test func startsEmpty() {
        let store = makeStore()
        #expect(store.trainer == nil)
        #expect(store.hrm == nil)
    }

    @Test func savesAndLoadsTrainer() {
        let store = makeStore()
        let device = RememberedDevice(
            peripheralIdentifier: UUID(),
            displayName: "KICKR CORE 1234",
            lastConnectedAt: Date()
        )
        store.trainer = device
        #expect(store.trainer?.peripheralIdentifier == device.peripheralIdentifier)
        #expect(store.trainer?.displayName == "KICKR CORE 1234")
    }

    @Test func savesAndLoadsHRM() {
        let store = makeStore()
        let device = RememberedDevice(
            peripheralIdentifier: UUID(),
            displayName: "Polar H10",
            lastConnectedAt: Date()
        )
        store.hrm = device
        #expect(store.hrm?.peripheralIdentifier == device.peripheralIdentifier)
        #expect(store.hrm?.displayName == "Polar H10")
    }

    @Test func forgetTrainerClearsTrainer() {
        let store = makeStore()
        store.trainer = RememberedDevice(
            peripheralIdentifier: UUID(),
            displayName: "Test",
            lastConnectedAt: Date()
        )
        #expect(store.trainer != nil)
        store.forgetTrainer()
        #expect(store.trainer == nil)
    }

    @Test func forgetHRMClearsHRM() {
        let store = makeStore()
        store.hrm = RememberedDevice(
            peripheralIdentifier: UUID(),
            displayName: "Test",
            lastConnectedAt: Date()
        )
        #expect(store.hrm != nil)
        store.forgetHRM()
        #expect(store.hrm == nil)
    }

    @Test func forgetAllClearsBoth() {
        let store = makeStore()
        store.trainer = RememberedDevice(
            peripheralIdentifier: UUID(),
            displayName: "Trainer",
            lastConnectedAt: Date()
        )
        store.hrm = RememberedDevice(
            peripheralIdentifier: UUID(),
            displayName: "HRM",
            lastConnectedAt: Date()
        )
        store.forgetAll()
        #expect(store.trainer == nil)
        #expect(store.hrm == nil)
    }

    @Test func trainerAndHRMIndependent() {
        let store = makeStore()
        let trainer = RememberedDevice(
            peripheralIdentifier: UUID(),
            displayName: "Kickr",
            lastConnectedAt: Date()
        )
        let hrm = RememberedDevice(
            peripheralIdentifier: UUID(),
            displayName: "Polar",
            lastConnectedAt: Date()
        )
        store.trainer = trainer
        store.hrm = hrm
        #expect(store.trainer?.displayName == "Kickr")
        #expect(store.hrm?.displayName == "Polar")

        store.forgetTrainer()
        #expect(store.trainer == nil)
        #expect(store.hrm?.displayName == "Polar")
    }

    @Test func overwriteDevice() {
        let store = makeStore()
        store.hrm = RememberedDevice(
            peripheralIdentifier: UUID(),
            displayName: "Old",
            lastConnectedAt: Date()
        )
        let newID = UUID()
        store.hrm = RememberedDevice(
            peripheralIdentifier: newID,
            displayName: "New",
            lastConnectedAt: Date()
        )
        #expect(store.hrm?.displayName == "New")
        #expect(store.hrm?.peripheralIdentifier == newID)
    }

    @Test func setNilClearsDevice() {
        let store = makeStore()
        store.trainer = RememberedDevice(
            peripheralIdentifier: UUID(),
            displayName: "Test",
            lastConnectedAt: Date()
        )
        store.trainer = nil
        #expect(store.trainer == nil)
    }
}

// MARK: - Resolved Heart Rate Equality

struct ResolvedHeartRateTests {

    @Test func unavailableIsEqual() {
        #expect(ResolvedHeartRate.unavailable == ResolvedHeartRate(bpm: nil, source: .none))
    }

    @Test func differentSourcesNotEqual() {
        let a = ResolvedHeartRate(bpm: 120, source: .trainer)
        let b = ResolvedHeartRate(bpm: 120, source: .hrm)
        #expect(a != b)
    }
}
