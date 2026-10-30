import Cocoa
import os

/// The Halloween bezel: bats for brightness and volume, drawn in the look
/// picked in Preferences (`HalloweenLook`). See docs/HALLOWEEN.md.
///
/// Each part has its own stage view around the bezel, back to front: the
/// ghost (clipped to the area above the bezel, so it rises from behind it and
/// never sits under the glass), the bezel itself, the spider and web over the
/// glyph, and the bats over the whole panel.
@MainActor
final class HalloweenScene: SeasonalScene {
    private static let logger = Logger(subsystem: "com.simonelhoej.ReBezel", category: "Halloween")

    private let hudView: HUDView
    private let ghostStage = HalloweenScene.makeStage()
    private let spiderStage = HalloweenScene.makeStage()
    private let batStage = HalloweenScene.makeStage()

    /// Whether brightness shows the jack-o'-lantern or keeps the standard sun
    /// glyph, drawn in the look's ink. Off for now: the pumpkin's own
    /// colours don't fit either look.
    private static let showsPumpkin = false

    /// Which level the bats' roost shows.
    private enum Gauge {
        case brightness
        case volume
    }

    private let pumpkin: PumpkinGlyph?
    private let bats: BatColony?
    /// The last brightness shown; `nil` until the first one, which is shown
    /// without animating.
    private var brightness: Float?
    /// What the roost last showed; `nil` until the first reading, or after a
    /// caption hid the bats.
    private var roost: Gauge?

    init(host: SeasonalSceneHost) {
        hudView = host.hudView
        let container = host.container
        let bezel = host.bezelFrame

        ghostStage.frame = NSRect(x: bezel.minX, y: bezel.maxY, width: bezel.width, height: container.bounds.maxY - bezel.maxY)
        ghostStage.layer?.masksToBounds = true
        container.addSubview(ghostStage, positioned: .below, relativeTo: nil)

        spiderStage.frame = NSRect(x: bezel.minX, y: bezel.minY, width: bezel.width, height: container.bounds.maxY - bezel.minY)
        container.addSubview(spiderStage)

        batStage.frame = container.bounds
        container.addSubview(batStage)

        let palette = Preferences.halloweenLook.palette
        palette.apply(to: hudView)
        hudView.backdrop = HalloweenAssets.graveyard(in: palette.ink)

        pumpkin = Self.showsPumpkin ? HalloweenAssets.pumpkin.map(PumpkinGlyph.init) : nil
        if let animation = HalloweenAssets.batFlying, let layer = batStage.layer {
            bats = BatColony(stage: layer, bezel: bezel, animation: animation, palette: palette)
        } else {
            bats = nil
        }
        if (Self.showsPumpkin && pumpkin == nil) || bats == nil {
            Self.logger.error("Halloween scene is missing animations; those parts are left out")
        }
    }

    func apply(_ reading: HUDReading, transition: HUDTransition) {
        // A reading that isn't a change (e.g. on a screen the bezel wasn't on)
        // goes straight there.
        let moves = transition != .none && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        switch reading {
        case .brightness(let level):
            // So does the first brightness this scene shows.
            pumpkin?.show(level: level, animated: moves && brightness != nil)
            brightness = level
            hudView.glyphOverride = pumpkin?.view
            showBats(level: level, for: .brightness, animated: moves, burst: transition == .brightnessUp)

        case .volume(let level, _):
            hudView.glyphOverride = nil
            // Silence hangs every bat, as the darkest screen does.
            showBats(level: reading.isSilent ? 0 : level, for: .volume, animated: moves,
                     burst: transition == .volumeUp)

        case .caption:
            hudView.glyphOverride = nil
            batStage.isHidden = true
            roost = nil
        }
    }

    /// Brings the roost to `level` of `gauge`. Switching between brightness
    /// and volume jumps to the other level rather than flying every bat off
    /// or in for it.
    private func showBats(level: Float, for gauge: Gauge, animated: Bool, burst: Bool) {
        let animated = animated && roost == gauge
        roost = gauge
        batStage.isHidden = false
        bats?.show(level: level, animated: animated, burst: animated && burst)
    }

    func pause() {
        pumpkin?.pause()
        bats?.pause()
    }

    /// A view whose layer tree is the scene's own (layer-hosting), so Core
    /// Animation layers can be added and animated freely. Not flipped:
    /// y goes up, as in the panel.
    private static func makeStage() -> NSView {
        let view = NSView()
        view.layer = CALayer()
        view.wantsLayer = true
        return view
    }
}
