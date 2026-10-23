import Testing
@testable import ReBezel

@MainActor
struct HalloweenAssetsTests {
    @Test func animationsLoadFromTheAppBundle() throws {
        let bat = try #require(HalloweenAssets.batFlying)
        let spider = try #require(HalloweenAssets.spider)
        let pumpkin = try #require(HalloweenAssets.pumpkin)
        #expect(pumpkin.duration > 0)
        #expect(bat.duration > 0)
        #expect(spider.duration > 0)
    }
}
