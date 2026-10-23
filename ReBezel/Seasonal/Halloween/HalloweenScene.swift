import Cocoa
import os

/// The Halloween bezel: a jack-o'-lantern and bats for brightness, ghostly
/// wisps and a rising ghost for volume, and a spider spinning a web on mute.
/// See docs/HALLOWEEN.md.
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

        pumpkin = HalloweenAssets.pumpkin.map(PumpkinGlyph.init)
        if let animation = HalloweenAssets.batFlying, let layer = batStage.layer {
            bats = BatColony(stage: layer, bezel: bezel, animation: animation)
        } else {
            bats = nil
        }
        if pumpkin == nil || bats == nil {
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
