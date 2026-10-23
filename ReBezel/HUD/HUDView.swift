import Cocoa

/// Classic macOS bezel: a thin outline symbol in the upper part and, along
/// the bottom, either a 16-segment level bar in a dark track or a short
/// caption (used for the "Voilá!" confirmation during onboarding).
///
/// Each segment is split into quarters so the fine Shift+Option steps
/// (1/64 of the range) are visible: the last segment fills up a quarter at a
/// time, as the system bezel did.
final class HUDView: NSView {
    static let segmentCount = 16
    static let subdivisions = 4

    /// What to show in the lower part of the bezel.
    enum Content: Equatable {
        /// A level bar, 0...1.
        case level(Float)
        /// A line of text where the bar would normally be.
        case caption(String)
    }

    var symbolName: String = "speaker.wave.3" { didSet { updateImage() } }
    var content: Content = .level(0) { didSet { updateContent() } }

    /// Shown in place of the symbol, in the same spot, e.g. a seasonal theme's
    /// animated glyph.
    var glyphOverride: NSView? {
        didSet {
            guard glyphOverride !== oldValue else { return }
            oldValue?.removeFromSuperview()
            if let glyphOverride { addSubview(glyphOverride) }
            imageView.isHidden = glyphOverride != nil
            needsLayout = true
        }
    }

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
    /// The caption is centred on the same line as the track.
    private var captionCenterY: CGFloat { trackBottom + trackHeight / 2 + 1 }

    /// Colour of the glyph, the filled segments and the caption.
    var foreground = NSColor(white: 1, alpha: 0.82) {
        didSet {
            imageView.contentTintColor = foreground
            captionLabel.textColor = foreground
            needsDisplay = true
        }
    }
    /// Colour of the empty bar behind the segments.
    var trackColor = NSColor(white: 0, alpha: 0.3) { didSet { needsDisplay = true } }

    private let imageView = NSImageView()
    private let captionLabel = PlainLabel(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        imageView.imageScaling = .scaleNone
        imageView.contentTintColor = foreground
        addSubview(imageView)

        captionLabel.alignment = .center
        captionLabel.font = .systemFont(ofSize: 19, weight: .medium)
        captionLabel.textColor = foreground
        captionLabel.lineBreakMode = .byTruncatingTail
        captionLabel.isHidden = true
        addSubview(captionLabel)

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
        glyphOverride?.frame = imageView.frame
        let captionHeight = captionLabel.fittingSize.height
        captionLabel.frame = NSRect(
            x: trackInset / 2,
            y: captionCenterY - captionHeight / 2,
            width: bounds.width - trackInset,
            height: captionHeight
        )
    }

    private func updateImage() {
        let config = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .light)
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }

    private func updateContent() {
        switch content {
        case .level:
            captionLabel.isHidden = true
        case .caption(let text):
            captionLabel.stringValue = text
            captionLabel.isHidden = false
            needsLayout = true
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard case .level(let level) = content else { return }

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

        // Quantise to quarter segments: 0...64 quarters.
        let quarters = Self.segmentCount * Self.subdivisions
        let filledQuarters = min(max(Int((level * Float(quarters)).rounded()), 0), quarters)
        let fullSegments = filledQuarters / Self.subdivisions
        let partialQuarters = filledQuarters % Self.subdivisions

        foreground.setFill()
        for index in 0..<fullSegments {
            NSBezierPath(roundedRect: segmentRect(index, in: inner, width: segmentWidth),
                         xRadius: segmentCornerRadius, yRadius: segmentCornerRadius).fill()
        }

        if partialQuarters > 0, fullSegments < Self.segmentCount {
            // Fill the next segment from the left, clipped to its rounded outline.
            let rect = segmentRect(fullSegments, in: inner, width: segmentWidth)
            let fraction = CGFloat(partialQuarters) / CGFloat(Self.subdivisions)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: rect, xRadius: segmentCornerRadius, yRadius: segmentCornerRadius).addClip()
            NSRect(x: rect.minX, y: rect.minY, width: rect.width * fraction, height: rect.height).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func segmentRect(_ index: Int, in inner: NSRect, width: CGFloat) -> NSRect {
        let x = inner.minX + CGFloat(index) * (width + segmentGap)
        return NSRect(x: x, y: inner.minY, width: width, height: inner.height)
    }
}

/// A label that opts out of vibrancy so it is drawn in its plain colour,
/// matching the glyph and the level bar.
private final class PlainLabel: NSTextField {
    override var allowsVibrancy: Bool { false }
}
