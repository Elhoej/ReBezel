import Cocoa
import os

/// The Halloween bezel: a jack-o'-lantern and bats for brightness, ghostly
/// wisps and a rising ghost for volume, and a spider spinning a web on mute.
/// See docs/HALLOWEEN.md.
///
/// Each part has its own stage view around the bezel, back to front:
/// the ghost (clipped to the area above the bezel, so it rises from behind it
/// and never sits under the glass), the bezel itself, the roost below it, the
/// spider and web over the glyph, and the swarm over the whole panel.
@MainActor
final class HalloweenScene: SeasonalScene {
    private static let logger = Logger(subsystem: "com.simonelhoej.ReBezel", category: "Halloween")

    /// Height of the area below the bezel where bats hang.
    private static let roostHeight: CGFloat = 64

    private let ghostStage = HalloweenScene.makeStage()
    private let roostStage = HalloweenScene.makeStage()
    private let spiderStage = HalloweenScene.makeStage()
    private let swarmStage = HalloweenScene.makeStage()

    init(host: SeasonalSceneHost) {
        let container = host.container
        let bezel = host.bezelFrame

        ghostStage.frame = NSRect(x: bezel.minX, y: bezel.maxY, width: bezel.width, height: container.bounds.maxY - bezel.maxY)
        ghostStage.layer?.masksToBounds = true
        container.addSubview(ghostStage, positioned: .below, relativeTo: nil)

        roostStage.frame = NSRect(x: bezel.minX, y: bezel.minY - Self.roostHeight, width: bezel.width, height: Self.roostHeight)
        container.addSubview(roostStage)

        spiderStage.frame = NSRect(x: bezel.minX, y: bezel.minY, width: bezel.width, height: container.bounds.maxY - bezel.minY)
        container.addSubview(spiderStage)

        swarmStage.frame = container.bounds
        container.addSubview(swarmStage)

        if HalloweenAssets.batFlying == nil || HalloweenAssets.spider == nil {
            Self.logger.error("Halloween scene is missing animations")
        }
    }

    func apply(_ reading: HUDReading, transition: HUDTransition) {
        Self.logger.debug("Halloween \(String(describing: reading), privacy: .public) \(String(describing: transition), privacy: .public)")
    }

    func pause() {}

    private static func makeStage() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        return view
    }
}
