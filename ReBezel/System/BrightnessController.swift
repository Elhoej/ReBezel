import CoreGraphics
import Foundation
import os

/// Controls built-in display brightness through the private DisplayServices
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

    var isAvailable: Bool { getBrightness != nil && setBrightness != nil && targetDisplay() != nil }

    /// Prefers the built-in display, falls back to any display that reports it can change brightness.
    func targetDisplay() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }

        if let builtin = displays.first(where: { CGDisplayIsBuiltin($0) != 0 }) {
            return builtin
        }
        if let can = canChangeBrightness {
            return displays.first(where: { can($0) })
        }
        return displays.first
    }

    /// 0...1, or nil if unavailable.
    func brightness() -> Float? {
        guard let get = getBrightness, let display = targetDisplay() else { return nil }
        var value: Float = 0
        let status = get(display, &value)
        guard status == 0 else {
            Self.logger.error("DisplayServicesGetBrightness failed (\(status))")
            return nil
        }
        return value
    }

    func setBrightness(_ newValue: Float) {
        guard let set = setBrightness, let display = targetDisplay() else { return }
        let status = set(display, min(max(newValue, 0), 1))
        if status != 0 {
            Self.logger.error("DisplayServicesSetBrightness failed (\(status))")
        }
    }
}
