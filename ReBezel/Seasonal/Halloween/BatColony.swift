import Cocoa
import Lottie

/// The bats that come with the jack-o'-lantern. Up to `roostSize` hang under
/// the bezel, more the darker the screen. As it brightens, bats leave the
/// roost and a few more burst out of the bezel; as it dims, bats fly in and
/// hang in the next free spot.
///
/// Every bat plays the same flapping loop. A Lottie file can't spawn or steer
/// copies of itself, so the flights are Core Animation paths with a random
/// curve, length, speed and size each time.
@MainActor
final class BatColony {
    nonisolated static let roostSize = 10
    /// Most bats in the air at once (not counting ones flying in to hang), so
    /// holding the key doesn't flood the screen.
    static let maxFlying = 24

    /// Bats hanging at `brightness`: none at full brightness, all of them in the dark.
    nonisolated static func roostCount(for brightness: Float) -> Int {
        let darkness = 1 - min(max(brightness, 0), 1)
        // The tolerance keeps float error (0.1 × 10 = 1.0000001) from rounding up a bat too many.
        return max(0, Int((darkness * Float(roostSize) - 0.0001).rounded(.up)))
    }

    /// Spots fill from the middle outwards, so a few bats look deliberate.
    private static let fillOrder = [4, 5, 3, 6, 2, 7, 1, 8, 0, 9]
    /// How far below the bezel each spot hangs, so neighbours don't line up.
    private static let drops: [CGFloat] = [3, 8, 1, 6, 2, 7, 0, 5, 9, 4]
    /// A hanging bat is smaller than a flying one, so ten fit under the bezel.
    private static let hangingScale: CGFloat = 0.72

    private enum Spot {
        case empty
        case arriving(Bat)
        case hanging(Bat)

        var bat: Bat? {
            switch self {
            case .empty: nil
            case .arriving(let bat), .hanging(let bat): bat
            }
        }
    }

    private let stage: CALayer
    private let bezel: NSRect
    private let animation: LottieAnimation
    private let screenScale: CGFloat
    private var spots = [Spot](repeating: .empty, count: BatColony.roostSize)
    private var flying: [ObjectIdentifier: Bat] = [:]
    private var spare: [Bat] = []

    /// `stage` covers the whole panel; `bezel` is the bezel's frame in it.
    init(stage: CALayer, bezel: NSRect, animation: LottieAnimation) {
        self.stage = stage
        self.bezel = bezel
        self.animation = animation
        screenScale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
    }

    /// Brings the roost to `brightness`. Animated, bats fly off or in for the
    /// difference, and `burst` sends a few more out of the bezel.
    func show(brightness: Float, animated: Bool, burst: Bool) {
        let target = Self.roostCount(for: brightness)
        guard animated else {
            settle(count: target)
            return
        }
        resumeSwaying()

        let occupied = Self.fillOrder.filter { spots[$0].bat != nil }
        if target < occupied.count {
            for index in occupied.suffix(occupied.count - target).reversed() {
                release(spot: index)
            }
        } else if target > occupied.count {
            let free = Self.fillOrder.filter { spots[$0].bat == nil }
            for index in free.prefix(target - occupied.count) {
                arrive(at: index)
            }
        }

        if burst {
            let room = Self.maxFlying - flying.count
            for _ in 0..<min(Int.random(in: 3...5), max(room, 0)) {
                burstFromBezel()
            }
        }
    }

    /// Ends every flight where it was going and stops the hanging bats, so
    /// nothing animates while the bezel is hidden.
    func pause() {
        for bat in flying.values {
            recycle(bat)
        }
        flying.removeAll()
        for index in spots.indices {
            guard let bat = spots[index].bat else { continue }
            hang(bat, at: index)
            bat.carrier.removeAllAnimations()
        }
    }

    // MARK: - Roost

