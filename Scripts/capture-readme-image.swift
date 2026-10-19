import Cocoa

// Captures the README images: real bezels (HUDView in the same Liquid Glass and
// classic backgrounds HUDWindowController builds) over a generated backdrop,
// shown on screen for a moment and grabbed with screencapture. NSGlassEffectView
// and NSVisualEffectView only render on screen, so this needs Screen Recording
// permission for the terminal.
// Usage:
//   swiftc -O -parse-as-library -o /tmp/capture Scripts/capture-readme-image.swift \
//     ReBezel/HUD/HUDView.swift ReBezel/HUD/HUDPanel.swift
//   /tmp/capture docs/images/bezel.png regular
//   /tmp/capture docs/images/styles.png classic regular clear
// Each bezel is style[:symbol[:level]], style being classic, regular or clear.

let args = Array(CommandLine.arguments.dropFirst())
let out = args[0]
let specs = args.dropFirst().map { $0.split(separator: ":").map(String.init) }

let canvas = NSSize(width: 800, height: 440)
let side: CGFloat = 200
let gap: CGFloat = 40

func makeBackdrop(size: NSSize) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                        bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let base = CGGradient(colorsSpace: space, colors: [
        CGColor(srgbRed: 0.10, green: 0.16, blue: 0.42, alpha: 1),
        CGColor(srgbRed: 0.30, green: 0.18, blue: 0.52, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(base, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
    let blobs: [(CGFloat, CGFloat, CGFloat, CGColor)] = [
        (0.12, 0.85, 0.55, CGColor(srgbRed: 0.20, green: 0.55, blue: 0.95, alpha: 0.9)),
        (0.85, 0.80, 0.50, CGColor(srgbRed: 0.95, green: 0.45, blue: 0.55, alpha: 0.85)),
        (0.70, 0.10, 0.60, CGColor(srgbRed: 0.98, green: 0.62, blue: 0.30, alpha: 0.8)),
        (0.20, 0.05, 0.45, CGColor(srgbRed: 0.45, green: 0.30, blue: 0.85, alpha: 0.8)),
        (0.50, 0.55, 0.30, CGColor(srgbRed: 0.85, green: 0.40, blue: 0.80, alpha: 0.6)),
    ]
    for (x, y, r, color) in blobs {
        let c = CGPoint(x: x * size.width, y: y * size.height)
        let g = CGGradient(colorsSpace: space, colors: [color, color.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r * size.width, options: [])
    }
    return ctx.makeImage()!
}

@MainActor
func makeBezel(style: String, symbol: String, level: Float) -> NSView {
    let size = NSSize(width: side, height: side)
    let view = HUDView(frame: NSRect(origin: .zero, size: size))
    view.autoresizingMask = [.width, .height]
    view.symbolName = symbol
    view.content = .level(level)
    if style == "classic" {
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.appearance = NSAppearance(named: .darkAqua)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 18
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        view.foreground = NSColor(white: 1, alpha: 0.82)
        view.trackColor = NSColor(white: 0, alpha: 0.3)
        effect.addSubview(view)
        return effect
    }
    let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: size))
    glass.style = style == "clear" ? .clear : .regular
    glass.cornerRadius = 28
    glass.appearance = NSAppearance(named: .darkAqua)
    view.foreground = NSColor(white: 1, alpha: 0.95)
    view.trackColor = NSColor(white: 1, alpha: 0.22)
    glass.contentView = view
    return glass
}

@main
enum CaptureReadmeImage {
    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)

            let screen = NSScreen.main!
            let origin = NSPoint(x: screen.frame.midX - canvas.width / 2, y: screen.frame.midY - canvas.height / 2)

            let backdrop = NSWindow(contentRect: NSRect(origin: origin, size: canvas), styleMask: [.borderless],
                                    backing: .buffered, defer: false)
            backdrop.level = .floating
            let imageView = NSImageView(frame: NSRect(origin: .zero, size: canvas))
            imageView.imageScaling = .scaleAxesIndependently
            imageView.image = NSImage(cgImage: makeBackdrop(size: NSSize(width: canvas.width * 2, height: canvas.height * 2)), size: canvas)
            backdrop.contentView = imageView
            backdrop.orderFrontRegardless()

            let total = CGFloat(specs.count) * side + CGFloat(specs.count - 1) * gap
            let margin: CGFloat = 40
            var panels: [NSPanel] = []
            for (i, spec) in specs.enumerated() {
                let style = spec[0]
                let symbol = spec.count > 1 ? spec[1] : "speaker.wave.3"
                let level = spec.count > 2 ? Float(spec[2])! : 11 / 16
                let x = origin.x + (canvas.width - total) / 2 + CGFloat(i) * (side + gap)
                let y = origin.y + (canvas.height - side) / 2
                let panelSize = NSSize(width: side + margin * 2, height: side + margin * 2)
                let panel = HUDPanel(contentRect: NSRect(x: x - margin, y: y - margin, width: panelSize.width, height: panelSize.height),
                                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = false
                let bezel = makeBezel(style: style, symbol: symbol, level: level)
                bezel.frame.origin = NSPoint(x: margin, y: margin)
                let container = NSView(frame: NSRect(origin: .zero, size: panelSize))
                container.addSubview(bezel)
                panel.contentView = container
                panel.orderFrontRegardless()
                panels.append(panel)
            }

            // screencapture -R takes top-left based global coordinates.
            let mainHeight = NSScreen.screens[0].frame.height
            let rect = "\(Int(origin.x)),\(Int(mainHeight - origin.y - canvas.height)),\(Int(canvas.width)),\(Int(canvas.height))"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                task.arguments = ["-x", "-o", "-R", rect, out]
                try! task.run()
                task.waitUntilExit()
                _ = panels
                exit(task.terminationStatus)
            }
            app.run()
        }
    }
}
