import AVFoundation
import Flutter

/// Drop-in just_audio iOS plugin override.
/// Registers on the binary messenger so Flutter's just_audio package routes
/// all local-file playback through our AVAudioEngine graph (which includes
/// the shared AVAudioUnitEQ node from AudioEngineManager).
///
/// HOW IT WORKS
/// ─────────────
/// just_audio communicates with its native side via a MethodChannel named
/// "com.ryanheise.just_audio.methods.<playerId>" plus an EventChannel for
/// state updates. We intercept the method channel for the player and handle
/// "load", "play", "pause", "stop", and "seek" messages, routing them
/// through AudioEngineManager instead of AVQueuePlayer.
///
/// For any call we don't intercept we return FlutterMethodNotImplemented
/// so Flutter's just_audio plugin (registered after us via
/// GeneratedPluginRegistrant) handles it — HTTP/HLS streaming and everything
/// else keeps working untouched.
///
/// SUPPORTED SOURCE TYPES (local only)
/// ─────────────────────────────────────
///  - uri  (file:// or absolute path)  →  routed through AVAudioEngine + EQ
///  - everything else                  →  falls through to just_audio

@objc public class JustAudioEQPlugin: NSObject, FlutterPlugin {
  private let messenger: FlutterBinaryMessenger
  private var playerChannels: [String: FlutterMethodChannel] = [:]
  /// Track which playerIds are currently routing through AVAudioEngine
  /// so play/pause/stop/seek know whether to handle or fall through.
  private var enginePlayers: Set<String> = []

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = JustAudioEQPlugin(messenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: FlutterMethodChannel(
      name: "com.ryanheise.just_audio.methods",
      binaryMessenger: registrar.messenger()
    ))
  }

  public init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "init":
      let playerId = args["id"] as? String ?? "default"
      setupPlayerChannel(playerId: playerId)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Per-player channel

  private func setupPlayerChannel(playerId: String) {
    guard playerChannels[playerId] == nil else { return }
    let channel = FlutterMethodChannel(
      name: "com.ryanheise.just_audio.methods.\(playerId)",
      binaryMessenger: messenger
    )
    playerChannels[playerId] = channel
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handlePlayerCall(playerId: playerId, call: call, result: result)
    }
  }

  private func handlePlayerCall(
    playerId: String,
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    let args = call.arguments as? [String: Any] ?? [:]
    let isEnginePlayer = enginePlayers.contains(playerId)

    switch call.method {

    case "load":
      handleLoad(playerId: playerId, args: args, result: result)

    case "play":
      guard isEnginePlayer else { result(FlutterMethodNotImplemented); return }
      do {
        try AudioEngineManager.shared.resume()
        result(["playing": true])
      } catch {
        result(FlutterError(code: "EQ_ENGINE_ERROR", message: error.localizedDescription, details: nil))
      }

    case "pause":
      guard isEnginePlayer else { result(FlutterMethodNotImplemented); return }
      AudioEngineManager.shared.pause()
      result(nil)

    case "stop":
      guard isEnginePlayer else { result(FlutterMethodNotImplemented); return }
      AudioEngineManager.shared.stop()
      enginePlayers.remove(playerId)
      result(nil)

    case "seek":
      guard isEnginePlayer else { result(FlutterMethodNotImplemented); return }
      handleSeek(args: args, result: result)

    case "dispose":
      if isEnginePlayer {
        AudioEngineManager.shared.stop()
        enginePlayers.remove(playerId)
      }
      playerChannels.removeValue(forKey: playerId)
      result(nil)

    default:
      // setVolume, setSpeed, setLoopMode, concatenating, etc. — fall through.
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Load

  private func handleLoad(
    playerId: String,
    args: [String: Any],
    result: @escaping FlutterResult
  ) {
    guard
      let audioSource = args["audioSource"] as? [String: Any],
      let type        = audioSource["type"]  as? String,
      type == "progressive",
      let uri         = audioSource["uri"]   as? String,
      isLocalFileUri(uri)
    else {
      // Not a local file — fall through to just_audio's AVQueuePlayer.
      enginePlayers.remove(playerId)
      result(FlutterMethodNotImplemented)
      return
    }

    let path = localFilePath(from: uri)
    do {
      try AudioEngineManager.shared.playFile(at: path)
      enginePlayers.insert(playerId)

      // Return the duration map just_audio expects on a successful load.
      let url  = URL(fileURLWithPath: path)
      let file = try AVAudioFile(forReading: url)
      let sampleRate  = file.processingFormat.sampleRate
      let durationMs  = sampleRate > 0
        ? Int64((Double(file.length) / sampleRate) * 1000)
        : 0
      result(["duration": durationMs])
    } catch {
      enginePlayers.remove(playerId)
      result(FlutterError(
        code: "EQ_ENGINE_LOAD_ERROR",
        message: error.localizedDescription,
        details: ["path": path]
      ))
    }
  }

  // MARK: - Seek

  private func handleSeek(args: [String: Any], result: @escaping FlutterResult) {
    // just_audio passes position as an integer number of microseconds.
    guard let positionUs = args["position"] as? Int else {
      result(FlutterError(code: "EQ_ENGINE_SEEK_ERROR", message: "Missing position argument.", details: nil))
      return
    }
    let seconds = Double(positionUs) / 1_000_000.0
    do {
      try AudioEngineManager.shared.seek(to: seconds)
      result(nil)
    } catch {
      result(FlutterError(code: "EQ_ENGINE_SEEK_ERROR", message: error.localizedDescription, details: nil))
    }
  }

  // MARK: - Helpers

  private func isLocalFileUri(_ uri: String) -> Bool {
    uri.hasPrefix("file://") || uri.hasPrefix("/")
  }

  private func localFilePath(from uri: String) -> String {
    if uri.hasPrefix("file://") {
      return URL(string: uri)?.path ?? uri
    }
    return uri
  }
}
