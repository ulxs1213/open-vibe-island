import Foundation
import IOKit.pwr_mgt
import Observation

@MainActor
@Observable
final class SleepPreventionController {
    struct Preset: Identifiable, Equatable, Sendable {
        let id: String
        let duration: TimeInterval?
    }

    static let presets: [Preset] = [
        Preset(id: "15m", duration: 15 * 60),
        Preset(id: "30m", duration: 30 * 60),
        Preset(id: "1h", duration: 60 * 60),
        Preset(id: "2h", duration: 2 * 60 * 60),
        Preset(id: "4h", duration: 4 * 60 * 60),
        Preset(id: "indefinite", duration: nil),
    ]

    private(set) var isActive = false
    private(set) var activePresetID: String?
    private(set) var activeUntil: Date?
    private(set) var lastError: String?

    @ObservationIgnored private var systemAssertionID: IOPMAssertionID = 0
    @ObservationIgnored private var displayAssertionID: IOPMAssertionID = 0
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    @discardableResult
    func start(_ preset: Preset) -> Bool {
        stop()

        let reason = "Open Island keep awake (\(preset.id))" as CFString
        var newSystemAssertionID: IOPMAssertionID = 0
        let systemResult = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &newSystemAssertionID
        )
        guard systemResult == kIOReturnSuccess else {
            lastError = "System sleep assertion failed: \(formatIOReturn(systemResult))"
            return false
        }

        var newDisplayAssertionID: IOPMAssertionID = 0
        let displayResult = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &newDisplayAssertionID
        )
        guard displayResult == kIOReturnSuccess else {
            IOPMAssertionRelease(newSystemAssertionID)
            lastError = "Display sleep assertion failed: \(formatIOReturn(displayResult))"
            return false
        }

        systemAssertionID = newSystemAssertionID
        displayAssertionID = newDisplayAssertionID
        isActive = true
        activePresetID = preset.id
        activeUntil = preset.duration.map { Date().addingTimeInterval($0) }
        lastError = nil

        if let duration = preset.duration {
            let nanoseconds = UInt64(max(1, duration) * 1_000_000_000)
            expiryTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return }
                self?.expire()
            }
        }

        return true
    }

    func stop() {
        expiryTask?.cancel()
        expiryTask = nil
        releaseAssertions()
        isActive = false
        activePresetID = nil
        activeUntil = nil
    }

    private func expire() {
        stop()
    }

    private func releaseAssertions() {
        if systemAssertionID != 0 {
            IOPMAssertionRelease(systemAssertionID)
            systemAssertionID = 0
        }

        if displayAssertionID != 0 {
            IOPMAssertionRelease(displayAssertionID)
            displayAssertionID = 0
        }
    }

    private func formatIOReturn(_ value: IOReturn) -> String {
        String(format: "0x%08x", UInt32(bitPattern: value))
    }
}
