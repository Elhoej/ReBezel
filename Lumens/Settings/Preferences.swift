import Foundation

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
