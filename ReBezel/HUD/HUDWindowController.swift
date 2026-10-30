import Cocoa

/// Shows the bezel as click-through, non-activating panels. One panel is kept
/// per screen; only the active screen's panel is used unless the
/// "show on all screens" preference is on.
@MainActor
final class HUDWindowController {
    private struct ScreenPanel {
        let panel: NSPanel
        let view: HUDView
        let scene: SeasonalScene?
    }

    /// What the current panels were built for. A change rebuilds them.
    private struct Look: Equatable {
        let style: HUDStyle
        let theme: SeasonalTheme?
        /// Only while the Halloween theme is shown.
        let halloweenLook: HalloweenLook?

        @MainActor
        static var current: Look {
            let theme = SeasonalTheme.current
            return Look(style: Preferences.hudStyle, theme: theme,
                        halloweenLook: theme == .halloween ? Preferences.halloweenLook : nil)
        }
    }

    private var panels: [ScreenPanel] = []
    private var builtLook: Look?
    private var hideTask: Task<Void, Never>?
    private var isShowing = false
    private var tracker = HUDTransitionTracker()

    private let size = NSSize(width: 200, height: 200)
    /// Transparent space around the bezel. Liquid Glass draws its own soft
    /// shadow outside its shape; without room for it the shadow is clipped
    /// at the window edge and shows up as dark, square corners.
    private let shadowMargin: CGFloat = 40
    /// The larger transparent space a seasonal theme gets, so its animations
    /// (bats flying out, a spider dropping in) have room around the bezel.
    private let seasonalMargin: CGFloat = 240
    /// Distance from the screen edge for the top and bottom positions.
    private let edgeOffset: CGFloat = 140
    private let visibleDuration: Duration = .seconds(1.5)
    private let captionDuration: Duration = .seconds(2.5)

    private var margin: CGFloat {
        builtLook?.theme == nil ? shadowMargin : seasonalMargin
    }

    /// Shows `reading` on `display` if given and otherwise on the active
    /// screen. For brightness, `display` is also the display the level is
    /// for; `nil` is the built-in one. A caption stays up a bit longer than a
    /// key press bezel so the text can be read. `press` is the change the key
    /// asked for, if a key caused it; see `HUDTransitionTracker.record`.
    func show(_ reading: HUDReading, on display: CGDirectDisplayID? = nil, press: HUDTransition? = nil) {
        let transition = tracker.record(reading, display: display, press: press)
        let duration: Duration
        if case .caption = reading {
            duration = captionDuration
        } else {
            duration = visibleDuration
        }
        present(reading, transition: transition, duration: duration, display: display)
    }

    private func present(_ reading: HUDReading, transition: HUDTransition, duration: Duration, display: CGDirectDisplayID?) {
        let look = Look.current
        if builtLook != look {
            for entry in panels {
                entry.panel.orderOut(nil)
            }
            panels.removeAll()
            builtLook = look
        }

        let screens = targetScreens(display: display)
        ensurePanelCount(screens.count)

        hideTask?.cancel()
        isShowing = true

        let (symbol, content) = Self.symbolAndContent(for: reading)
        for (index, entry) in panels.enumerated() {
            entry.view.symbolName = symbol
            entry.view.content = content
            // Panels not shown this time still follow the levels, without
            // animating, so they are up to date when they next appear.
            entry.scene?.apply(reading, transition: index < screens.count ? transition : .none)
        }
        for (index, screen) in screens.enumerated() {
            let entry = panels[index]
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
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.fadeOut()
        }
    }

    private static func symbolAndContent(for reading: HUDReading) -> (String, HUDView.Content) {
        switch reading {
        case .volume(let level, _):
            reading.isSilent ? ("speaker.slash", .level(0)) : ("speaker.wave.3", .level(level))
        case .brightness(let level):
            ("sun.max", .level(level))
        case .caption(let symbol, let text):
            (symbol, .caption(text))
        }
    }

    private func fadeOut() {
        isShowing = false
        // Panels stay ordered in at alpha 0; they are click-through and invisible.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            for entry in panels {
                entry.panel.animator().alphaValue = 0
            }
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // A key pressed during the fade shows the bezel again; keep its scenes running.
                guard let self, !self.isShowing else { return }
                for entry in self.panels {
                    entry.scene?.pause()
                }
            }
        }
    }

    private func targetScreens(display: CGDirectDisplayID?) -> [NSScreen] {
        let screens = NSScreen.screens
        if Preferences.showOnAllScreens, screens.count > 1 {
            return screens
        }
        if let display, let screen = screens.first(where: { $0.displayID == display }) {
            return [screen]
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
        return NSPoint(x: frame.midX - size.width / 2 - margin, y: y - margin)
    }

    private func ensurePanelCount(_ count: Int) {
        while panels.count < count {
            panels.append(makePanel(look: builtLook ?? Look(style: Preferences.hudStyle, theme: nil, halloweenLook: nil)))
        }
    }

    private func makePanel(look: Look) -> ScreenPanel {
        let panelSize = NSSize(width: size.width + margin * 2, height: size.height + margin * 2)
        let panel = HUDPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
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

        let background: NSView
        switch look.style {
        case .classic:
            background = makeClassicBackground(content: view)
        case .liquidGlassRegular:
            background = makeGlassBackground(content: view, style: .regular)
        case .liquidGlassClear:
            background = makeGlassBackground(content: view, style: .clear)
        }
        background.frame.origin = NSPoint(x: margin, y: margin)

        let container = NSView(frame: NSRect(origin: .zero, size: panelSize))
        container.addSubview(background)
        panel.contentView = container

        let scene = look.theme?.makeScene(in: SeasonalSceneHost(container: container, bezelFrame: background.frame, hudView: view))

        panel.alphaValue = 0
        return ScreenPanel(panel: panel, view: view, scene: scene)
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
        content.cornerRadius = 18
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
        content.cornerRadius = 28
        glass.contentView = content
        return glass
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
