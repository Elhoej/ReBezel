import Cocoa

/// A non-activating panel that always reports the "key" appearance.
///
/// NSGlassEffectView draws its specular rim through a "key fill highlight"
/// layer whose opacity follows the window's key appearance. A HUD never
/// becomes key, so without this override the glass renders as a flat slab.
/// Overriding these two private accessors makes the glass render exactly as
/// it does in a key window while the panel still never takes focus.
final class HUDPanel: NSPanel {
    @objc(hasKeyAppearance)
    var hasKeyAppearance: Bool { true }

    @objc(_hasActiveControls)
    var hasActiveControls: Bool { true }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
