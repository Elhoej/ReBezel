import Cocoa
import Lottie

/// The jack-o'-lantern that takes the sun's place. Its animation runs from
/// unlit (progress 0) to fully lit (1) and follows the brightness: up plays it
/// forward, down plays it backward.
@MainActor
final class PumpkinGlyph {
    /// How long a change takes whatever its size, so a quarter step is as
    /// visible as a jump from 0 to 100%.
    private static let changeDuration: Double = 0.25

    let view: LottieAnimationView
    private let duration: TimeInterval

    init(animation: LottieAnimation) {
        view = LottieAnimationView(animation: animation)
        view.contentMode = .scaleAspectFit
        view.loopMode = .playOnce
        view.backgroundBehavior = .continuePlaying
        duration = animation.duration
    }

    func show(level: Float, animated: Bool) {
        let target = AnimationProgressTime(min(max(level, 0), 1))
        guard animated else {
            view.currentProgress = target
            return
        }
        // A key repeat lands mid-change: carry on from what is on screen.
        let from = view.isAnimationPlaying ? view.realtimeAnimationProgress : view.currentProgress
        let span = abs(target - from)
        guard span > 0.0001 else { return }
        view.animationSpeed = span * duration / Self.changeDuration
        view.play(fromProgress: from, toProgress: target, loopMode: .playOnce)
    }

    func pause() {
        view.pause()
    }
}
