import Testing
@testable import ReBezel

struct BatColonyTests {
    @Test(arguments: [
        (Float(1), 0),
        (0.9375, 1),
        (0.9, 1),
        (0.5, 5),
        (0.4375, 6),
        (0.0625, 10),
        (0, 10),
    ])
    func roostCountGrowsAsTheScreenDarkens(brightness: Float, bats: Int) {
        #expect(BatColony.roostCount(for: brightness) == bats)
    }

    @Test func roostCountClampsOutOfRangeLevels() {
        #expect(BatColony.roostCount(for: 1.2) == 0)
        #expect(BatColony.roostCount(for: -0.1) == BatColony.roostSize)
    }
}
