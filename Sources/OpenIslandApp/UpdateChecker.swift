import Foundation

/// Update checks are intentionally disabled for this Codex-focused fork.
///
/// The upstream appcast points at the generic Open Island release channel. A
/// Sparkle update from that channel would replace the locally customized Codex
/// quota, notch layout, session identity, and keep-awake changes in this fork.
@MainActor
@Observable
final class UpdateChecker: NSObject {
    let updatesDisabled = true
    private(set) var canCheckForUpdates = false
    private(set) var hasUpdate = false
    private(set) var latestVersion: String?

    override init() {
        super.init()
    }

    /// Keep the old call site harmless while preventing all automatic checks.
    func startIfNeeded() {
        canCheckForUpdates = false
        hasUpdate = false
        latestVersion = nil
    }

    /// Manual checks are disabled for the same reason as automatic checks.
    func checkForUpdates() {
        startIfNeeded()
    }
}
