import Cocoa
import Sparkle

/// Owns Sparkle's updater. The feed URL, public key and the default for
/// automatic checks live in Info.plist (see `project.yml`); releases and the
/// appcast are published by `Scripts/release.sh`.
@MainActor
final class AppUpdater: NSObject {
    private var controller: SPUStandardUpdaterController!

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
    }

    /// Sparkle stores this in the app's defaults; it starts out on
    /// (`SUEnableAutomaticChecks`), so users are never asked.
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    /// A "Check for Updates…" item. Sparkle disables it while a check is running.
    func makeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        item.target = controller
        return item
    }
}

extension AppUpdater: SPUUpdaterDelegate {
    /// Debug builds never check on their own, so a build from Xcode doesn't offer
    /// to replace itself with a release. "Check for Updates…" still works.
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        #if DEBUG
        if updateCheck == .updatesInBackground {
            throw NSError(domain: "com.simonelhoej.ReBezel", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Scheduled update checks are disabled in Debug builds.",
            ])
        }
        #endif
    }
}

extension AppUpdater: @preconcurrency SPUStandardUserDriverDelegate {
    /// ReBezel has no Dock icon and its menu bar icon may be hidden, so there is
    /// nowhere to put a gentle reminder. Declaring support only silences Sparkle's
    /// background-app warning; the update alert itself is brought to the front below.
    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        true
    }

    /// For a background app Sparkle shows a scheduled update behind other apps;
    /// activating first puts the alert in front instead.
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if handleShowingUpdate, !state.userInitiated {
            NSApp.activate()
        }
    }
}