    /// Puts exactly `count` bats in the roost, without animating.
    private func settle(count: Int) {
        for bat in flying.values {
            recycle(bat)
        }
        flying.removeAll()
        for (rank, index) in Self.fillOrder.enumerated() {
            if rank < count {
                let bat = spots[index].bat ?? makeBat()
                hang(bat, at: index)
                sway(bat)
            } else if let bat = spots[index].bat {
                recycle(bat)
                spots[index] = .empty
            }
        }
    }

    private func hangPoint(_ index: Int) -> CGPoint {
        let spacing = bezel.width / CGFloat(Self.roostSize)
        return CGPoint(x: bezel.minX + spacing * (CGFloat(index) + 0.5), y: bezel.minY - 1 - Self.drops[index])
    }

    /// Hangs `bat` upside down from its feet at the spot, wings folded.
    private func hang(_ bat: Bat, at index: Int) {
        bat.flightID += 1
        bat.carrier.removeAllAnimations()
        withoutActions {
            bat.carrier.position = hangPoint(index)
            bat.carrier.transform = Bat.transform(scale: Self.hangingScale, angle: .pi)
            bat.carrier.opacity = 1
        }
        bat.fold()
        if bat.carrier.superlayer == nil {
            stage.addSublayer(bat.carrier)
        }
        spots[index] = .hanging(bat)
    }

    private func sway(_ bat: Bat) {
        let sway = CABasicAnimation(keyPath: "transform.rotation.z")
        sway.fromValue = -0.08
        sway.toValue = 0.08
        sway.isAdditive = true
        sway.autoreverses = true
        sway.repeatCount = .infinity
        sway.duration = .random(in: 1.4...2.0)
        sway.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        sway.beginTime = CACurrentMediaTime() - .random(in: 0...2)
        bat.carrier.add(sway, forKey: "sway")
    }

    private func resumeSwaying() {
        for spot in spots {
            if case .hanging(let bat) = spot, bat.carrier.animation(forKey: "sway") == nil {
                sway(bat)
            }
        }
    }

    // MARK: - Flights

    /// The bat at `index` takes off, from wherever it is, and flies away from the bezel.
    private func release(spot index: Int) {
        guard let bat = spots[index].bat else { return }
        spots[index] = .empty
        let presented = bat.carrier.presentation()
        let start = presented?.position ?? bat.carrier.position
        let startAngle = (presented?.value(forKeyPath: "transform.rotation.z") as? CGFloat) ?? .pi
        let startScale = (presented?.value(forKeyPath: "transform.scale") as? CGFloat) ?? Self.hangingScale
        let direction = outward(from: start, spread: 0.8)
        let end = start + direction * .random(in: 220...300)
        flyAway(bat, from: start, to: end, angles: (startAngle, bankAngle(direction)),
                scales: (startScale, 1.25), opacities: [1, 1, 0], opacityTimes: [0, 0.65, 1])
    }

    /// A bat comes out of the bezel's edge and flies off, growing as it comes closer.
    private func burstFromBezel() {
        let bat = makeBat()
        stage.addSublayer(bat.carrier)
        let start = pointOnBezelEdge()
        let direction = outward(from: start, spread: 0.6)
        let end = start + direction * .random(in: 200...280)
        let angle = bankAngle(direction)
        flyAway(bat, from: start, to: end, angles: (angle, angle),
                scales: (0.5, 1.2), opacities: [0, 1, 1, 0], opacityTimes: [0, 0.15, 0.65, 1])
    }

    private func flyAway(_ bat: Bat, from start: CGPoint, to end: CGPoint, angles: (CGFloat, CGFloat),
                         scales: (CGFloat, CGFloat), opacities: [Float], opacityTimes: [NSNumber]) {
        flying[ObjectIdentifier(bat)] = bat
        bat.flap()
        let duration = CFTimeInterval.random(in: 0.8...1.1)
        let turn = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        turn.values = [angles.0, angles.1, angles.1]
        turn.keyTimes = [0, 0.25, 1]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = opacities
        fade.keyTimes = opacityTimes
        run(bat, along: curve(from: start, to: end), duration: duration,
            timing: CAMediaTimingFunction(name: .easeIn),
            extra: [turn, fade, grow(scales)],
            end: (end, Bat.transform(scale: scales.1, angle: angles.1), opacities.last ?? 0)) { [weak self] in
            self?.flying[ObjectIdentifier(bat)] = nil
            self?.recycle(bat)
        }
    }

