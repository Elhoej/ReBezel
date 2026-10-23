import Cocoa
import CoreAudio
import os

/// Notices volume and brightness changes that don't come from a key press.
///
/// A Mac with a Touch Bar has no volume or brightness keys. Its Control Strip
/// (ControlStrip.app) sets the levels itself, through CoreAudio and
/// `DisplayServicesSetBrightnessWithType`, and asks for the system banner
/// directly, so `MediaKeyTap` never sees an event. This watches the levels
/// instead. The system banner still shows for those changes: there is no
/// event to swallow.
@MainActor
final class LevelChangeObserver {
    nonisolated private static let logger = Logger(subsystem: "com.simonelhoej.ReBezel", category: "LevelChangeObserver")

    /// The default output device's volume or mute state changed.
    var onVolumeChange: ((_ volume: Float, _ muted: Bool) -> Void)?
    /// The primary display's brightness was changed by hand (not by auto-brightness).
    var onBrightnessChange: ((Float) -> Void)?

    private let brightness: BrightnessController
    private(set) var isRunning = false

    // MARK: Volume state

    private var device: AudioDeviceID?
    /// CoreAudio reports most changes twice; only a different level is news.
    private var lastVolume: Float?
    private var lastMuted: Bool?
    /// Kept so the same blocks can be handed back when removing the listeners.
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    private var levelListener: AudioObjectPropertyListenerBlock?

    // MARK: Brightness state

    private var display: CGDirectDisplayID?
    private var lastBrightness: Float?
    private var interactionEndsAt: ContinuousClock.Instant?
    private var screensAsleep = false
    private var quietUntil: ContinuousClock.Instant?
    private var observers: [NSObjectProtocol] = []

    // Auto-brightness ramps the level in a stream of tiny steps (~0.00015
    // per notification, about every 10 ms) and the system's fades in slightly
    // bigger ones (~0.0013, at most ~0.0025), measured on an M-series MacBook.
    // The Control Strip sets the level in one go per touch, one notification
    // per change.

    /// A step at least this big is the user's.
    private let userStep: Float = 0.004
    /// For this long after a user step, steps at least `followStep` big are
    /// shown too, so a slow drag on the Touch Bar slider keeps the bezel
    /// moving. Auto-brightness steps are smaller and can't keep it open.
    private let interactionWindow: Duration = .seconds(1)
    private let followStep: Float = 0.001
    /// Nobody touches a brightness control without input: changes after this
    /// long without any are the system's, like dimming before display sleep.
    private let maxIdleTime: CFTimeInterval = 30
    /// Brightness may be restored in one jump when the displays wake.
    private let wakeQuietPeriod: Duration = .seconds(3)

    init(brightness: BrightnessController) {
        self.brightness = brightness
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startVolume()
        startBrightness()
        Self.logger.info("Level change observer started")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        stopVolume()
        stopBrightness()
        Self.logger.info("Level change observer stopped")
    }

    // MARK: - Volume

