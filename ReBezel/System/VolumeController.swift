import AudioToolbox
import CoreAudio
import os

/// Reads and writes the output volume of the default audio device via CoreAudio.
/// Changing volume this way does not trigger the system HUD.
struct VolumeController {
    private static let logger = Logger(subsystem: "com.simonelhoej.ReBezel", category: "Volume")

    static func defaultOutputDeviceAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    static func defaultOutputDevice() -> AudioDeviceID? {
        var address = defaultOutputDeviceAddress()
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        guard status == noErr, device != kAudioObjectUnknown else {
            logger.error("No default output device (status \(status))")
            return nil
        }
        return device
    }

    static func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    static func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    /// 0...1, or nil if there is no controllable output device.
    static func volume() -> Float? {
        guard let device = defaultOutputDevice() else { return nil }
        var address = volumeAddress()
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        guard status == noErr else {
            logger.error("Get volume failed (status \(status))")
            return nil
        }
        return value
    }

    static func setVolume(_ newValue: Float) {
        guard let device = defaultOutputDevice() else { return }
        var address = volumeAddress()
        var value = min(max(newValue, 0), 1)
        let size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
        if status != noErr {
            logger.error("Set volume failed (status \(status))")
        }
    }

    static func isMuted() -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        var address = muteAddress()
        guard AudioObjectHasProperty(device, &address) else { return false }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr && value != 0
    }

    static func setMuted(_ muted: Bool) {
        guard let device = defaultOutputDevice() else { return }
        var address = muteAddress()
        guard AudioObjectHasProperty(device, &address) else {
            logger.warning("Output device has no mute control")
            return
        }
        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
        if status != noErr {
            logger.error("Set mute failed (status \(status))")
        }
    }
}
