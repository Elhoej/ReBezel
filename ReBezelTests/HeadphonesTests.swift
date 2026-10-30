import Testing
@testable import ReBezel

struct HeadphonesTests {
    @Test(arguments: [
        ("Simon's AirPods Pro", "airpods.pro"),
        ("AirPods Pro 3", "airpods.pro"),
        ("Simon's AirPods Max", "airpods.max"),
        ("Simon's AirPods", "airpods"),
        ("airpods 4", "airpods"),
        ("Powerbeats Pro 2", "beats.powerbeats.pro"),
        ("Beats Studio Buds +", "beats.studiobuds"),
        ("Beats Fit Pro", "beats.fitpro"),
        ("Beats Studio Pro", "beats.headphones"),
        ("WH-1000XM5", "headphones"),
        ("Pods", "headphones"),
    ])
    func symbolFollowsName(name: String, symbol: String) {
        #expect(Headphones(name: name).symbolName == symbol)
    }
}
