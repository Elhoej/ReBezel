import Cocoa
import Lottie
import os

/// The Halloween animations and artwork, loaded once and shared by every panel's scene.
/// A missing or unreadable file is `nil`, and the scene leaves that part out.
@MainActor
enum HalloweenAssets {
    private static let logger = Logger(subsystem: "com.simonelhoej.ReBezel", category: "Halloween")

    /// A friendly grin at progress 0 that turns into a scary one by 1, with a
    /// red flash on the way.
    static let pumpkin = load("pumpkin")
    /// One bat flapping in place (0.33 s loop) with orange eyes. The body is
    /// tinted at runtime.
    static let batFlying = load("bat-flying")
    /// A spider dropping in on its rope (frames 0–37), then swinging.
    static let spider = load("spider")
    /// Graves, a fence and a raven in silhouette, along the bottom of the
    /// bezel, as a black template image; see `graveyard(in:)`.
    static let graveyard = NSImage(named: "HalloweenGraveyard")

    private static func load(_ name: String) -> LottieAnimation? {
        guard let animation = LottieAnimation.named(name) else {
            logger.error("Couldn't load Halloween animation \(name, privacy: .public)")
            return nil
        }
        return animation
    }

    /// The graveyard filled with `color`, e.g. the look's ink.
    static func graveyard(in color: NSColor) -> NSImage? {
        guard let template = graveyard else {
            logger.error("Couldn't load Halloween image HalloweenGraveyard")
            return nil
        }
        return NSImage(size: template.size, flipped: false) { rect in
            template.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}
