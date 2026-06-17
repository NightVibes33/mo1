import AVFoundation

/// Shared singleton that owns the AVAudioEngine graph.
/// Both the EqualizerChannel (MethodChannel) and LocalAudioEnginePlayer
/// reference this same instance so EQ band changes immediately affect playback.
final class AudioEngineManager {
  static let shared = AudioEngineManager()

  let engine     = AVAudioEngine()
  let playerNode = AVAudioPlayerNode()
  let eqNode: AVAudioUnitEQ

  private var isGraphConnected = false
  private var currentFile: AVAudioFile?

  private init() {
    // 10-band EQ: 32 Hz … 16 kHz
    eqNode = AVAudioUnitEQ(numberOfBands: 10)
    let frequencies: [Float] = [32, 64, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
    for (i, freq) in frequencies.enumerated() {
      let band            = eqNode.bands[i]
      band.filterType     = .parametric
      band.frequency      = freq
      band.bandwidth      = 1.0
      band.gain           = 0.0
      band.bypass         = false
    }
    buildGraph()
  }

  // MARK: - Graph

  private func buildGraph() {
    guard !isGraphConnected else { return }
    engine.attach(playerNode)
    engine.attach(eqNode)
    engine.connect(playerNode,  to: eqNode,              format: nil)
    engine.connect(eqNode,      to: engine.mainMixerNode, format: nil)
    isGraphConnected = true
  }

  func startEngineIfNeeded() throws {
    guard !engine.isRunning else { return }
    try engine.start()
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

  /// Load and play a local file through the EQ graph.
  func playFile(at path: String) throws {
    let url  = URL(fileURLWithPath: path)
    let file = try AVAudioFile(forReading: url)
    currentFile = file

    // Re-connect with the file's processing format for accurate sample-rate matching.
    let format = file.processingFormat
    engine.disconnectNodeOutput(playerNode)
    engine.disconnectNodeOutput(eqNode)
    engine.connect(playerNode,  to: eqNode,              format: format)
    engine.connect(eqNode,      to: engine.mainMixerNode, format: format)

    playerNode.stop()
    try startEngineIfNeeded()
    playerNode.scheduleFile(file, at: nil, completionHandler: nil)
    playerNode.play()
  }

  func stop() {
    playerNode.stop()
  }

  func pause() {
    playerNode.pause()
  }

  func resume() throws {
    try startEngineIfNeeded()
    playerNode.play()
  }
}
