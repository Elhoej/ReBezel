import Cocoa

/// Classic macOS bezel: a thin outline symbol in the upper part and, along
/// the bottom, either a 16-segment level bar in a dark track or a short
/// caption (the "Voilá!" confirmation during onboarding, or the name of
/// headphones that just connected).
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

    /// Shown along the bottom edge behind the glyph, e.g. a seasonal theme's
    /// scenery: at its own aspect ratio, `backdropOverhang` wider than the
    /// bezel on each side and cut off at the bezel's edges. The bar and
    /// caption move up to stand clear of it.
    var backdrop: NSImage? {
        didSet {
            backdropView.image = backdrop
            backdropView.isHidden = backdrop == nil
            needsLayout = true
            needsDisplay = true
        }
    }

    /// A radial glow, from the centre outwards, with where each colour sits (0...1).
    struct Backlight: Equatable {
        var colors: [NSColor]
        var locations: [CGFloat]
    }

    /// Drawn behind everything else, centred on the glyph and reaching the
    /// corners, cut to `cornerRadius`: e.g. a seasonal theme's light source.
    /// `nil` draws none.
    var backlight: Backlight? { didSet { needsDisplay = true } }

    /// The corner radius of the background the view sits in. Only the
    /// backlight is cut to it; the background clips everything else itself.
    var cornerRadius: CGFloat = 0 { didSet { needsDisplay = true } }

    // Geometry, in points, for a 200x200 bezel.
    private let symbolPointSize: CGFloat = 96
    private let symbolCenterY: CGFloat = 112
    private let trackInset: CGFloat = 20
    private let defaultTrackBottom: CGFloat = 18
    /// Space between the top of the backdrop and the bar.
    private let backdropGap: CGFloat = 6
    /// How far the backdrop reaches past the bezel's left and right edges.
    private let backdropOverhang: CGFloat = 8
    private let trackHeight: CGFloat = 9
    private let trackCornerRadius: CGFloat = 2.5
    private let segmentPadding: CGFloat = 1
    private let segmentGap: CGFloat = 1.5
    private let segmentCornerRadius: CGFloat = 1
    private var backdropHeight: CGFloat {
        guard let backdrop, backdrop.size.width > 0 else { return 0 }
        return (bounds.width + backdropOverhang * 2) * backdrop.size.height / backdrop.size.width
    }
    private var trackBottom: CGFloat {
        backdrop == nil ? defaultTrackBottom : max(defaultTrackBottom, backdropHeight + backdropGap)
    }
    private let captionFontSize: CGFloat = 19
    /// A longer caption, like a pair of headphones' name, wraps onto this
    /// many lines, then gets smaller down to `minimumCaptionFontSize`, and
    /// only then is cut off.
    private let captionMaximumLines = 2
    private let minimumCaptionFontSize: CGFloat = 13
    /// The least space between the caption and the glyph, and between the
    /// glyph and the top edge when the glyph moves up to keep that space.
    private let captionGlyphGap: CGFloat = 6
    private let glyphTopMargin: CGFloat = 14
    /// A one-line caption is centred on the same line as the track. A longer
    /// one keeps its last line there and grows upward, toward the glyph.
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
    /// A soft rim of this colour around the glyph, the filled segments, the
    /// caption and the backdrop, so a dark `foreground` still shows on a dark
    /// background. `nil` (the default) draws them plain.
    var rim: NSColor? {
        didSet {
            applyRim(to: imageView.layer)
            applyRim(to: captionLabel.layer)
            backdropView.rim = rim
            needsDisplay = true
        }
    }
    /// How far the rim spreads, in points.
    private let rimRadius: CGFloat = 2

    private let backdropView = BackdropView()
    private let imageView = NSImageView()
    private let captionLabel = PlainLabel(wrappingLabelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        backdropView.overhang = backdropOverhang
        backdropView.isHidden = true
        addSubview(backdropView)

        imageView.imageScaling = .scaleNone
        imageView.contentTintColor = foreground
        imageView.wantsLayer = true
        addSubview(imageView)

        captionLabel.wantsLayer = true
        captionLabel.alignment = .center
        captionLabel.font = captionFont(size: captionFontSize)
        captionLabel.textColor = foreground
        captionLabel.isSelectable = false
        captionLabel.maximumNumberOfLines = captionMaximumLines
        captionLabel.cell?.truncatesLastVisibleLine = true
        captionLabel.isHidden = true
        addSubview(captionLabel)

        updateImage()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // Draw with plain colours instead of vibrancy blending.
    override var allowsVibrancy: Bool { false }

    override func layout() {
        super.layout()
        backdropView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: backdropHeight)
        captionLabel.preferredMaxLayoutWidth = bounds.width - trackInset
        let captionHeight = captionLabel.fittingSize.height
        let lineHeight = Self.singleLineHeight(of: captionLabel.font)
        captionLabel.frame = NSRect(
            x: trackInset / 2,
            y: captionCenterY - lineHeight / 2,
            width: bounds.width - trackInset,
            height: captionHeight
        )

        // A two-line caption above a backdrop reaches the glyph; move the
        // glyph up, as far as the top edge allows, to keep clear of it.
        var glyphCenterY = symbolCenterY
        if !captionLabel.isHidden, let glyph = imageView.image?.size {
            let overlap = captionLabel.frame.maxY + captionGlyphGap - (symbolCenterY - glyph.height / 2)
            let room = bounds.height - glyphTopMargin - (symbolCenterY + glyph.height / 2)
            glyphCenterY += min(max(overlap, 0), max(room, 0))
        }
        let side: CGFloat = 140
        imageView.frame = NSRect(
            x: (bounds.width - side) / 2,
            y: glyphCenterY - side / 2,
            width: side,
            height: side
        )
        glyphOverride?.frame = imageView.frame
    }

    private func updateImage() {
        let config = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .light)
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        // Its height decides whether it has to move up for the caption.
        needsLayout = true
    }

    private func updateContent() {
        switch content {
        case .level:
            captionLabel.isHidden = true
            needsLayout = true
        case .caption(let text):
            let caption = captionLayout(for: text)
            captionLabel.stringValue = caption.text
            captionLabel.font = caption.font
            captionLabel.isHidden = false
            needsLayout = true
        }
        needsDisplay = true
    }

    private func captionFont(size: CGFloat) -> NSFont {
        .systemFont(ofSize: size, weight: .medium)
    }

    /// `text` with its line breaks, in the largest font, down to the
    /// minimum, that fits it in `captionMaximumLines` without breaking a
    /// word. Text that doesn't fit even then is left for the label to wrap
    /// and cut off.
    private func captionLayout(for text: String) -> (text: String, font: NSFont) {
        var size = captionFontSize
        while true {
            let font = captionFont(size: size)
            if let lines = captionLines(for: text, font: font) {
                return (lines.joined(separator: "\n"), font)
            }
            if size <= minimumCaptionFontSize { return (text, font) }
            size -= 1
        }
    }

    /// `text` on one line, or split between two words onto two lines as
    /// evenly as possible; `nil` if neither fits. The label's own padding
    /// takes a few points of the width.
    private func captionLines(for text: String, font: NSFont) -> [String]? {
        let width = bounds.width - trackInset - 6
        func measure(_ string: String) -> CGFloat {
            (string as NSString).size(withAttributes: [.font: font]).width
        }
        if measure(text) <= width { return [text] }

        let words = text.split(separator: " ").map(String.init)
        var best: (lines: [String], widest: CGFloat)?
        for split in words.indices.dropFirst() {
            let lines = [words[..<split].joined(separator: " "), words[split...].joined(separator: " ")]
            let widest = lines.map(measure).max() ?? 0
            if widest <= width, widest < best?.widest ?? .infinity {
                best = (lines, widest)
            }
        }
        return best?.lines
    }

    /// The height of a one-line label in `font`, padding included.
    private static func singleLineHeight(of font: NSFont?) -> CGFloat {
        let cell = NSTextFieldCell(textCell: "X")
        cell.font = font
        return cell.cellSize.height
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if let backlight {
            drawBacklight(backlight)
        }

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

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if let rim {
            let shadow = NSShadow()
            shadow.shadowColor = rim
            shadow.shadowBlurRadius = rimRadius
            shadow.set()
        }
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

    /// The glow is centred on the glyph. The farthest corner is at most
    /// about 0.75 of the width away, so the last colour is only just
    /// arriving at the corners.
    private func drawBacklight(_ backlight: Backlight) {
        guard let gradient = NSGradient(colors: backlight.colors, atLocations: backlight.locations, colorSpace: .sRGB)
        else { return }
        let center = NSPoint(x: bounds.midX, y: symbolCenterY)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).addClip()
        gradient.draw(fromCenter: center, radius: 0, toCenter: center, radius: bounds.width * 0.8,
                      options: [.drawsAfterEndingLocation])
        NSGraphicsContext.restoreGraphicsState()
    }

    private func segmentRect(_ index: Int, in inner: NSRect, width: CGFloat) -> NSRect {
        let x = inner.minX + CGFloat(index) * (width + segmentGap)
        return NSRect(x: x, y: inner.minY, width: width, height: inner.height)
    }

    private func applyRim(to layer: CALayer?) {
        guard let layer else { return }
        layer.shadowColor = rim?.withAlphaComponent(1).cgColor
        layer.shadowOpacity = Float(rim?.alphaComponent ?? 0)
        layer.shadowRadius = rimRadius
        layer.shadowOffset = .zero
    }
}

/// A label that opts out of vibrancy so it is drawn in its plain colour,
/// matching the glyph and the level bar.
private final class PlainLabel: NSTextField {
    override var allowsVibrancy: Bool { false }
}

/// Draws `image` across its full height and `overhang` wider than itself on
/// each side, cut off at its own edges, with a soft `rim` around it if given.
private final class BackdropView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var overhang: CGFloat = 0 { didSet { needsDisplay = true } }
    var rim: NSColor? { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var allowsVibrancy: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        if let rim {
            let shadow = NSShadow()
            shadow.shadowColor = rim
            shadow.shadowBlurRadius = 2
            shadow.set()
        }
        image?.draw(in: bounds.insetBy(dx: -overhang, dy: 0))
    }
}
