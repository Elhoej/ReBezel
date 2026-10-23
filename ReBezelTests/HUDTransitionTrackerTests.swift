import Testing
@testable import ReBezel

struct HUDTransitionTrackerTests {
    @Test func firstReadingOfEachKindIsNoChange() {
        var tracker = HUDTransitionTracker()
        #expect(tracker.record(.volume(level: 0.5, muted: false)) == .none)
        #expect(tracker.record(.brightness(level: 0.5)) == .none)
    }

    @Test func volumeSteps() {
        var tracker = HUDTransitionTracker()
        _ = tracker.record(.volume(level: 0.5, muted: false))
        #expect(tracker.record(.volume(level: 0.5625, muted: false)) == .volumeUp)
        #expect(tracker.record(.volume(level: 0.5, muted: false)) == .volumeDown)
    }

    @Test func sameLevelAgainIsNoChange() {
        // The Touch Bar observer reports ReBezel's own key changes back.
        var tracker = HUDTransitionTracker()
        _ = tracker.record(.brightness(level: 0.5))
        #expect(tracker.record(.brightness(level: 0.5625)) == .brightnessUp)
        #expect(tracker.record(.brightness(level: 0.5625)) == .none)
    }

    @Test func levelReadBackSlightlyOffIsNoChange() {
        var tracker = HUDTransitionTracker()
        _ = tracker.record(.brightness(level: 0.5))
        #expect(tracker.record(.brightness(level: 0.5002)) == .none)
        #expect(tracker.record(.brightness(level: 0.5 - 1.0 / 64.0)) == .brightnessDown)
    }

    @Test func muteAndUnmute() {
        var tracker = HUDTransitionTracker()
        _ = tracker.record(.volume(level: 0.5, muted: false))
        #expect(tracker.record(.volume(level: 0.5, muted: true)) == .mute)
        #expect(tracker.record(.volume(level: 0.5, muted: false)) == .unmute)
    }

    @Test func turningDownToZeroIsMute() {
        var tracker = HUDTransitionTracker()
        _ = tracker.record(.volume(level: 0.0625, muted: false))
        #expect(tracker.record(.volume(level: 0, muted: false)) == .mute)
        #expect(tracker.record(.volume(level: 0.0625, muted: false)) == .unmute)
    }

    @Test func volumeUpWhileMutedIsUnmute() {
        var tracker = HUDTransitionTracker()
        _ = tracker.record(.volume(level: 0.5, muted: true))
        #expect(tracker.record(.volume(level: 0.5625, muted: false)) == .unmute)
    }

    @Test func changesWhileSilentAreNoChange() {
        var tracker = HUDTransitionTracker()
        _ = tracker.record(.volume(level: 0.5, muted: true))
        #expect(tracker.record(.volume(level: 0.4375, muted: true)) == .none)
        _ = tracker.record(.volume(level: 0.4375, muted: false))
        _ = tracker.record(.volume(level: 0, muted: false))
        #expect(tracker.record(.volume(level: 0, muted: true)) == .none)
    }

    @Test func nothingHappensAtTheEnds() {
        var tracker = HUDTransitionTracker()
        _ = tracker.record(.brightness(level: 1))
        #expect(tracker.record(.brightness(level: 1)) == .none)
        _ = tracker.record(.volume(level: 1, muted: false))
        #expect(tracker.record(.volume(level: 1, muted: false)) == .none)
    }

    @Test func brightnessIsTrackedPerDisplay() {
        var tracker = HUDTransitionTracker()
        _ = tracker.record(.brightness(level: 0.5))
        #expect(tracker.record(.brightness(level: 0.25), display: 7) == .none)
        #expect(tracker.record(.brightness(level: 0.5625)) == .brightnessUp)
        #expect(tracker.record(.brightness(level: 0.1875), display: 7) == .brightnessDown)
    }

    @Test func captionsAreNoChangeAndLeaveLevelsAlone() {
        var tracker = HUDTransitionTracker()
        _ = tracker.record(.volume(level: 0.5, muted: false))
        #expect(tracker.record(.caption(symbol: "checkmark", text: "Voilá!")) == .none)
        #expect(tracker.record(.volume(level: 0.5625, muted: false)) == .volumeUp)
    }
}
