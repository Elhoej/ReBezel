import CoreGraphics

/// What the bezel shows, as levels rather than symbols. Callers report where a
/// level is now; `HUDTransitionTracker` works out what changed.
enum HUDReading: Equatable, Sendable {
    /// Output volume, 0...1, and whether the output is muted.
    case volume(level: Float, muted: Bool)
    /// Display brightness, 0...1.
    case brightness(level: Float)
    /// A symbol with a line of text where the level bar would be, e.g. a
    /// checkmark and "Voilá!" once onboarding is complete.
    case caption(symbol: String, text: String)

    /// Muted, or turned all the way down. The bezel shows both the same way:
    /// a slashed speaker over an empty bar.
    var isSilent: Bool {
        guard case .volume(let level, let muted) = self else { return false }
        return muted || level <= 0
    }
}

/// What changed from the previous reading of the same kind.
enum HUDTransition: Equatable, Sendable {
    /// The first reading of its kind, the same level again, or a caption.
    case none
    case volumeUp
    case volumeDown
    /// Went silent: muted, or turned down to 0.
    case mute
    /// Came back from silent, also when that happened by turning the volume up.
    case unmute
    case brightnessUp
    case brightnessDown
}

/// Remembers the last volume and brightness shown and turns each new reading
/// into a transition.
///
/// Working from the levels rather than from the keys means a change that is
/// reported twice only counts once. The Touch Bar observer reports ReBezel's
/// own key changes back, and that second reading comes out as `.none`.
struct HUDTransitionTracker: Sendable {
    /// Differences smaller than this are the same level read back slightly
    /// off, not a step. The smallest real step is 1/64.
    static let tolerance: Float = 0.001

    private var volume: (level: Float, silent: Bool)?
    /// Keyed by display; `nil` is the built-in (primary) display.
    private var brightness: [CGDirectDisplayID?: Float] = [:]

    /// Records `reading` and returns how it differs from the previous one of
    /// its kind. `display` is the display whose brightness the reading is for.
    /// `press` is the change a key asked for: a press at the end of the range
    /// (brightness up at 100%) leaves the level where it was, but still counts
    /// as that change rather than as `.none`.
    mutating func record(_ reading: HUDReading, display: CGDirectDisplayID? = nil, press: HUDTransition? = nil) -> HUDTransition {
        switch reading {
        case .volume(let level, _):
            let silent = reading.isSilent
            defer { volume = (level, silent) }
            guard let previous = volume else { return .none }
            if silent != previous.silent { return silent ? .mute : .unmute }
            if silent { return .none }
            return Self.direction(from: previous.level, to: level, up: .volumeUp, down: .volumeDown)

        case .brightness(let level):
            defer { brightness[display] = level }
            guard let previous = brightness[display] else { return .none }
            let transition = Self.direction(from: previous, to: level, up: .brightnessUp, down: .brightnessDown)
            if transition == .none, let press, press == .brightnessUp || press == .brightnessDown {
                return press
            }
            return transition

        case .caption:
            return .none
        }
    }

    private static func direction(from old: Float, to new: Float, up: HUDTransition, down: HUDTransition) -> HUDTransition {
        let delta = new - old
        if abs(delta) < tolerance { return .none }
        return delta > 0 ? up : down
    }
}
