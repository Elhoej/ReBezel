import Lottie
import os

/// The Halloween animations, loaded once and shared by every panel's scene.
/// A missing or unreadable file is `nil`, and the scene leaves that part out.
@MainActor
enum HalloweenAssets {
    private static let logger = Logger(subsystem: "com.simonelhoej.ReBezel", category: "Halloween")

    /// One bat flapping in place (0.8 s loop). Black; tint it for dark wallpapers.
    static let batFlying = load("bat-flying")
    /// A spider dropping in on its rope (frames 0–37), then swinging.
    static let spider = load("spider")

    private static func load(_ name: String) -> LottieAnimation? {
        guard let animation = LottieAnimation.named(name) else {
            logger.error("Couldn't load Halloween animation \(name, privacy: .public)")
            return nil
        }
        return animation
    }
}
