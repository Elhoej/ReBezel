import Cocoa
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: "com.simonelhoej.Lumens", category: "App")

    private var statusItem: NSStatusItem?
    private var mediaKeyTap: MediaKeyTap?
    private let hud = HUDWindowController()
    private let brightness = BrightnessController()

    private let normalStep: Float = 1.0 / 16.0
    private let fineStep: Float = 1.0 / 64.0

    /// Pass this launch argument to reveal a hidden menu bar icon, for when
    /// relaunching from Finder is not practical (e.g. running from Xcode):
    /// `open -a Lumens --args --show-menu-bar-icon`
    static let showMenuBarIconArgument = "--show-menu-bar-icon"

    func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchAtLogin.applyDefaultIfNeeded()
        if CommandLine.arguments.contains(Self.showMenuBarIconArgument) {
            Preferences.hideMenuBarIcon = false
        }
        setUpStatusItem()
        startTapIfTrusted()
        applyMenuBarIconVisibility()
    }

    /// Launching Lumens while it is already running lands here. Use it as the
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
        print("running")
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "Lumens")

        let menu = NSMenu()
        menu.addItem(withTitle: "Lumens", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let positionItem = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        positionItem.submenu = makePositionMenu()
        menu.addItem(positionItem)
        let styleItem = NSMenuItem(title: "Style", action: nil, keyEquivalent: "")
        styleItem.submenu = makeStyleMenu()
        menu.addItem(styleItem)
        let allScreensItem = NSMenuItem(title: "Show on All Screens", action: #selector(toggleAllScreens(_:)), keyEquivalent: "")
        allScreensItem.state = Preferences.showOnAllScreens ? .on : .off
        menu.addItem(allScreensItem)
        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        loginItem.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(withTitle: "Hide Menu Bar Icon…", action: #selector(hideMenuBarIcon), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Accessibility Settings…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        menu.addItem(withTitle: "Retry Event Tap", action: #selector(retryTap), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Lumens", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    private func makePositionMenu() -> NSMenu {
        let menu = NSMenu()
        for position in HUDPosition.allCases {
            let item = NSMenuItem(title: position.title, action: #selector(selectPosition(_:)), keyEquivalent: "")
            item.representedObject = position.rawValue
            item.state = position == Preferences.hudPosition ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    @objc private func selectPosition(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let position = HUDPosition(rawValue: raw) else { return }
        Preferences.hudPosition = position
        for item in sender.menu?.items ?? [] {
            item.state = item == sender ? .on : .off
        }
        // Preview the new spot right away.
        hud.show(symbol: "sun.max", level: 0.5)
    }

    private func makeStyleMenu() -> NSMenu {
        let menu = NSMenu()
        for style in HUDStyle.allCases {
            let item = NSMenuItem(title: style.title, action: #selector(selectStyle(_:)), keyEquivalent: "")
            item.representedObject = style.rawValue
            item.state = style == Preferences.hudStyle ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    @objc private func selectStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = HUDStyle(rawValue: raw) else { return }
        Preferences.hudStyle = style
        for item in sender.menu?.items ?? [] {
            item.state = item == sender ? .on : .off
        }
        hud.show(symbol: "sun.max", level: 0.5)
    }

    @objc private func toggleAllScreens(_ sender: NSMenuItem) {
        Preferences.showOnAllScreens.toggle()
        sender.state = Preferences.showOnAllScreens ? .on : .off
        hud.show(symbol: "sun.max", level: 0.5)
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        LaunchAtLogin.setEnabled(!LaunchAtLogin.isEnabled)
        sender.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    @objc private func hideMenuBarIcon() {
        let alert = NSAlert()
        alert.messageText = "Hide the menu bar icon?"
        alert.informativeText = "Lumens keeps running in the background. To show the icon again (or to quit), open Lumens from Finder, Spotlight or Launchpad while it is running."
        alert.addButton(withTitle: "Hide Icon")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Preferences.hideMenuBarIcon = true
        applyMenuBarIconVisibility()
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

    @objc private func retryTap() {
        startTapIfTrusted()
    }

    // MARK: - Event tap

    private func startTapIfTrusted() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            Self.logger.warning("Not trusted for Accessibility yet; waiting for permission")
            statusItem?.button?.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Lumens needs Accessibility")
            applyMenuBarIconVisibility()
            return
        }

        if mediaKeyTap == nil {
            mediaKeyTap = MediaKeyTap { [weak self] event in
                self?.handle(event) ?? false
            }
        }
        if mediaKeyTap?.start() == true {
            statusItem?.button?.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "Lumens")
        }
        applyMenuBarIconVisibility()
    }

    /// Returns true to swallow the key so the native banner never appears.
    private func handle(_ event: MediaKeyEvent) -> Bool {
        switch event.key {
        case .soundUp, .soundDown, .mute:
            if event.isDown { handleVolume(event) }
            return true

        case .brightnessUp, .brightnessDown:
            guard brightness.isAvailable else { return false }
            if event.isDown { handleBrightness(event) }
            return true

        case .illuminationUp, .illuminationDown:
            // Keyboard backlight is not handled yet; let the system do it.
            return false
        }
    }

    private func step(for event: MediaKeyEvent) -> Float {
        event.modifiers.isSuperset(of: [.option, .shift]) ? fineStep : normalStep
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

        Self.logger.info("Volume \(event.key.rawValue): \(value) muted=\(muted)")
        // The classic bezel always shows the same speaker glyph.
        hud.show(symbol: "speaker.wave.3", level: muted ? 0 : value)
    }

    private func handleBrightness(_ event: MediaKeyEvent) {
        guard let current = brightness.brightness() else { return }
        let delta = event.key == .brightnessUp ? step(for: event) : -step(for: event)
        let value = snap(current + delta, step: step(for: event))
        brightness.setBrightness(value)
        Self.logger.info("Brightness \(event.key.rawValue): \(value)")
        hud.show(symbol: "sun.max", level: value)
    }

    /// Clamp to 0...1 and align to the step grid so repeated presses land on clean values.
    private func snap(_ value: Float, step: Float) -> Float {
        let clamped = min(max(value, 0), 1)
        return (clamped / step).rounded() * step
    }
}
