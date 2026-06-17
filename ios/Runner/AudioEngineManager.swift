import AVFoundation

/// Shared singleton that owns the AVAudioEngine graph.
/// Both the EqualizerChannel (MethodChannel) and JustAudioEQPlugin
/// reference this same instance so EQ band changes immediately affect playback.
final class AudioEngineManager {
  static let shared = AudioEngineManager()

  let engine     = AVAudioEngine()
  let playerNode = AVAudioPlayerNode()
  let eqNode: AVAudioUnitEQ

  private var isGraphConnected = false
  private var currentFile: AVAudioFile?
  /// Tracks the sample-frame offset so seek works correctly.
  private var scheduledStartFrame: AVAudioFramePosition = 0

  private init() {
    // 10-band EQ: 32 Hz … 16 kHz
    eqNode = AVAudioUnitEQ(numberOfBands: 10)
    let frequencies: [Float] = [32, 64, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
    for (i, freq) in frequencies.enumerated() {
      let band        = eqNode.bands[i]
      band.filterType = .parametric
      band.frequency  = freq
      band.bandwidth  = 1.0
      band.gain       = 0.0
      band.bypass     = false
    }
    buildGraph()
    observeInterruptions()
  }

  // MARK: - Graph

  private func buildGraph() {
    guard !isGraphConnected else { return }
    engine.attach(playerNode)
    engine.attach(eqNode)
    engine.connect(playerNode, to: eqNode,               format: nil)
    engine.connect(eqNode,     to: engine.mainMixerNode,  format: nil)
    isGraphConnected = true
  }

  private func reconnectGraph(format: AVAudioFormat) {
    engine.disconnectNodeOutput(playerNode)
    engine.disconnectNodeOutput(eqNode)
    engine.connect(playerNode, to: eqNode,               format: format)
    engine.connect(eqNode,     to: engine.mainMixerNode,  format: format)
  }

  func startEngineIfNeeded() throws {
    guard !engine.isRunning else { return }
    try engine.start()
  }

  // MARK: - Interruption handling
  // Observes AVAudioSession interruptions (phone calls, Siri, etc.) and
  // automatically restarts the engine + resumes playback when the
  // interruption ends, so EQ never silently stops working.

  private func observeInterruptions() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleInterruption(_:)),
      name: AVAudioSession.interruptionNotification,
      object: AVAudioSession.sharedInstance()
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleRouteChange(_:)),
      name: AVAudioSession.routeChangeNotification,
      object: AVAudioSession.sharedInstance()
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
      // Engine will be stopped by the system; nothing to do.
      break
    case .ended:
      let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
      let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
      if options.contains(.shouldResume) {
        try? restartAfterInterruption()
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

    // Old device unplugged (e.g. headphones removed) — engine may have stopped.
    if reason == .oldDeviceUnavailable {
      try? startEngineIfNeeded()
    }
  }

  private func restartAfterInterruption() throws {
    try AVAudioSession.sharedInstance().setActive(true)
    try startEngineIfNeeded()
    // Re-schedule the current file from the approximate position if one is loaded.
    if let file = currentFile, playerNode.outputFormat(forBus: 0).sampleRate > 0 {
      playerNode.stop()
      playerNode.scheduleFile(file, at: nil, completionHandler: nil)
      playerNode.play()
    }
  }

  // MARK: - EQ

  /// Apply an array of per-band gains (dB). Pass an empty array to reset to flat.
  func applyBandGains(_ gains: [Double]) {
    let bands = eqNode.bands
    if gains.isEmpty {
      bands.forEach { $0.gain = 0.0 }
      return
    }
    for (i, gain) in gains.prefix(bands.count).enumerated() {
      bands[i].gain = Float(gain)
    }
  }

  // MARK: - Playback

  /// Load and play a local file through the EQ graph from the beginning.
  func playFile(at path: String) throws {
    let url  = URL(fileURLWithPath: path)
    let file = try AVAudioFile(forReading: url)
    currentFile = file
    scheduledStartFrame = 0

    reconnectGraph(format: file.processingFormat)
    playerNode.stop()
    try startEngineIfNeeded()
    playerNode.scheduleFile(file, at: nil, completionHandler: nil)
    playerNode.play()
  }

  /// Seek to a position in the current file (seconds).
  /// Re-schedules playback from the target frame so the seek is accurate.
  func seek(to seconds: Double) throws {
    guard let file = currentFile else { return }
    let sampleRate = file.processingFormat.sampleRate
    guard sampleRate > 0 else { return }

    let targetFrame = AVAudioFramePosition(seconds * sampleRate)
    let totalFrames = file.length
    let clampedFrame = max(0, min(targetFrame, totalFrames - 1))
    let remainingFrames = AVAudioFrameCount(totalFrames - clampedFrame)
    guard remainingFrames > 0 else { return }

    scheduledStartFrame = clampedFrame
    let wasPlaying = playerNode.isPlaying

    playerNode.stop()
    try startEngineIfNeeded()
    playerNode.scheduleSegment(
      file,
      startingFrame: clampedFrame,
      frameCount: remainingFrames,
      at: nil,
      completionHandler: nil
    )
    if wasPlaying { playerNode.play() }
  }

  /// Current playback position in seconds.
  var currentPositionSeconds: Double {
    guard let file = currentFile else { return 0 }
    let sampleRate = file.processingFormat.sampleRate
    guard sampleRate > 0,
          let nodeTime = playerNode.lastRenderTime,
          let playerTime = playerNode.playerTime(forNodeTime: nodeTime)
    else { return 0 }
    let frame = scheduledStartFrame + playerTime.sampleTime
    return Double(max(0, frame)) / sampleRate
  }

  func stop() {
    playerNode.stop()
    currentFile = nil
    scheduledStartFrame = 0
  }

  func pause() {
    playerNode.pause()
  }

  func resume() throws {
    try startEngineIfNeeded()
    playerNode.play()
  }
}
