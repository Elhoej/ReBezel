import Cocoa
import CoreGraphics
import os

/// The special keys macOS delivers as NSSystemDefined events (subtype 8).
/// Raw values are the NX_KEYTYPE_* constants from IOKit/hidsystem/ev_keymap.h.
enum MediaKey: Int, CaseIterable {
    case soundUp = 0
    case soundDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
    case illuminationUp = 21
    case illuminationDown = 22
}

struct MediaKeyEvent: Sendable {
    let key: MediaKey
    let isDown: Bool
    let isRepeat: Bool
    let modifiers: NSEvent.ModifierFlags
}

/// Intercepts media key presses before the rest of the system sees them.
///
/// The handler returns `true` to swallow the event (Control Center then never
/// receives it and never shows its banner), or `false` to let it pass through.
@MainActor
final class MediaKeyTap {
    typealias Handler = @MainActor (MediaKeyEvent) -> Bool

    nonisolated private static let logger = Logger(subsystem: "com.simonelhoej.ReBezel", category: "MediaKeyTap")

    private let handler: Handler
    private var port: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    var isRunning: Bool { port != nil }

    func start() -> Bool {
        guard port == nil else { return true }

        let mask = CGEventMask(1) << CGEventMask(NX_SYSDEFINED)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        // Session tap: sees events before any application does. If the native
        // banner still shows up with this, try `.cghidEventTap` which is earlier.
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: mediaKeyTapCallback,
            userInfo: refcon
        ) else {
            Self.logger.error("CGEvent.tapCreate failed (missing Accessibility permission?)")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        self.port = port
        self.runLoopSource = source
        Self.logger.info("Media key tap started")
        return true
    }

    func stop() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CFMachPortInvalidate(port)
        self.port = nil
        self.runLoopSource = nil
        Self.logger.info("Media key tap stopped")
    }

    fileprivate func reenable() {
        guard let port else { return }
        Self.logger.warning("Tap was disabled by the system; re-enabling")
        CGEvent.tapEnable(tap: port, enable: true)
    }

    /// Decodes an NSSystemDefined CGEvent into a media key event, if it is one.
    nonisolated static func decode(_ cgEvent: CGEvent) -> MediaKeyEvent? {
        guard let event = NSEvent(cgEvent: cgEvent),
              event.type == .systemDefined,
              event.subtype.rawValue == 8 else {
            return nil
        }

        let data1 = event.data1
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let keyFlags = data1 & 0xFFFF
        let keyState = (keyFlags & 0xFF00) >> 8
        let isDown = keyState == 0x0A
        let isRepeat = (keyFlags & 0x1) == 1

        guard let key = MediaKey(rawValue: keyCode) else {
            logger.debug("Unhandled system key code \(keyCode)")
            return nil
        }

        return MediaKeyEvent(
            key: key,
            isDown: isDown,
            isRepeat: isRepeat,
            modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        )
    }

    /// Returns true if the event was consumed.
    fileprivate func dispatch(_ event: MediaKeyEvent) -> Bool {
        handler(event)
    }
}

private func mediaKeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()

    // The tap's run loop source lives on the main run loop, so assuming
    // main-actor isolation here is valid.
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        MainActor.assumeIsolated { tap.reenable() }
        return Unmanaged.passUnretained(event)
    default:
        guard let mediaEvent = MediaKeyTap.decode(event) else {
            return Unmanaged.passUnretained(event)
        }
        let consumed = MainActor.assumeIsolated { tap.dispatch(mediaEvent) }
        return consumed ? nil : Unmanaged.passUnretained(event)
    }
}
