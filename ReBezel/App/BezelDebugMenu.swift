import Cocoa

/// A status menu submenu that shows the bezel for made-up levels, to try the
/// seasonal animations without changing the real volume or brightness.
/// Added when ReBezel is launched with `--debug-bezel` (combine it with
/// `--season halloween` outside the season).
@MainActor
final class BezelDebugMenu: NSObject {
    static let launchArgument = "--debug-bezel"

    private let show: (HUDReading) -> Void
    private var volume: Float = 0.5
    private var muted = false
    private var brightness: Float = 0.5
    private let step: Float = 1.0 / 16.0

    init(show: @escaping (HUDReading) -> Void) {
        self.show = show
    }

    func makeMenuItem() -> NSMenuItem {
        let menu = NSMenu()
        add("Volume Up", #selector(volumeUp), to: menu)
        add("Volume Down", #selector(volumeDown), to: menu)
        add("Mute", #selector(mute), to: menu)
        add("Unmute", #selector(unmute), to: menu)
        add("Volume 100%", #selector(volumeFull), to: menu)
        menu.addItem(.separator())
        add("Brightness Up", #selector(brightnessUp), to: menu)
        add("Brightness Down", #selector(brightnessDown), to: menu)
        add("Brightness 0%", #selector(brightnessZero), to: menu)
        add("Brightness 100%", #selector(brightnessFull), to: menu)

        let item = NSMenuItem(title: "Debug Bezel", action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private func add(_ title: String, _ action: Selector, to menu: NSMenu) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
    }

    @objc private func volumeUp() {
        // Turning the volume up unmutes, as the key does.
        muted = false
        volume = min(volume + step, 1)
        showVolume()
    }

    @objc private func volumeDown() {
        volume = max(volume - step, 0)
        showVolume()
    }

    @objc private func mute() {
        muted = true
        showVolume()
    }

    @objc private func unmute() {
        muted = false
        showVolume()
    }

    @objc private func volumeFull() {
        muted = false
        volume = 1
        showVolume()
    }

    @objc private func brightnessUp() {
        brightness = min(brightness + step, 1)
        show(.brightness(level: brightness))
    }

    @objc private func brightnessDown() {
        brightness = max(brightness - step, 0)
        show(.brightness(level: brightness))
    }

    @objc private func brightnessZero() {
        brightness = 0
        show(.brightness(level: brightness))
    }

    @objc private func brightnessFull() {
        brightness = 1
        show(.brightness(level: brightness))
    }

    private func showVolume() {
        show(.volume(level: volume, muted: muted))
    }
}
