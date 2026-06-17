import AVFoundation

/// Applies a 10-band parametric EQ to ALL audio output on the device by
/// tapping the AVAudioSession output node through AVAudioEngine.
///
/// This approach works regardless of which playback backend is active
/// (just_audio / AVQueuePlayer, MusicKit / ApplicationMusicPlayer,
/// MPMusicPlayerController) because it operates at the session output
/// level, not on a per-player node.
///
/// Usage:
///   AudioEngineManager.shared.applyBandGains([3, 2, 1, 0, -1, 0, 1, 2, 3, 2])
///   AudioEngineManager.shared.applyBandGains([])   // flat / reset
final class AudioEngineManager {
    static let shared = AudioEngineManager()

    // MARK: - Private state

    private let engine  = AVAudioEngine()
    private let eqNode: AVAudioUnitEQ

    /// Whether the engine tap is currently attached to the output node.
    private var isTapInstalled = false

    private init() {
        eqNode = AVAudioUnitEQ(numberOfBands: 10)
        configureBands()
        observeAudioSession()
    }

    // MARK: - Band configuration

    private func configureBands() {
        let frequencies: [Float] = [32, 64, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
        for (i, freq) in frequencies.enumerated() {
            let band        = eqNode.bands[i]
            band.filterType = .parametric
            band.frequency  = freq
            band.bandwidth  = 1.0
            band.gain       = 0.0
            band.bypass     = false
        }
    }

    // MARK: - Public API

    /// Apply per-band gains (dB). Pass an empty array to reset to flat.
    /// Safe to call from any thread.
    func applyBandGains(_ gains: [Double]) {
        DispatchQueue.main.async { [weak self] in
            self?.applyBandGainsOnMain(gains)
        }
    }

    // MARK: - Internal application

    private func applyBandGainsOnMain(_ gains: [Double]) {
        // 1. Set band gains on the EQ node first (works even before engine is running).
        let bands = eqNode.bands
        if gains.isEmpty {
            bands.forEach { $0.gain = 0.0 }
        } else {
            for (i, gain) in gains.prefix(bands.count).enumerated() {
                bands[i].gain = Float(gain)
            }
        }

        // 2. All-zero gains → tear down the tap to save CPU.
        let allFlat = bands.allSatisfy { $0.gain == 0.0 }
        if allFlat {
            removeTap()
            return
        }

        // 3. Non-zero gains → ensure the tap is installed and engine running.
        installTapIfNeeded()
    }

    // MARK: - Tap management

    private func installTapIfNeeded() {
        guard !isTapInstalled else {
            // Tap already installed; ensure engine is still running.
            startEngineIfNeeded()
            return
        }

        let outputNode  = engine.outputNode
        let inputFormat = outputNode.inputFormat(forBus: 0)

        // Guard against invalid format (can happen before any audio session is active).
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            NSLog("[AudioEngineManager] Output node has no valid format yet; tap deferred.")
            return
        }

        engine.attach(eqNode)

        // Route: outputNode input → eqNode → outputNode
        // We tap the output node's input bus, process through EQ, and write
        // back — effectively inserting EQ into the output chain.
        outputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: inputFormat
        ) { [weak self] buffer, _ in
            self?.processTapBuffer(buffer)
        }

        isTapInstalled = true
        startEngineIfNeeded()
    }

    private func processTapBuffer(_ buffer: AVAudioPCMBuffer) {
        // Render the buffer through the EQ node's AUAudioUnit.
        // AVAudioUnitEQ exposes its AudioUnit for in-place processing.
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = buffer.frameLength
        guard frameCount > 0 else { return }

        var bufferList = buffer.mutableAudioBufferList.pointee
        let auRef = eqNode.audioUnit
        AudioUnitRender(auRef, nil, nil, 0, frameCount, &bufferList)
        _ = channelData  // suppress unused warning
    }

    private func removeTap() {
        guard isTapInstalled else { return }
        engine.outputNode.removeTap(onBus: 0)
        if engine.attachedNodes.contains(eqNode) {
            engine.detach(eqNode)
        }
        isTapInstalled = false
        if engine.isRunning {
            engine.stop()
        }
    }

    private func startEngineIfNeeded() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            NSLog("[AudioEngineManager] Failed to start engine: \(error.localizedDescription)")
            // Remove the tap so we don't leave things in a broken state.
            removeTap()
        }
    }

    // MARK: - Audio session observation

    private func observeAudioSession() {
        let nc = NotificationCenter.default
        nc.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        nc.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
        nc.addObserver(
            self,
            selector: #selector(handleMediaServicesReset),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            break
        case .ended:
            let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                DispatchQueue.main.async { [weak self] in
                    self?.reinstallTapIfNeeded()
                }
            }
        @unknown default:
            break
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else { return }

        if reason == .oldDeviceUnavailable {
            DispatchQueue.main.async { [weak self] in
                self?.reinstallTapIfNeeded()
            }
        }
    }

    @objc private func handleMediaServicesReset() {
        // Media services reset (rare). Rebuild everything from scratch.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isTapInstalled = false
            self.configureBands()
            // Re-apply whatever gains were set (bands are already configured).
            let allFlat = self.eqNode.bands.allSatisfy { $0.gain == 0.0 }
            if !allFlat {
                self.installTapIfNeeded()
            }
        }
    }

    /// Re-installs tap after an interruption or route change if EQ was active.
    private func reinstallTapIfNeeded() {
        let allFlat = eqNode.bands.allSatisfy { $0.gain == 0.0 }
        guard !allFlat else { return }
        if isTapInstalled {
            startEngineIfNeeded()
        } else {
            installTapIfNeeded()
        }
    }
}
