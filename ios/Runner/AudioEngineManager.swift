import AVFoundation

// MARK: - AudioEngineManager
//
// Applies a 10-band parametric EQ to just_audio playback on iOS.
//
// Architecture
// ─────────────
// just_audio 0.10+ supports an AVAudioEngine backend when the AudioPlayer
// is created with AudioLoadConfiguration(darwinLoadControl: .avAudioEngine).
// In that mode just_audio builds its own AVAudioEngine internally and
// connects:  playerNode → mainMixerNode → outputNode
//
// We intercept that graph and insert our eqNode:
//   playerNode → mainMixerNode → eqNode → outputNode
//
// The Dart side calls MethodChannel "mo1/equalizer" → "setPreset" which
// calls applyBandGains(_:).  The MethodChannel "mo1/equalizer" → "wireEngine"
// is called once after the AudioPlayer is ready, passing the engine pointer
// via AudioPlayer.audioEffects (AVAudioEngineNativeWrapper).
//
// Fallback
// ────────
// For MusicKit / MPMusicPlayerController paths (which never expose their
// engine) we keep a standalone AVAudioEngine + outputNode tap as a
// best-effort approach.  Note: this fallback CANNOT mutate in-place;
// it silently no-ops for those sources.  Full EQ for MusicKit requires
// a different API surface (AudioComponentFindNext / AUGraph) that is
// out of scope here.  Local-file playback via just_audio is fully covered.

final class AudioEngineManager {
    static let shared = AudioEngineManager()

    // MARK: - Private state

    private let eqNode: AVAudioUnitEQ
    /// Gains currently applied (kept so we can re-wire after interruption).
    private var currentGains: [Double] = []

    /// Set when just_audio hands us its engine.
    private weak var wiredEngine: AVAudioEngine?
    private var isWiredIntoJustAudioEngine = false

    // Standalone fallback engine (used only when wiredEngine is nil).
    private let fallbackEngine = AVAudioEngine()
    private var fallbackTapInstalled = false

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

    /// Wire our eqNode into the provided just_audio AVAudioEngine.
    /// Must be called on the main thread after the AudioPlayer is configured.
    ///
    /// just_audio (AVAudioEngine mode) graph before wiring:
    ///   playerNode → (optional: pitch/speed nodes) → mainMixerNode → outputNode
    ///
    /// After wiring:
    ///   playerNode → (optional nodes) → mainMixerNode → eqNode → outputNode
    func wireIntoEngine(_ engine: AVAudioEngine) {
        guard !isWiredIntoJustAudioEngine || wiredEngine !== engine else { return }

        // Tear down any previous wiring.
        unwireFromEngine()
        removeFallbackTap()

        let mixer    = engine.mainMixerNode
        let output   = engine.outputNode
        let format   = mixer.outputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            NSLog("[AudioEngineManager] wireIntoEngine: mixer has no valid format yet, deferred")
            return
        }

        engine.attach(eqNode)
        // Disconnect mixer → output, insert eqNode in between.
        engine.disconnectNodeOutput(mixer)
        engine.connect(mixer,   to: eqNode,  format: format)
        engine.connect(eqNode,  to: output,  format: format)

        wiredEngine = engine
        isWiredIntoJustAudioEngine = true

        // Re-apply gains now that the graph is wired.
        applyGainsToEqNode(currentGains)

