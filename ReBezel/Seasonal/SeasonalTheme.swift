import Foundation

/// A themed bezel for a few days of the year.
enum SeasonalTheme: String, CaseIterable, Sendable {
    case halloween

    /// Forces a theme regardless of the date and the preference, for testing:
    /// `--season halloween`, or `--season none` to turn themes off.
    static let launchArgument = "--season"

    /// The theme to show now: the one forced by the launch argument, otherwise
    /// the one in season unless seasonal bezels are turned off.
    @MainActor
    static var current: SeasonalTheme? {
        if let forced = forcedByLaunchArgument { return forced }
        guard Preferences.showSeasonalThemes else { return nil }
        return inSeason(on: .now)
    }

    /// The theme in season on `date`, if any.
    static func inSeason(on date: Date, calendar: Calendar = .current) -> SeasonalTheme? {
        allCases.first { $0.isInSeason(on: date, calendar: calendar) }
    }

    /// Halloween runs from three days before October 31 to three days after,
    /// in the user's own calendar.
    func isInSeason(on date: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .halloween:
            let year = calendar.component(.year, from: date)
            guard let halloween = calendar.date(from: DateComponents(year: year, month: 10, day: 31)),
                  let days = calendar.dateComponents([.day], from: halloween, to: calendar.startOfDay(for: date)).day
            else { return false }
            return abs(days) <= 3
        }
    }

    /// `.some(nil)` when the argument turns themes off, `nil` when it is absent.
    private static var forcedByLaunchArgument: SeasonalTheme?? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: launchArgument), index + 1 < arguments.count else {
            return nil
        }
        return .some(SeasonalTheme(rawValue: arguments[index + 1]))
    }
}
