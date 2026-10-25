import Cocoa

/// A status menu submenu that shows the bezel for made-up levels, to try the
/// seasonal animations without changing the real volume or brightness.
/// Added when ReBezel is launched with `--debug-bezel` (combine it with
/// `--season halloween` outside the season).
@MainActor
final class BezelDebugMenu: NSObject {
    static let launchArgument = "--debug-bezel"

    /// Shows a reading, with the change a key would have asked for.
    private let showReading: (HUDReading, HUDTransition?) -> Void
    private var volume: Float = 0.5
    private var muted = false
    private var brightness: Float = 0.5
    private let step: Float = 1.0 / 16.0
    private let batSizeLabel = NSTextField(labelWithString: "")

    init(show: @escaping (HUDReading, HUDTransition?) -> Void) {
        showReading = show
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
        menu.addItem(.separator())
        menu.addItem(makeBatSizeItem())

        let item = NSMenuItem(title: "Debug Bezel", action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    /// A slider for the Halloween bats' size, from half to two and a half
    /// times. Moving it shows the bezel at the current brightness, so the
    /// hanging bats are redrawn at the new size.
    private func makeBatSizeItem() -> NSMenuItem {
        let slider = NSSlider(value: BatColony.sizeMultiplier, minValue: 0.5, maxValue: 2.5,
                              target: self, action: #selector(batSizeChanged(_:)))
        slider.frame = NSRect(x: 18, y: 4, width: 204, height: 22)
        batSizeLabel.font = .menuFont(ofSize: 0)
        batSizeLabel.frame = NSRect(x: 20, y: 28, width: 200, height: 18)
        updateBatSizeLabel()

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 50))
        view.addSubview(batSizeLabel)
        view.addSubview(slider)
        let item = NSMenuItem()
        item.view = view
        return item
    }

    private func updateBatSizeLabel() {
        batSizeLabel.stringValue = String(format: "Bat Size: %.2f×", BatColony.sizeMultiplier)
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
        show(.brightness(level: brightness), press: .brightnessUp)
    }

    @objc private func brightnessDown() {
        brightness = max(brightness - step, 0)
        show(.brightness(level: brightness), press: .brightnessDown)
    }

    @objc private func brightnessZero() {
        brightness = 0
        show(.brightness(level: brightness))
    }

    @objc private func brightnessFull() {
        brightness = 1
        show(.brightness(level: brightness))
    }

    @objc private func batSizeChanged(_ slider: NSSlider) {
        BatColony.sizeMultiplier = slider.doubleValue
        updateBatSizeLabel()
        show(.brightness(level: brightness))
    }

    private func show(_ reading: HUDReading, press: HUDTransition? = nil) {
        showReading(reading, press)
    }

    private func showVolume() {
        show(.volume(level: volume, muted: muted))
    }
}