        if engine.isRunning {
            // Engine already running — no need to restart.
            NSLog("[AudioEngineManager] Wired eqNode into running just_audio engine")
        } else {
            startEngine(engine, tag: "just_audio")
        }
    }

    /// Apply per-band gains (dB). Pass an empty array to reset to flat / bypass.
    /// Safe to call from any thread.
    func applyBandGains(_ gains: [Double]) {
        DispatchQueue.main.async { [weak self] in
            self?.applyBandGainsOnMain(gains)
        }
    }

    // MARK: - Internal application

    private func applyBandGainsOnMain(_ gains: [Double]) {
        currentGains = gains
        applyGainsToEqNode(gains)

        let allFlat = eqNode.bands.allSatisfy { $0.gain == 0.0 }

        if isWiredIntoJustAudioEngine {
            // EQ node stays in the graph; bypass it when flat for zero overhead.
            eqNode.bypass = allFlat
            if let engine = wiredEngine, !engine.isRunning {
                startEngine(engine, tag: "just_audio (resume)")
            }
            return
        }

        // Fallback standalone path (MusicKit / MPMusicPlayerController).
        if allFlat {
            removeFallbackTap()
        } else {
            installFallbackTapIfNeeded()
        }
    }

    private func applyGainsToEqNode(_ gains: [Double]) {
        let bands = eqNode.bands
        if gains.isEmpty {
            bands.forEach { $0.gain = 0.0 }
        } else {
            for (i, gain) in gains.prefix(bands.count).enumerated() {
                bands[i].gain = Float(gain)
            }
        }
    }

    // MARK: - just_audio engine wiring helpers

    private func unwireFromEngine() {
        guard isWiredIntoJustAudioEngine, let engine = wiredEngine else { return }
        // Restore original mixer → output connection.
        let mixer  = engine.mainMixerNode
        let output = engine.outputNode
        let format = eqNode.outputFormat(forBus: 0)
        engine.disconnectNodeOutput(eqNode)
        engine.disconnectNodeOutput(mixer)
        engine.detach(eqNode)
        engine.connect(mixer, to: output, format: format)
        isWiredIntoJustAudioEngine = false
        wiredEngine = nil
    }

    // MARK: - Fallback tap (standalone, read-only capture — for future use)

    /// NOTE: AVAudioEngine output-node taps are READ-ONLY captures.
    /// They cannot mutate audio in-place.  This fallback installs a tap
    /// solely to keep the API surface consistent; actual EQ processing
    /// for non-just_audio sources (MusicKit etc.) is not possible via
    /// this path.  It is kept here as a no-op placeholder.
    private func installFallbackTapIfNeeded() {
        guard !fallbackTapInstalled else {
            startEngine(fallbackEngine, tag: "fallback")
            return
        }
        let outputNode = fallbackEngine.outputNode
        let format     = outputNode.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            NSLog("[AudioEngineManager] Fallback output node has no valid format yet")
            return
        }
        outputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { _, _ in
            // Read-only tap: no in-place mutation possible here.
        }
        fallbackTapInstalled = true
        startEngine(fallbackEngine, tag: "fallback")
    }

    private func removeFallbackTap() {
        guard fallbackTapInstalled else { return }
        fallbackEngine.outputNode.removeTap(onBus: 0)
        fallbackTapInstalled = false
        if fallbackEngine.isRunning { fallbackEngine.stop() }
    }

    // MARK: - Engine start helper

    private func startEngine(_ engine: AVAudioEngine, tag: String) {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
            NSLog("[AudioEngineManager] Started \(tag) engine")
        } catch {
            NSLog("[AudioEngineManager] Failed to start \(tag) engine: \(error.localizedDescription)")
        }
    }

    // MARK: - Audio session observation

    private func observeAudioSession() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleInterruption(_:)),
                       name: AVAudioSession.interruptionNotification,
                       object: AVAudioSession.sharedInstance())
        nc.addObserver(self, selector: #selector(handleRouteChange(_:)),
                       name: AVAudioSession.routeChangeNotification,
                       object: AVAudioSession.sharedInstance())
        nc.addObserver(self, selector: #selector(handleMediaServicesReset),
                       name: AVAudioSession.mediaServicesWereResetNotification,
                       object: nil)
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard
            let info      = notification.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type      = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        if case .ended = type {
            let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                DispatchQueue.main.async { [weak self] in self?.reinstallIfNeeded() }
            }
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard
            let info        = notification.userInfo,
            let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason      = AVAudioSession.RouteChangeReason(rawValue: reasonValue),
            reason == .oldDeviceUnavailable
        else { return }
        DispatchQueue.main.async { [weak self] in self?.reinstallIfNeeded() }
    }

    @objc private func handleMediaServicesReset() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isWiredIntoJustAudioEngine = false
            self.wiredEngine = nil
            self.fallbackTapInstalled = false
            self.configureBands()
            // Re-apply; the Dart side will call wireEngine again on next play.
            self.applyGainsToEqNode(self.currentGains)
        }
    }

    private func reinstallIfNeeded() {
        let allFlat = eqNode.bands.allSatisfy { $0.gain == 0.0 }
        guard !allFlat else { return }
        if let engine = wiredEngine {
            startEngine(engine, tag: "just_audio (resume after interruption)")
        } else {
            installFallbackTapIfNeeded()
        }
    }
}
