import Cocoa

/// Classic macOS bezel: a thin outline symbol in the upper part and a
/// 16-segment level bar sitting in a dark track along the bottom.
final class HUDView: NSView {
    static let segmentCount = 16

    var symbolName: String = "speaker.wave.3" { didSet { updateImage() } }
    /// 0...1
    var level: Float = 0 { didSet { needsDisplay = true } }

    // Geometry, in points, for a 200x200 bezel.
    private let symbolPointSize: CGFloat = 96
    private let symbolCenterY: CGFloat = 112
    private let trackInset: CGFloat = 20
    private let trackBottom: CGFloat = 18
    private let trackHeight: CGFloat = 9
    private let trackCornerRadius: CGFloat = 2.5
    private let segmentPadding: CGFloat = 1
    private let segmentGap: CGFloat = 1.5
    private let segmentCornerRadius: CGFloat = 1

    /// Colour of the glyph and the filled segments.
    var foreground = NSColor(white: 1, alpha: 0.82) {
        didSet {
            imageView.contentTintColor = foreground
            needsDisplay = true
        }
    }
    /// Colour of the empty bar behind the segments.
    var trackColor = NSColor(white: 0, alpha: 0.3) { didSet { needsDisplay = true } }

    private let imageView = NSImageView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        imageView.imageScaling = .scaleNone
        imageView.contentTintColor = foreground
        addSubview(imageView)
        updateImage()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // Draw with plain colours instead of vibrancy blending.
    override var allowsVibrancy: Bool { false }

    override func layout() {
        super.layout()
        let side: CGFloat = 140
        imageView.frame = NSRect(
            x: (bounds.width - side) / 2,
            y: symbolCenterY - side / 2,
            width: side,
            height: side
        )
    }

    private func updateImage() {
        let config = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .light)
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let track = NSRect(
            x: trackInset,
            y: trackBottom,
            width: bounds.width - trackInset * 2,
            height: trackHeight
        )
        trackColor.setFill()
        NSBezierPath(roundedRect: track, xRadius: trackCornerRadius, yRadius: trackCornerRadius).fill()

        let inner = track.insetBy(dx: segmentPadding, dy: segmentPadding)
        let count = CGFloat(Self.segmentCount)
        let segmentWidth = (inner.width - segmentGap * (count - 1)) / count
        let filled = Int((level * Float(Self.segmentCount)).rounded(.toNearestOrAwayFromZero))

        foreground.setFill()
        for index in 0..<filled {
            let x = inner.minX + CGFloat(index) * (segmentWidth + segmentGap)
            let rect = NSRect(x: x, y: inner.minY, width: segmentWidth, height: inner.height)
            NSBezierPath(roundedRect: rect, xRadius: segmentCornerRadius, yRadius: segmentCornerRadius).fill()
        }
    }
}
