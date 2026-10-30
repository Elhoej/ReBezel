import CoreAudio
import Foundation
import os

/// Bluetooth headphones the sound now goes to.
struct Headphones: Equatable, Sendable {
    /// The name the device has in Sound settings, e.g. "Simon's AirPods Pro".
    let name: String

    /// The SF Symbol that looks most like the device. CoreAudio says only that
    /// it is Bluetooth, so this goes by the name, which for AirPods and Beats
    /// keeps the model unless the user renames it.
    var symbolName: String {
        let name = name.lowercased()
        let symbols: [(match: String, symbol: String)] = [
            ("airpods max", "airpods.max"),
            ("airpods pro", "airpods.pro"),
            ("airpods", "airpods"),
            ("powerbeats", "beats.powerbeats.pro"),
            ("studio buds", "beats.studiobuds"),
            ("fit pro", "beats.fitpro"),
            ("beats", "beats.headphones"),
        ]
        return symbols.first { name.contains($0.match) }?.symbol ?? "headphones"
    }
}

/// Notices when the sound moves to Bluetooth headphones, as it does when
/// AirPods connect, and reports them.
///
/// This watches the default output device rather than Bluetooth itself, so it
/// needs no Bluetooth permission. Headphones that connect without taking over
/// the sound don't count, and picking headphones that were already connected
/// in Control Center does, since that is when the sound starts going to them.
@MainActor
final class HeadphonesObserver {
    nonisolated private static let logger = Logger(subsystem: "com.simonelhoej.ReBezel", category: "HeadphonesObserver")

    /// The default output device changed to Bluetooth headphones.
    var onConnect: ((Headphones) -> Void)?

    private(set) var isRunning = false
    private var device: AudioDeviceID?
    /// Kept so the same block can be handed back when removing the listener.
    private var listener: AudioObjectPropertyListenerBlock?

    func start() {
        guard !isRunning else { return }
        isRunning = true
        // Headphones already in use when this starts were not just connected.
        device = VolumeController.defaultOutputDevice()

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.defaultDeviceDidChange() }
        }
        var address = VolumeController.defaultOutputDeviceAddress()
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, .main, listener
        )
        if status == noErr {
            self.listener = listener
            Self.logger.info("Headphones observer started")
        } else {
            Self.logger.error("Could not watch the default output device (status \(status))")
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        if let listener {
            var address = VolumeController.defaultOutputDeviceAddress()
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, .main, listener
            )
            self.listener = nil
        }
        device = nil
        Self.logger.info("Headphones observer stopped")
    }

    private func defaultDeviceDidChange() {
        let current = VolumeController.defaultOutputDevice()
        // CoreAudio can report the same switch more than once.
        guard current != device else { return }
        device = current
        guard let current, Self.isBluetooth(current), let name = Self.name(of: current) else { return }
        Self.logger.info("Sound moved to Bluetooth device \(name, privacy: .public)")
        onConnect?(Headphones(name: name))
    }

    private static func isBluetooth(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    private static func name(of device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr,
              let name else { return nil }
        return name.takeRetainedValue() as String
    }
}
