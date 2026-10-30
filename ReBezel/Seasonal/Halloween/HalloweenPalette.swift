import Cocoa
import Lottie

/// The two looks of the Halloween bezel, picked in Preferences. Both draw the
/// whole scene (bats, graveyard, glyph, level bar) as silhouettes in one ink;
/// they differ in what the silhouettes stand against.
enum HalloweenLook: String, CaseIterable, Sendable {
    /// Near-black silhouettes against a warm glow inside the bezel, like a
    /// low harvest moon. The default, so listed first.
    case harvestMoon
    /// Black silhouettes with a pale rim on the bezel's own background.
    case silhouettes

    var title: String {
        switch self {
        case .harvestMoon: "Harvest Moon"
        case .silhouettes: "Silhouettes"
        }
    }

    var palette: HalloweenPalette {
        switch self {
        case .harvestMoon: .harvestMoon
        case .silhouettes: .silhouettes
        }
    }
}

/// The colours of one Halloween look. Everything in the scene is a flat
/// silhouette in `ink`; only the bats' orange eyes keep their colour.
struct HalloweenPalette {
    /// Bats, graveyard, glyph, filled segments and caption.
    let ink: NSColor
    /// The empty part of the level bar.
    let track: NSColor
    /// A soft rim around the glyph, the bar, the caption and the graveyard,
    /// so the ink still shows on a dark bezel. `nil` draws them plain.
    let rim: NSColor?
    /// The rim each bat catches. It is what shows a bat against a dark
    /// wallpaper once it has left the bezel.
    let batRim: NSColor
    let batRimRadius: CGFloat
    /// A glow drawn inside the bezel, centred on the glyph. `nil` leaves the
    /// bezel's own background as it is.
    let backlight: HUDView.Backlight?

    /// Black silhouettes on the classic or Liquid Glass background, each with
    /// the faint white rim the bats have always had.
    static let silhouettes = HalloweenPalette(
        ink: NSColor(white: 0.04, alpha: 1),
        track: NSColor(white: 1, alpha: 0.28),
        rim: NSColor(white: 1, alpha: 0.7),
        batRim: NSColor(white: 1, alpha: 0.7),
        batRimRadius: 2,
        backlight: nil
    )

    /// One light and one ink, like a poster. The bezel glows warm from behind
    /// the glyph and everything in front of it is a near-black silhouette,
    /// warmed a little so it sits in the amber rather than on top of it. The
    /// glow is slightly translucent so the glass still shows through it.
    static let harvestMoon = HalloweenPalette(
        ink: NSColor(red: 0.09, green: 0.05, blue: 0.04, alpha: 1),
        // A lighter slot the light shows through.
        track: NSColor(white: 1, alpha: 0.30),
        rim: nil,
        // As if lit from behind.
        batRim: NSColor(red: 1.0, green: 0.68, blue: 0.30, alpha: 0.9),
        batRimRadius: 2.5,
        backlight: HUDView.Backlight(
            colors: [
                // The heart of the glow, right behind the glyph.
                NSColor(red: 1.0, green: 0.84, blue: 0.52, alpha: 0.94),
                // Most of the bezel.
                NSColor(red: 1.0, green: 0.64, blue: 0.22, alpha: 0.90),
                // Towards the edges.
                NSColor(red: 0.90, green: 0.40, blue: 0.10, alpha: 0.86),
                // The corners, where the light has nearly gone.
                NSColor(red: 0.42, green: 0.13, blue: 0.05, alpha: 0.84),
            ],
            locations: [0, 0.32, 0.68, 1]
        )
    )

    var inkLottie: LottieColor {
        let c = ink.usingColorSpace(.sRGB) ?? ink
        return LottieColor(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent), a: 1)
    }

    /// Puts the palette on `view`: the backlight, ink for the glyph, the
    /// filled segments and the caption, the track behind them, and the rim.
    @MainActor
    func apply(to view: HUDView) {
        view.backlight = backlight
        view.foreground = ink
        view.trackColor = track
        view.rim = rim
    }
}
