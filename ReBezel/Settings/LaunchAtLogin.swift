import Foundation
import ServiceManagement
import os

/// Registers the app as a login item via SMAppService. Enabled by default on
/// first launch; afterwards the user's choice in Settings (or in System
/// Settings → Login Items) is respected.
@MainActor
enum LaunchAtLogin {
    private static let logger = Logger(subsystem: "com.simonelhoej.ReBezel", category: "LaunchAtLogin")
    private static let didApplyDefaultKey = "didApplyDefaultLaunchAtLogin"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func applyDefaultIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didApplyDefaultKey) else { return }
        defaults.set(true, forKey: didApplyDefaultKey)
        setEnabled(true)
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            logger.info("Launch at login \(enabled ? "enabled" : "disabled")")
        } catch {
            logger.error("Failed to \(enabled ? "register" : "unregister") login item: \(error.localizedDescription)")
        }
    }
}
