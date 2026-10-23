import Cocoa

/// Where the bezel sits on the active screen.
enum HUDPosition: String, CaseIterable, Sendable {
    case top
    case center
    case bottom

    var title: String {
        switch self {
        case .bottom: "Bottom"
        case .center: "Center"
        case .top: "Top"
        }
    }
}

/// Visual treatment of the bezel background.
enum HUDStyle: String, CaseIterable, Sendable {
    case classic
    case liquidGlassRegular
    case liquidGlassClear

    var title: String {
        switch self {
        case .classic: "Classic"
        case .liquidGlassRegular: "Liquid Glass (Regular)"
        case .liquidGlassClear: "Liquid Glass (Clear)"
        }
    }
}

/// User-facing settings, persisted in UserDefaults.
@MainActor
enum Preferences {
    private static let positionKey = "hudPosition"
    private static let allScreensKey = "showOnAllScreens"
    private static let styleKey = "hudStyle"
    private static let hideMenuBarIconKey = "hideMenuBarIcon"
    private static let didCompleteOnboardingKey = "didCompleteOnboarding"
    private static let showForTouchBarKey = "showForTouchBar"
    private static let showSeasonalThemesKey = "showSeasonalThemes"

    /// The Control Strip draws the Touch Bar's system buttons, so it only
    /// runs on a Mac that has one.
    nonisolated static let controlStripBundleIdentifier = "com.apple.controlstrip"

    static var hudPosition: HUDPosition {
        get {
            UserDefaults.standard.string(forKey: positionKey)
                .flatMap(HUDPosition.init(rawValue:)) ?? .bottom
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: positionKey)
        }
    }

    /// Show the bezel on every connected screen instead of just the active one.
    static var showOnAllScreens: Bool {
        get { UserDefaults.standard.bool(forKey: allScreensKey) }
        set { UserDefaults.standard.set(newValue, forKey: allScreensKey) }
    }

    /// Hide the status item. Relaunching the app shows it again.
    static var hideMenuBarIcon: Bool {
        get { UserDefaults.standard.bool(forKey: hideMenuBarIconKey) }
        set { UserDefaults.standard.set(newValue, forKey: hideMenuBarIconKey) }
    }

    /// Set once the first-run walkthrough has been dismissed, whether or not
    /// every step was completed. Delete the key to see it again:
    /// `defaults delete com.simonelhoej.ReBezel didCompleteOnboarding`.
    static var didCompleteOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: didCompleteOnboardingKey) }
        set { UserDefaults.standard.set(newValue, forKey: didCompleteOnboardingKey) }
    }

    /// Show the bezel for volume and brightness changes made without the keys,
    /// which is how the Touch Bar makes them. Until the user picks a side it
    /// follows whether this Mac has a Touch Bar. That is checked on every read,
    /// since at login ReBezel can start before the Control Strip does.
    static var showForTouchBar: Bool {
        get {
            UserDefaults.standard.object(forKey: showForTouchBarKey) as? Bool
                ?? !NSRunningApplication.runningApplications(withBundleIdentifier: controlStripBundleIdentifier).isEmpty
        }
        set { UserDefaults.standard.set(newValue, forKey: showForTouchBarKey) }
    }

    /// Show a themed bezel in season, such as around Halloween. On until the
    /// user turns it off.
    static var showSeasonalThemes: Bool {
        get { UserDefaults.standard.object(forKey: showSeasonalThemesKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: showSeasonalThemesKey) }
    }

    static var hudStyle: HUDStyle {
        get {
            UserDefaults.standard.string(forKey: styleKey)
                .flatMap(HUDStyle.init(rawValue:)) ?? .classic
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: styleKey)
        }
    }
}
