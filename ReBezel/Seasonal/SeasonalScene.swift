import Cocoa

/// Where a scene puts its views: the panel's content view, the bezel's frame
/// inside it, and the bezel's own content for replacing the glyph.
struct SeasonalSceneHost {
    let container: NSView
    let bezelFrame: NSRect
    let hudView: HUDView
}

/// Seasonal decorations for one bezel panel, animated as the levels change.
@MainActor
protocol SeasonalScene: AnyObject {
    /// Brings the scene to `reading`. `transition` is what changed since the
    /// previous reading of the same kind; with `.none` the scene goes straight
    /// to the new state without animating.
    func apply(_ reading: HUDReading, transition: HUDTransition)

    /// Called once the bezel has faded out. Stops anything still running, so
    /// nothing animates while the panel is invisible.
    func pause()
}

extension SeasonalTheme {
    /// A new scene for one panel, installed into `host`.
    @MainActor
    func makeScene(in host: SeasonalSceneHost) -> SeasonalScene {
        switch self {
        case .halloween: HalloweenScene(host: host)
        }
    }
}