    /// A bat flies in from outside the panel and hangs in the spot at `index`.
    private func arrive(at index: Int) {
        let bat = makeBat()
        stage.addSublayer(bat.carrier)
        spots[index] = .arriving(bat)
        bat.flap()

        let end = hangPoint(index)
        let heading = CGFloat.random(in: 0..<(2 * .pi))
        let start = end + CGPoint(x: cos(heading), y: sin(heading)) * .random(in: 260...320)
        let angle = bankAngle(CGPoint(x: end.x - start.x, y: 0).normalized)
        let turn = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        turn.values = [angle, angle, CGFloat.pi]
        turn.keyTimes = [0, 0.8, 1]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1]
        fade.keyTimes = [0, 0.2, 1]
        run(bat, along: curve(from: start, to: end), duration: .random(in: 0.9...1.15),
            timing: CAMediaTimingFunction(name: .easeOut),
            extra: [turn, fade, grow((1.3, Self.hangingScale))],
            end: (end, Bat.transform(scale: Self.hangingScale, angle: .pi), 1)) { [weak self] in
            guard let self, case .arriving(let arriving) = spots[index], arriving === bat else { return }
            hang(bat, at: index)
            sway(bat)
        }
    }

    /// Runs one flight: sets the end state as the model values and animates
    /// towards it. `completion` only runs if no newer flight replaced this one.
    private func run(_ bat: Bat, along path: CGPath, duration: CFTimeInterval, timing: CAMediaTimingFunction,
                     extra: [CAAnimation], end: (CGPoint, CATransform3D, Float), completion: @escaping @MainActor () -> Void) {
        bat.flightID += 1
        let flight = bat.flightID
        bat.carrier.removeAllAnimations()

        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path
        let group = CAAnimationGroup()
        group.animations = [move] + extra
        group.duration = duration
        group.timingFunction = timing

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock {
            MainActor.assumeIsolated {
                guard bat.flightID == flight else { return }
                completion()
            }
        }
        bat.carrier.position = end.0
        bat.carrier.transform = end.1
        bat.carrier.opacity = end.2
        bat.carrier.add(group, forKey: "flight")
        CATransaction.commit()
    }

    private func grow(_ scales: (CGFloat, CGFloat)) -> CAAnimation {
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = scales.0
        grow.toValue = scales.1
        return grow
    }

    /// A gentle curve from `start` to `end`, bowed to a random side.
    private func curve(from start: CGPoint, to end: CGPoint) -> CGPath {
        let middle = (start + end) * 0.5
        let along = (end - start).normalized
        let control = middle + CGPoint(x: -along.y, y: along.x) * .random(in: -70...70)
        let path = CGMutablePath()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        return path
    }

    /// The direction from the bezel's centre through `point`, turned by up to `spread` radians.
    private func outward(from point: CGPoint, spread: CGFloat) -> CGPoint {
        let center = CGPoint(x: bezel.midX, y: bezel.midY)
        let away = point - center
        let angle = atan2(away.y, away.x) + .random(in: -spread...spread)
        return CGPoint(x: cos(angle), y: sin(angle))
    }

    /// Bats lean into a turn: tilted a little towards the side they head for.
    private func bankAngle(_ direction: CGPoint) -> CGFloat {
        -direction.x * 0.35
    }

    private func pointOnBezelEdge() -> CGPoint {
        let inset = bezel.insetBy(dx: 14, dy: 14)
        switch Int.random(in: 0..<4) {
        case 0: return CGPoint(x: .random(in: inset.minX...inset.maxX), y: inset.maxY)
        case 1: return CGPoint(x: .random(in: inset.minX...inset.maxX), y: inset.minY)
        case 2: return CGPoint(x: inset.minX, y: .random(in: inset.minY...inset.maxY))
        default: return CGPoint(x: inset.maxX, y: .random(in: inset.minY...inset.maxY))
        }
    }

    // MARK: - Pool

    private func makeBat() -> Bat {
        spare.popLast() ?? Bat(animation: animation, screenScale: screenScale)
    }

    private func recycle(_ bat: Bat) {
        bat.flightID += 1
        bat.carrier.removeAllAnimations()
        bat.carrier.removeFromSuperlayer()
        bat.fold()
        spare.append(bat)
    }

    private func withoutActions(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }
}

