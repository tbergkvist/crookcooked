import AVFoundation

final class AlarmService {
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?

    func startIfAllowed(_ allowed: Bool) {
        guard allowed else { return }
        guard engine == nil else { return }

        let sampleRate = 44_100.0
        let duration = 2.4
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleRate * duration)),
              let samples = buffer.floatChannelData?[0]
        else { return }
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

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        do {
            try engine.start()
            player.play()
            self.engine = engine
            self.player = player
        } catch {
            engine.stop()
        }
    }

    func stop() {
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
    }
}
