import Cocoa
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: "com.simonelhoej.ReBezel", category: "App")

    private var statusItem: NSStatusItem?
    private var mediaKeyTap: MediaKeyTap?
    private var permissionPollTask: Task<Void, Never>?
    private let hud = HUDWindowController()
    private let brightness = BrightnessController()
    private let updater = AppUpdater()
    private lazy var preferences = makePreferencesWindowController()
    private var onboarding: OnboardingWindowController?

    /// One of the 16 segments on the bezel.
    private let normalStep: Float = 1.0 / 16.0
    /// Holding Shift+Option moves a quarter segment at a time (64 steps), as
    /// the system does.
    private let fineStep: Float = 1.0 / 64.0

    /// Pass this launch argument to reveal a hidden menu bar icon, for when
    /// relaunching from Finder is not practical (e.g. running from Xcode):
    /// `open -a ReBezel --args --show-menu-bar-icon`
    static let showMenuBarIconArgument = "--show-menu-bar-icon"

    func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchAtLogin.applyDefaultIfNeeded()
        if CommandLine.arguments.contains(Self.showMenuBarIconArgument) {
            Preferences.hideMenuBarIcon = false
        }
        setUpStatusItem()
        if Preferences.didCompleteOnboarding {
            startTapIfTrusted()
        } else {
            // The walkthrough asks for the permission at the right moment, so
            // only check quietly here (which also starts the poll).
            startTapIfTrusted(prompt: false)
            showOnboarding()
        }
        applyMenuBarIconVisibility()
    }

    /// Launching ReBezel while it is already running lands here. Use it as the
    /// way back once the menu bar icon has been hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if Preferences.hideMenuBarIcon {
            Preferences.hideMenuBarIcon = false
            applyMenuBarIconVisibility()
        }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        mediaKeyTap?.stop()
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "square.bottomthird.inset.filled", accessibilityDescription: "ReBezel")

        let menu = NSMenu()
        menu.addItem(withTitle: "Preferences…", action: #selector(showPreferences), keyEquivalent: ",")
        menu.addItem(updater.makeMenuItem())
        menu.addItem(withTitle: "Open Accessibility Settings…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ReBezel", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    // MARK: - Preferences

    private func makePreferencesWindowController() -> PreferencesWindowController {
        let controller = PreferencesWindowController(updater: updater)
        controller.onHUDSettingChanged = { [weak self] in
            // Preview the new look/spot right away.
            self?.hud.show(symbol: "sun.max", level: 0.5)
        }
        controller.onHideMenuBarIcon = { [weak self] in
            Preferences.hideMenuBarIcon = true
            self?.applyMenuBarIconVisibility()
        }
        return controller
    }

    @objc private func showPreferences() {
        preferences.show()
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        if onboarding == nil {
            let controller = OnboardingWindowController()
            controller.onPreviewRequested = { [weak self] in
                self?.hud.show(symbol: "speaker.wave.3", level: 0.5)
            }
            controller.onPermissionRequested = { [weak self] in
                self?.requestAccessibility()
            }
            controller.onFinished = { [weak self] in
                self?.celebratePermission()
            }
            controller.onClose = { [weak self] in
                Preferences.didCompleteOnboarding = true
                self?.onboarding = nil
            }
            onboarding = controller
        }
        onboarding?.show()
    }

    /// Shows the system prompt (which also lists ReBezel in the Accessibility
    /// pane) and opens that pane. The poll started at launch picks up the
    /// grant and finishes the walkthrough.
    private func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            startTapIfTrusted(prompt: false)
            celebratePermission()
            return
        }
        openAccessibilitySettings()
    }

    /// Confirms that everything is set up: a checkmark bezel in the chosen
    /// style and position, and the walkthrough (if open) goes away.
    private func celebratePermission() {
        hud.show(symbol: "checkmark", caption: "Voilá!")
        onboarding?.finish()
    }

    /// The icon stays visible while the event tap is not running so the
    /// Accessibility warning can never be hidden away.
    private func applyMenuBarIconVisibility() {
        let tapRunning = mediaKeyTap?.isRunning == true
        statusItem?.isVisible = !Preferences.hideMenuBarIcon || !tapRunning
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Event tap

    /// Starts the tap if Accessibility permission has been granted. The system
    /// prompt is shown only on the first check; while the permission is still
    /// missing, `pollForPermission` keeps checking quietly so the tap starts on
    /// its own as soon as the user grants it.
    private func startTapIfTrusted(prompt: Bool = true) {
        let trusted: Bool
        if prompt {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            trusted = AXIsProcessTrustedWithOptions(options)
        } else {
            trusted = AXIsProcessTrusted()
        }
        guard trusted else {
            Self.logger.warning("Not trusted for Accessibility yet; waiting for permission")
            statusItem?.button?.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "ReBezel needs Accessibility")
            applyMenuBarIconVisibility()
            pollForPermission()
            return
        }

        permissionPollTask?.cancel()
        permissionPollTask = nil

        if mediaKeyTap == nil {
            mediaKeyTap = MediaKeyTap { [weak self] event in
                self?.handle(event) ?? false
            }
        }
        if mediaKeyTap?.start() == true {
            statusItem?.button?.image = NSImage(systemSymbolName: "square.bottomthird.inset.filled", accessibilityDescription: "ReBezel")
        }
        applyMenuBarIconVisibility()
    }

    private func pollForPermission() {
        guard permissionPollTask == nil else { return }
        permissionPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, AXIsProcessTrusted() else { continue }
                Self.logger.info("Accessibility permission granted; starting event tap")
                self?.permissionPollTask = nil
                self?.startTapIfTrusted(prompt: false)
                self?.celebratePermission()
                return
            }
        }
    }

    /// Returns true to swallow the key so the native banner never appears.
    private func handle(_ event: MediaKeyEvent) -> Bool {
        switch event.key {
        case .soundUp, .soundDown, .mute:
            if event.isDown, opensSettings(event) {
                if !event.isRepeat { openSettingsPane("com.apple.Sound-Settings.extension") }
                return true
            }
            if event.isDown { handleVolume(event) }
            return true

        case .brightnessUp, .brightnessDown:
            // Control targets an external display, as the native shortcut does.
            // With no display to change, let the system handle the key.
            let display = event.modifiers.contains(.control)
                ? brightness.externalDisplay()
                : brightness.primaryDisplay()
            guard let display else { return false }
            if event.isDown, opensSettings(event) {
                if !event.isRepeat { openSettingsPane("com.apple.Displays-Settings.extension") }
                return true
            }
            if event.isDown { handleBrightness(event, display: display) }
            return true

        case .illuminationUp, .illuminationDown:
            // Keyboard backlight is not handled yet; let the system do it.
            return false
        }
    }

    /// Shift+Option: quarter-segment steps instead of whole segments.
    private func step(for event: MediaKeyEvent) -> Float {
        event.modifiers.isSuperset(of: [.option, .shift]) ? fineStep : normalStep
    }

    /// Option on its own (without Shift) opens the matching System Settings
    /// pane instead of changing the level, as the system does.
    private func opensSettings(_ event: MediaKeyEvent) -> Bool {
        event.modifiers.contains(.option) && !event.modifiers.contains(.shift)
    }

    private func openSettingsPane(_ identifier: String) {
        guard let url = URL(string: "x-apple.systempreferences:\(identifier)") else { return }
        Self.logger.info("Opening settings pane \(identifier)")
        NSWorkspace.shared.open(url)
    }

    private func handleVolume(_ event: MediaKeyEvent) {
        guard let current = VolumeController.volume() else { return }
        var muted = VolumeController.isMuted()
        var value = current

        switch event.key {
        case .mute:
            muted.toggle()
            VolumeController.setMuted(muted)
        case .soundUp:
            value = snap(current + step(for: event), step: step(for: event))
            if muted {
                muted = false
                VolumeController.setMuted(false)
            }
            VolumeController.setVolume(value)
        case .soundDown:
            value = snap(current - step(for: event), step: step(for: event))
            VolumeController.setVolume(value)
        default:
            break
        }

        Self.logger.info("Volume \(event.key.rawValue): \(value) muted=\(muted) step=\(self.step(for: event)) modifiers=\(event.modifiers.rawValue)")
        // Muted, or turned all the way down: slashed speaker over an empty bar.
        let silent = muted || value <= 0
        hud.show(symbol: silent ? "speaker.slash" : "speaker.wave.3", level: silent ? 0 : value)
    }

    private func handleBrightness(_ event: MediaKeyEvent, display: CGDirectDisplayID) {
        guard let current = brightness.brightness(of: display) else { return }
        let delta = event.key == .brightnessUp ? step(for: event) : -step(for: event)
        let value = snap(current + delta, step: step(for: event))
        brightness.setBrightness(value, of: display)
        Self.logger.info("Brightness \(event.key.rawValue): \(value) display=\(display) step=\(self.step(for: event)) modifiers=\(event.modifiers.rawValue)")
        // Control+Brightness may change a display other than the one under the
        // cursor, so the bezel goes on that display. Plain keys keep showing it
        // on the active screen.
        let bezelDisplay = event.modifiers.contains(.control) ? display : nil
        hud.show(symbol: "sun.max", level: value, on: bezelDisplay)
    }

    /// Clamp to 0...1 and align to the step grid so repeated presses land on clean values.
    private func snap(_ value: Float, step: Float) -> Float {
        let clamped = min(max(value, 0), 1)
        return (clamped / step).rounded() * step
    }
}
