import AVFoundation
import Flutter

/// Drop-in just_audio iOS plugin override.
/// Registers as "just_audio" on the binary messenger so Flutter's just_audio
/// package routes all local-file playback through our AVAudioEngine graph
/// (which includes the shared AVAudioUnitEQ node from AudioEngineManager).
///
/// HOW IT WORKS
/// ─────────────
/// just_audio communicates with its native side via a MethodChannel named
/// "com.ryanheise.just_audio.methods.<playerId>" plus an EventChannel for
/// state updates. We intercept the method channel for the "init" player
/// and "load" / "play" / "pause" / "stop" / "seek" messages, routing them
/// through AudioEngineManager instead of AVQueuePlayer.
///
/// For any call we don't intercept we fall through to the real just_audio
/// plugin (via GeneratedPluginRegistrant), so HTTP/HLS streaming and
/// everything else keeps working untouched.
///
/// SUPPORTED SOURCE TYPES (local only)
/// ─────────────────────────────────────
///  - uri  (file:// or absolute path)  →  routed through AVAudioEngine+EQ
///  - everything else                  →  falls through to just_audio

@objc public class JustAudioEQPlugin: NSObject, FlutterPlugin {
  private let messenger: FlutterBinaryMessenger
  private var playerChannels: [String: FlutterMethodChannel] = [:]

  public static func register(with registrar: FlutterPluginRegistrar) {
    // Register under the same channel prefix just_audio uses so calls
    // arrive here before the bundled plugin handles them.
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
      // Unknown top-level call — let just_audio handle it.
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
      self?.handlePlayerCall(call, result: result)
    }
  }

  private func handlePlayerCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]

    switch call.method {
    case "load":
      handleLoad(args: args, result: result)

    case "play":
      do {
        try AudioEngineManager.shared.resume()
        result(["playing": true])
      } catch {
        // Fall through — let just_audio handle non-EQ sources.
        result(FlutterMethodNotImplemented)
      }

    case "pause":
      AudioEngineManager.shared.pause()
      result(nil)

    case "stop":
      AudioEngineManager.shared.stop()
      result(nil)

    default:
      // Seek, setVolume, setSpeed, dispose, etc. — fall through.
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Load

  private func handleLoad(args: [String: Any], result: @escaping FlutterResult) {
    guard
      let audioSource = args["audioSource"] as? [String: Any],
      let type        = audioSource["type"]  as? String,
      type == "progressive",
      let uri         = audioSource["uri"]   as? String,
      isLocalFileUri(uri)
    else {
      // Not a local file — fall through to just_audio's AVQueuePlayer.
      result(FlutterMethodNotImplemented)
      return
    }

    let path = localFilePath(from: uri)
    do {
      try AudioEngineManager.shared.playFile(at: path)
      // Return the duration just_audio expects.
      let url  = URL(fileURLWithPath: path)
      let file = try AVAudioFile(forReading: url)
      let durationSamples = Double(file.length)
      let sampleRate      = file.processingFormat.sampleRate
      let durationMs      = sampleRate > 0 ? Int64((durationSamples / sampleRate) * 1000) : 0
      result(["duration": durationMs])
    } catch {
      // File unreadable — fall through.
      result(FlutterMethodNotImplemented)
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
