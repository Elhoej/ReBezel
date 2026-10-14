import Cocoa

// Renders the classic ReBezel volume bezel as a macOS app icon at a given pixel size.
// Usage:
//   swiftc -O -o /tmp/render Scripts/render-app-icon.swift
//   for s in 16:1 16:2 32:1 32:2 128:1 128:2 256:1 256:2 512:1 512:2; do
//     pt=${s%%:*}; sc=${s##*:}
//     /tmp/render $((pt*sc)) "ReBezel/Assets.xcassets/AppIcon.appiconset/icon_${pt}x${pt}@${sc}x.png"
//   done
let args = CommandLine.arguments
guard args.count == 3, let pixels = Int(args[1]) else {
    FileHandle.standardError.write("usage: render <pixels> <out.png>\n".data(using: .utf8)!)
    exit(1)
}
let out = URL(fileURLWithPath: args[2])

// Apple's macOS icon grid: on a 1024 canvas the rounded square is 824 wide,
// corner radius ~185, centred. Everything is derived from the 200pt bezel.
let canvas = CGFloat(pixels)
let squareSide = canvas * 824 / 1024
let squareRadius = squareSide * 185 / 824
let scale = squareSide / 200          // bezel points -> pixels
let originX = (canvas - squareSide) / 2
let originY = (canvas - squareSide) / 2

// Small sizes need more contrast: a heavier glyph, a solid bar and no translucency.
let isSmall = pixels <= 64
let symbolWeight: NSFont.Weight = pixels <= 64 ? .medium : (pixels <= 256 ? .regular : .light)

func makeRep() -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: canvas, height: canvas)
    return rep
}

// Tinted SF Symbol rendered into its own transparent bitmap.
func symbolRep(name: String, pointSize: CGFloat, color: NSColor) -> NSBitmapImageRep {
    let rep = makeRep()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: symbolWeight)
    let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
        .withSymbolConfiguration(config)!
    let size = image.size
    let rect = NSRect(x: (canvas - size.width) / 2,
                      y: originY + 112 * scale - size.height / 2,
                      width: size.width, height: size.height)
    image.draw(in: rect)
    color.set()
    NSRect(x: 0, y: 0, width: canvas, height: canvas).fill(using: .sourceAtop)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let rep = makeRep()
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
ctx.setShouldAntialias(true)
ctx.interpolationQuality = .high

let square = NSRect(x: originX, y: originY, width: squareSide, height: squareSide)
let squarePath = NSBezierPath(roundedRect: square, xRadius: squareRadius, yRadius: squareRadius)

// Dark translucent HUD slab, rendered opaque: a soft top-to-bottom gradient.
squarePath.addClip()
let gradient = NSGradient(colors: [
    NSColor(calibratedWhite: 0.30, alpha: 1),
    NSColor(calibratedWhite: 0.20, alpha: 1),
    NSColor(calibratedWhite: 0.15, alpha: 1),
], atLocations: [0, 0.55, 1], colorSpace: .deviceRGB)!
gradient.draw(in: square, angle: -90)

// Faint inner rim, like the material's edge highlight.
NSGraphicsContext.saveGraphicsState()
let rimWidth = max(1, 2 * scale / 4.12)
NSColor(calibratedWhite: 1, alpha: 0.10).setStroke()
let rimPath = NSBezierPath(roundedRect: square.insetBy(dx: rimWidth / 2, dy: rimWidth / 2),
                           xRadius: squareRadius - rimWidth / 2, yRadius: squareRadius - rimWidth / 2)
rimPath.lineWidth = rimWidth
rimPath.stroke()
NSGraphicsContext.restoreGraphicsState()

// Geometry from HUDView, scaled.
let foreground = NSColor(white: 1, alpha: isSmall ? 1 : 0.86)
let trackColor = NSColor(white: 0, alpha: 0.32)
let trackInset: CGFloat = 20 * scale
let trackBottom: CGFloat = 18 * scale
let trackHeight: CGFloat = max(9 * scale, isSmall ? 3 : 0)
let trackCornerRadius: CGFloat = 2.5 * scale
let segmentPadding: CGFloat = 1 * scale
let segmentGap: CGFloat = 1.5 * scale
let segmentCornerRadius: CGFloat = 1 * scale
let segmentCount = 16
let filled = 11

let track = NSRect(x: originX + trackInset, y: originY + trackBottom,
                   width: squareSide - trackInset * 2, height: trackHeight)
trackColor.setFill()
NSBezierPath(roundedRect: track, xRadius: trackCornerRadius, yRadius: trackCornerRadius).fill()

let inner = track.insetBy(dx: segmentPadding, dy: segmentPadding)
let count = CGFloat(segmentCount)
let segmentWidth = (inner.width - segmentGap * (count - 1)) / count
foreground.setFill()
if segmentWidth < 2 {
    // Segments would blur together; draw the filled part as one bar.
    let width = CGFloat(filled) * (segmentWidth + segmentGap) - segmentGap
    let r = NSRect(x: inner.minX, y: inner.minY, width: width, height: inner.height)
    NSBezierPath(roundedRect: r, xRadius: segmentCornerRadius, yRadius: segmentCornerRadius).fill()
}
for index in 0..<(segmentWidth < 2 ? 0 : filled) {
    let x = inner.minX + CGFloat(index) * (segmentWidth + segmentGap)
    let r = NSRect(x: x, y: inner.minY, width: segmentWidth, height: inner.height)
    NSBezierPath(roundedRect: r, xRadius: segmentCornerRadius, yRadius: segmentCornerRadius).fill()
}

// Speaker glyph.
let glyph = symbolRep(name: "speaker.wave.3", pointSize: 96 * scale, color: foreground)
NSImage(size: NSSize(width: canvas, height: canvas)).apply { img in
    img.addRepresentation(glyph)
    img.draw(in: NSRect(x: 0, y: 0, width: canvas, height: canvas))
}

NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: out)

extension NSImage {
    func apply(_ body: (NSImage) -> Void) { body(self) }
}
