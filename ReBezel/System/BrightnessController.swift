import CoreGraphics
import Foundation
import os

/// Controls display brightness through the private DisplayServices
/// framework (the same calls MonitorControl uses). Setting brightness this way
/// does not trigger the system HUD.
final class BrightnessController: Sendable {
    private static let logger = Logger(subsystem: "com.simonelhoej.ReBezel", category: "Brightness")

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CanChange = @convention(c) (CGDirectDisplayID) -> Bool

    private let getBrightness: GetBrightness?
    private let setBrightness: SetBrightness?
    private let canChangeBrightness: CanChange?

    init() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_LAZY) else {
            Self.logger.error("Could not load DisplayServices.framework")
            getBrightness = nil
            setBrightness = nil
            canChangeBrightness = nil
            return
        }
        getBrightness = dlsym(handle, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: GetBrightness.self) }
        setBrightness = dlsym(handle, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: SetBrightness.self) }
        canChangeBrightness = dlsym(handle, "DisplayServicesCanChangeBrightness").map { unsafeBitCast($0, to: CanChange.self) }
        if getBrightness == nil || setBrightness == nil {
            Self.logger.error("DisplayServices symbols missing")
        }
    }

    private var hasSymbols: Bool { getBrightness != nil && setBrightness != nil }

    /// The display the plain brightness keys control: the built-in display,
    /// falling back to any display that reports it can change brightness
    /// (a desktop Mac, or a laptop with its lid closed). Nil if brightness
    /// cannot be changed at all.
    func primaryDisplay() -> CGDirectDisplayID? {
        guard hasSymbols else { return nil }
        let displays = onlineDisplays()
        if let builtin = displays.first(where: { CGDisplayIsBuiltin($0) != 0 }) {
            return builtin
        }
        if let can = canChangeBrightness {
            return displays.first(where: { can($0) })
        }
        return displays.first
    }

    /// The display Control+Brightness controls: the supported external display
    /// under the mouse cursor, or the first supported external if the cursor is
    /// on the built-in display or on an external that cannot be controlled.
    /// "Supported" means DisplayServices can change its brightness (Studio
    /// Display, Pro Display XDR, LG UltraFine), as with the native shortcut.
    /// Nil if there is no such display.
    func externalDisplay() -> CGDirectDisplayID? {
        guard hasSymbols, let can = canChangeBrightness else { return nil }
        let supported = onlineDisplays().filter { CGDisplayIsBuiltin($0) == 0 && can($0) }
        guard !supported.isEmpty else { return nil }

        let cursor = displayUnderCursor()
        if let cursor, supported.contains(cursor) {
            Self.logger.info("External display \(cursor) chosen: under cursor")
            return cursor
        }
        Self.logger.info("External display \(supported[0]) chosen: first supported (cursor on \(cursor ?? 0), not supported)")
        return supported[0]
    }

    private func onlineDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return [] }
        return Array(displays.prefix(Int(count)))
    }

    private func displayUnderCursor() -> CGDirectDisplayID? {
        // CGEvent locations use the same global, top-left-origin coordinates as
        // CGGetDisplaysWithPoint.
        guard let location = CGEvent(source: nil)?.location else { return nil }
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(location, 1, &display, &count) == .success, count > 0 else { return nil }
        return display
    }

    /// 0...1, or nil if unavailable.
    func brightness(of display: CGDirectDisplayID) -> Float? {
        guard let get = getBrightness else { return nil }
        var value: Float = 0
        let status = get(display, &value)
        guard status == 0 else {
            Self.logger.error("DisplayServicesGetBrightness failed (\(status))")
            return nil
        }
        return value
    }

    func setBrightness(_ newValue: Float, of display: CGDirectDisplayID) {
        guard let set = setBrightness else { return }
        let status = set(display, min(max(newValue, 0), 1))
        if status != 0 {
            Self.logger.error("DisplayServicesSetBrightness failed (\(status))")
        }
    }
}
