import Cocoa

/// Shows the bezel as click-through, non-activating panels. One panel is kept
/// per screen; only the active screen's panel is used unless the
/// "show on all screens" preference is on.
@MainActor
final class HUDWindowController {
    private struct ScreenPanel {
        let panel: NSPanel
        let view: HUDView
    }

    private var panels: [ScreenPanel] = []
    private var builtStyle: HUDStyle?
    private var hideTask: Task<Void, Never>?

    private let size = NSSize(width: 200, height: 200)
    /// Distance from the screen edge for the top and bottom positions.
    private let edgeOffset: CGFloat = 140
    private let visibleDuration: Duration = .seconds(1.5)

    func show(symbol: String, level: Float) {
        let style = Preferences.hudStyle
        if builtStyle != style {
            for entry in panels {
                entry.panel.orderOut(nil)
            }
            panels.removeAll()
            builtStyle = style
        }

        let screens = targetScreens()
        ensurePanelCount(screens.count)

        hideTask?.cancel()

        for (index, screen) in screens.enumerated() {
            let entry = panels[index]
            entry.view.symbolName = symbol
            entry.view.level = level
            entry.panel.setFrameOrigin(origin(on: screen))
            entry.panel.orderFrontRegardless()
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            for (index, entry) in panels.enumerated() {
                entry.panel.animator().alphaValue = index < screens.count ? 1 : 0
            }
        }

        hideTask = Task { [weak self] in
            try? await Task.sleep(for: self?.visibleDuration ?? .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.fadeOut()
        }
    }

    private func fadeOut() {
        // Panels stay ordered in at alpha 0; they are click-through and invisible.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            for entry in panels {
                entry.panel.animator().alphaValue = 0
            }
        }
    }

    private func targetScreens() -> [NSScreen] {
        let screens = NSScreen.screens
        if Preferences.showOnAllScreens, screens.count > 1 {
            return screens
        }
        let active = screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
            ?? screens.first
        return active.map { [$0] } ?? []
    }

    private func origin(on screen: NSScreen) -> NSPoint {
        let frame = screen.frame
        let y: CGFloat
        switch Preferences.hudPosition {
        case .bottom:
            y = frame.minY + edgeOffset
        case .center:
            y = frame.midY - size.height / 2
        case .top:
            y = frame.maxY - edgeOffset - size.height
        }
        return NSPoint(x: frame.midX - size.width / 2, y: y)
    }

    private func ensurePanelCount(_ count: Int) {
        while panels.count < count {
            panels.append(makePanel(style: builtStyle ?? Preferences.hudStyle))
        }
    }

    private func makePanel(style: HUDStyle) -> ScreenPanel {
        let panel = HUDPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none

        let view = HUDView(frame: NSRect(origin: .zero, size: size))
        view.autoresizingMask = [.width, .height]

        switch style {
        case .classic:
            panel.contentView = makeClassicBackground(content: view)
        case .liquidGlassRegular:
            panel.contentView = makeGlassBackground(content: view, style: .regular)
        case .liquidGlassClear:
            panel.contentView = makeGlassBackground(content: view, style: .clear)
        }

        panel.alphaValue = 0
        return ScreenPanel(panel: panel, view: view)
    }

    /// Dark translucent square, as on macOS 11–15. Always dark regardless of appearance.
    private func makeClassicBackground(content: HUDView) -> NSView {
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.appearance = NSAppearance(named: .darkAqua)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 18
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true

        content.foreground = NSColor(white: 1, alpha: 0.82)
        content.trackColor = NSColor(white: 0, alpha: 0.3)
        effect.addSubview(content)
        return effect
    }

    /// Liquid Glass square. `.clear` is the transparent, strongly lensed glass
    /// used by Control Center's modules; `.regular` is the frosted variant and
    /// is affected by the system's Liquid Glass tint setting.
    private func makeGlassBackground(content: HUDView, style: NSGlassEffectView.Style) -> NSView {
        let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: size))
        glass.style = style
        glass.cornerRadius = 28
        glass.appearance = NSAppearance(named: .darkAqua)

        content.foreground = NSColor(white: 1, alpha: 0.95)
        content.trackColor = NSColor(white: 1, alpha: 0.22)
        glass.contentView = content
        return glass
    }
}