    private func startVolume() {
        let defaultDeviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.observeDefaultDevice() }
        }
        var address = VolumeController.defaultOutputDeviceAddress()
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, .main, defaultDeviceListener
        )
        if status == noErr {
            self.defaultDeviceListener = defaultDeviceListener
        } else {
            Self.logger.error("Could not watch the default output device (status \(status))")
        }
        observeDefaultDevice()
    }

    private func stopVolume() {
        stopObservingDevice()
        if let defaultDeviceListener {
            var address = VolumeController.defaultOutputDeviceAddress()
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, .main, defaultDeviceListener
            )
            self.defaultDeviceListener = nil
        }
    }

    /// Moves the level listeners to the current default output device. The
    /// switch itself shows nothing: plugging in headphones is not a volume change.
    private func observeDefaultDevice() {
        let current = VolumeController.defaultOutputDevice()
        guard current != device || levelListener == nil else { return }
        stopObservingDevice()
        guard let current else { return }

        let levelListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.volumeDidChange() }
        }
        // A device without a volume or mute control just never reports one.
        for var address in [VolumeController.volumeAddress(), VolumeController.muteAddress()]
        where AudioObjectHasProperty(current, &address) {
            let status = AudioObjectAddPropertyListenerBlock(current, &address, .main, levelListener)
            if status != noErr {
                Self.logger.error("Could not watch output device \(current) (status \(status))")
            }
        }
        device = current
        self.levelListener = levelListener
        lastVolume = VolumeController.volume()
        lastMuted = VolumeController.isMuted()
    }

    private func stopObservingDevice() {
        if let device, let levelListener {
            for var address in [VolumeController.volumeAddress(), VolumeController.muteAddress()] {
                AudioObjectRemovePropertyListenerBlock(device, &address, .main, levelListener)
            }
        }
        device = nil
        levelListener = nil
    }

    private func volumeDidChange() {
        guard let volume = VolumeController.volume() else { return }
        let muted = VolumeController.isMuted()
        guard volume != lastVolume || muted != lastMuted else { return }
        lastVolume = volume
        lastMuted = muted
        onVolumeChange?(volume, muted)
    }

    // MARK: - Brightness

    private func startBrightness() {
        observePrimaryDisplay()

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.observePrimaryDisplay() }
        })

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensAsleep = true }
        })
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.displaysDidWake() }
            })
        }
    }

    private func stopBrightness() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        stopObservingDisplay()
    }

    /// Watches the display the plain brightness keys (and the Touch Bar)
    /// control, following it when the lid closes or displays change.
    private func observePrimaryDisplay() {
        let current = brightness.primaryDisplay()
        guard current != display else { return }
        stopObservingDisplay()
        guard let current else { return }

        if brightness.registerForChanges(of: current, observer: observerToken, callback: brightnessChangeCallback) {
            display = current
            lastBrightness = brightness.brightness(of: current)
            Self.logger.info("Watching brightness of display \(current)")
        }
    }

    private func stopObservingDisplay() {
        guard let display else { return }
        brightness.unregisterForChanges(of: display, observer: observerToken)
        self.display = nil
        lastBrightness = nil
        interactionEndsAt = nil
    }

    private func secondsSinceInput() -> CFTimeInterval {
        // ~0 is kCGAnyInputEventType.
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
    }

    private func displaysDidWake() {
        screensAsleep = false
        quietUntil = .now + wakeQuietPeriod
    }

    /// Passed to DisplayServices and handed back to `brightnessChangeCallback`.
    /// The observer lives as long as the app, and the callback only runs
    /// between register and unregister.
    private var observerToken: UnsafeRawPointer {
        UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
    }

    fileprivate func brightnessDidChange(to value: Float) {
        guard let display else { return }
        let step = lastBrightness.map { abs(value - $0) } ?? 0
        lastBrightness = value

        let now = ContinuousClock.now
        if screensAsleep || quietUntil.map({ now < $0 }) == true || secondsSinceInput() > maxIdleTime {
            return
        }
        let interacting = interactionEndsAt.map { now < $0 } == true
        guard step >= userStep || (interacting && step >= followStep) else {
            // Auto-brightness or a system fade.
            return
        }
        interactionEndsAt = now + interactionWindow
        // The notification can trail a quick series of changes; show where
        // the level is now.
        onBrightnessChange?(brightness.brightness(of: display) ?? value)
    }
}

/// DisplayServices calls this on a queue of its own.
private func brightnessChangeCallback(
    center: CFNotificationCenter?,
    observer: UnsafeMutableRawPointer?,
    name: CFNotificationName?,
    object: UnsafeRawPointer?,
    userInfo: CFDictionary?
) {
    guard let observer,
          let value = (userInfo as NSDictionary?)?["value"] as? NSNumber else { return }
    let address = UInt(bitPattern: observer)
    let level = value.floatValue
    DispatchQueue.main.async {
        guard let pointer = UnsafeRawPointer(bitPattern: address) else { return }
        let observer = Unmanaged<LevelChangeObserver>.fromOpaque(pointer).takeUnretainedValue()
        MainActor.assumeIsolated { observer.brightnessDidChange(to: level) }
    }
}
