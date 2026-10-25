import Cocoa
import os

/// The Halloween bezel: bats for brightness, ghostly wisps and a rising ghost
/// for volume, and a spider spinning a web on mute, all drawn in the look
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

    private let pumpkin: PumpkinGlyph?
    private let bats: BatColony?
    /// The last brightness shown; `nil` until the first one, which is shown
    /// without animating.
    private var brightness: Float?

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
        switch reading {
        case .brightness(let level):
            // The first brightness this scene shows, and a reading that isn't a
            // change (e.g. on a screen the bezel wasn't on), go straight there.
            let animated = brightness != nil && transition != .none
                && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            brightness = level
            hudView.glyphOverride = pumpkin?.view
            pumpkin?.show(level: level, animated: animated)
            batStage.isHidden = false
            bats?.show(brightness: level, animated: animated, burst: animated && transition == .brightnessUp)

        case .volume, .caption:
            hudView.glyphOverride = nil
            batStage.isHidden = true
        }
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
