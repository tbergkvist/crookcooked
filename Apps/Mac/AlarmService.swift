import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

/// The siren. While it sounds, the Mac's own speakers are the output, at full
/// volume and unmuted, and they are held there: volume keys, the mute key, or
/// plugging in headphones are undone within a quarter of a second. The owner's
/// previous output device and volume come back when it stops.
final class AlarmService {
    private var engine: AVAudioEngine?
    private var buffer: AVAudioPCMBuffer?
    private var enforcement: DispatchSourceTimer?
    private var configurationObserver: NSObjectProtocol?
    private var saved: (device: AudioObjectID, volume: Float32?, muted: Bool?)?
    /// Looked up once per alarm; the device list does not need re-reading four times a second.
    private var speakers: AudioObjectID?

    var isSounding: Bool { engine != nil }

    func start() {
        guard engine == nil else { return }
        speakers = CoreAudioDevice.builtInSpeakers
        saveOutputState()
        holdOutputAtMaximum()
        startEngine()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
        timer.setEventHandler { [weak self] in self?.holdOutputAtMaximum() }
        timer.resume()
        enforcement = timer
    }

    func stop() {
        enforcement?.cancel()
        enforcement = nil
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine?.stop()
        engine = nil
        restoreOutputState()
    }

    // MARK: - Sound

    private func startEngine() {
        guard let buffer = buffer ?? Self.makeSiren() else { return }
        self.buffer = buffer

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        do {
            try engine.start()
            player.play()
        } catch {
            return
        }
        self.engine = engine

        // Changing the output device stops the engine; start a new one on the new device.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.engine != nil else { return }
            if let configurationObserver = self.configurationObserver {
                NotificationCenter.default.removeObserver(configurationObserver)
            }
            self.engine?.stop()
            self.engine = nil
            self.startEngine()
        }
    }

    private static func makeSiren() -> AVAudioPCMBuffer? {
        let sampleRate = 44_100.0
        let duration = 2.4
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleRate * duration)),
              let samples = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = buffer.frameCapacity

        var phase = 0.0
        for frame in 0..<Int(buffer.frameLength) {
            let time = Double(frame) / sampleRate
            let sweep = (sin(time * .pi * 1.7) + 1) / 2
            let frequency = 620 + 820 * sweep
            phase += 2 * .pi * frequency / sampleRate
            let pulse = sin(time * .pi * 5) > -0.35 ? 1.0 : 0.2
            let value = (sin(phase) * 0.72 + sin(phase * 2.01) * 0.18) * pulse
            samples[frame] = Float(max(-0.9, min(0.9, value)))
        }
        return buffer
    }

    // MARK: - Output device

    private func saveOutputState() {
        guard let device = CoreAudioDevice.defaultOutput else { return }
        saved = (device, CoreAudioDevice.volume(of: device), CoreAudioDevice.isMuted(device))
    }

    private func holdOutputAtMaximum() {
        if let speakers, CoreAudioDevice.defaultOutput != speakers {
            CoreAudioDevice.setDefaultOutput(speakers)
        }
        guard let device = CoreAudioDevice.defaultOutput else { return }
        if CoreAudioDevice.isMuted(device) == true { CoreAudioDevice.setMuted(device, false) }
        if let volume = CoreAudioDevice.volume(of: device), volume < 1 { CoreAudioDevice.setVolume(device, 1) }
    }

    private func restoreOutputState() {
        guard let saved else { return }
        self.saved = nil
        if CoreAudioDevice.defaultOutput != saved.device { CoreAudioDevice.setDefaultOutput(saved.device) }
        if let volume = saved.volume { CoreAudioDevice.setVolume(saved.device, volume) }
        if let muted = saved.muted { CoreAudioDevice.setMuted(saved.device, muted) }
    }
}

/// The few CoreAudio properties the alarm needs, without the pointer ceremony at each call site.
private enum CoreAudioDevice {
    static var defaultOutput: AudioObjectID? {
        read(AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
    }

    static func setDefaultOutput(_ device: AudioObjectID) {
        write(AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal, value: device)
    }

    /// The Mac's own speakers, if it has any. Found by transport type, so it
    /// does not depend on the device's localised name.
    static var builtInSpeakers: AudioObjectID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return nil }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return nil }

        return devices.first { device in
            let transport: UInt32? = read(device, selector: kAudioDevicePropertyTransportType, scope: kAudioObjectPropertyScopeGlobal)
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            let hasOutput = AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamSize) == noErr && streamSize > 0
            return transport == kAudioDeviceTransportTypeBuiltIn && hasOutput
        }
    }

    static func volume(of device: AudioObjectID) -> Float32? {
        read(device, selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioObjectPropertyScopeOutput)
    }

    static func setVolume(_ device: AudioObjectID, _ value: Float32) {
        write(device, selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioObjectPropertyScopeOutput, value: value)
    }

    static func isMuted(_ device: AudioObjectID) -> Bool? {
        let value: UInt32? = read(device, selector: kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)
        return value.map { $0 != 0 }
    }

    static func setMuted(_ device: AudioObjectID, _ muted: Bool) {
        write(device, selector: kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput, value: UInt32(muted ? 1 : 0))
    }

    private static func read<Value: BitwiseCopyable>(_ object: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope) -> Value? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var size = UInt32(MemoryLayout<Value>.size)
        let pointer = UnsafeMutablePointer<Value>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.pointee
    }

    private static func write<Value: BitwiseCopyable>(_ object: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, value: Value) {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(object, &address),
              AudioObjectIsPropertySettable(object, &address, &settable) == noErr, settable.boolValue
        else { return }
        var value = value
        AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<Value>.size), &value)
    }
}