/// One bat: a carrier layer that is moved, scaled and turned freely, holding
/// the Lottie layer. The carrier's anchor is the bat's feet, so a hanging bat
/// hangs (and sways) from them.
@MainActor
private final class Bat {
    /// Side of the carrier, in points, at scale 1. The bat itself is about two
    /// thirds of that wide.
    static let side: CGFloat = 56
    /// Very dark purple rather than black, with a faint light rim from the
    /// shadow, so bats still show up on a dark wallpaper.
    static let color = LottieColor(r: 0.11, g: 0.07, b: 0.14, a: 1)

    static func transform(scale: CGFloat, angle: CGFloat) -> CATransform3D {
        CATransform3DRotate(CATransform3DMakeScale(scale, scale, 1), angle, 0, 0, 1)
    }

    let carrier = CALayer()
    /// Bumped by every new flight, so a finished flight can tell it was replaced.
    var flightID = 0
    private let lottie: LottieAnimationLayer

    init(animation: LottieAnimation, screenScale: CGFloat) {
        lottie = LottieAnimationLayer(animation: animation)
        lottie.loopMode = .loop
        lottie.backgroundBehavior = .continuePlaying
        lottie.screenScale = screenScale
        lottie.setValueProvider(ColorValueProvider(Self.color), keypath: AnimationKeypath(keypath: "**.Color"))

        // LottieAnimationLayer draws at its animation's natural size, y-down,
        // centred on its own top-left corner. Anchoring that corner at the
        // carrier's centre, scaling it down and flipping its geometry puts the
        // bat upright in the middle of the carrier.
        let side = Self.side
        lottie.bounds = CGRect(origin: .zero, size: animation.size)
        lottie.anchorPoint = CGPoint(x: 0, y: 1)
        lottie.isGeometryFlipped = true
        lottie.position = CGPoint(x: side / 2, y: side / 2)
        lottie.transform = CATransform3DMakeScale(side / animation.size.width, side / animation.size.height, 1)

        carrier.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        // The feet: just below the body of the upright bat.
        carrier.anchorPoint = CGPoint(x: 0.5, y: 0.4)
        carrier.shadowColor = NSColor.white.cgColor
        carrier.shadowOpacity = 0.35
        carrier.shadowRadius = 1.5
        carrier.shadowOffset = .zero
        carrier.addSublayer(lottie)
    }

    /// Flaps, starting at a random point in the loop and at a slightly
    /// different speed from its neighbours.
    func flap() {
        lottie.animationSpeed = .random(in: 0.9...1.3)
        lottie.currentProgress = .random(in: 0..<1)
        lottie.play()
    }

    /// Stops on the frame with the wings raised, which upside down reads as folded.
    func fold() {
        lottie.currentProgress = 0
    }
}

private extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, k: CGFloat) -> CGPoint { CGPoint(x: a.x * k, y: a.y * k) }

    var normalized: CGPoint {
        let length = (x * x + y * y).squareRoot()
        return length > 0 ? CGPoint(x: x / length, y: y / length) : CGPoint(x: 0, y: -1)
    }
}
