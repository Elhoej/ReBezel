import Foundation
import Testing
@testable import ReBezel

struct SeasonalThemeTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Copenhagen")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test(arguments: [(10, 28), (10, 31), (11, 1), (11, 3)])
    func halloweenIsInSeason(month: Int, day: Int) {
        #expect(SeasonalTheme.inSeason(on: date(2026, month, day), calendar: calendar) == .halloween)
    }

    @Test(arguments: [(10, 27), (11, 4), (6, 15), (12, 31)])
    func halloweenIsOutOfSeason(month: Int, day: Int) {
        #expect(SeasonalTheme.inSeason(on: date(2026, month, day), calendar: calendar) == nil)
    }

    @Test func seasonCoversWholeDays() {
        #expect(SeasonalTheme.halloween.isInSeason(on: date(2026, 10, 28, hour: 0), calendar: calendar))
        #expect(SeasonalTheme.halloween.isInSeason(on: date(2026, 11, 3, hour: 23), calendar: calendar))
        #expect(!SeasonalTheme.halloween.isInSeason(on: date(2026, 10, 27, hour: 23), calendar: calendar))
    }

    @Test func seasonComesBackEveryYear() {
        #expect(SeasonalTheme.halloween.isInSeason(on: date(2027, 10, 30), calendar: calendar))
    }
}
