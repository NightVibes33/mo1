import AVFoundation
import Flutter
import MediaPlayer
import MusicKit
import SwiftUI
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    do {
      try AVAudioSession.sharedInstance().setCategory(
        .playback,
        mode: .default,
        options: [.allowAirPlay, .allowBluetoothA2DP]
      )
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      NSLog("mo1 audio session setup failed: \(error.localizedDescription)")
    }

    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      AppleMusicLookupChannel.register(with: controller.binaryMessenger)
      EqualizerChannel.register(with: controller.binaryMessenger)
    }
    if let registrar = registrar(forPlugin: "ClassiPodNativeVisuals") {
      registrar.register(
        NativeDeviceShellViewFactory(),
        withId: "classipod/native_device_shell"
      )
      registrar.register(
        NativeClickWheelGlassViewFactory(),
        withId: "classipod/native_click_wheel_glass"
      )
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

private enum EqualizerChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "mo1/equalizer",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "setPreset" else {
        result(FlutterMethodNotImplemented)
        return
      }

      let arguments = call.arguments as? [String: Any] ?? [:]
      let presetName = arguments["presetName"] as? String ?? "off"

      if presetName == "off" || presetName == "flat" {
        result([
          "isApplied": true,
          "backend": "neutral",
          "message": "Neutral equalizer curve selected."
        ])
        return
      }

      result([
        "isApplied": false,
        "backend": "just_audio_avplayer",
        "message": "The current iOS playback backend uses just_audio/AVPlayer; " +
          "audible EQ requires an AVAudioEngine-backed player."
      ])
    }
  }
}

private enum AppleMusicLookupChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "mo1/apple_music",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard #available(iOS 15.0, *) else {
        if call.method == "authorizationStatus" || call.method == "requestAuthorization" {
          result("unsupported")
        } else if call.method == "subscriptionStatus" {
          result([
            "isSupported": false,
            "canPlayCatalogContent": false,
            "canBecomeSubscriber": false,
            "hasCloudLibraryEnabled": false
          ])
        } else if call.method == "searchSongs" || call.method == "librarySongs" {
          result([])
        } else if call.method == "playbackSnapshot" {
          result([
            "isSupported": false,
            "positionSeconds": 0,
            "durationSeconds": 0,
            "isPlaying": false,
            "playbackState": "unsupported"
          ])
        } else if call.method == "playCatalogSong" ||
                    call.method == "playCatalogQueue" ||
                    call.method == "pausePlayback" ||
                    call.method == "resumePlayback" ||
                    call.method == "seekToSeconds" {
          result(false)
        } else {
          result(FlutterMethodNotImplemented)
        }
        return
      }

      switch call.method {
      case "authorizationStatus":
        result(authorizationStatusName(MusicAuthorization.currentStatus))
      case "requestAuthorization":
        Task {
          let status = await MusicAuthorization.request()
          await MainActor.run {
            result(authorizationStatusName(status))
          }
        }
      case "subscriptionStatus":
        Task {
          do {
            let status = try await subscriptionStatus()
            await MainActor.run {
              result(status)
            }
          } catch {
            await MainActor.run {
              result(FlutterError(
                code: "APPLE_MUSIC_SUBSCRIPTION_FAILED",
                message: error.localizedDescription,
                details: nil
              ))
            }
          }
        }
      case "playCatalogSong":
        guard let arguments = call.arguments as? [String: Any],
              let catalogId = arguments["catalogId"] as? String,
              !catalogId.isEmpty else {
          result(FlutterError(
            code: "APPLE_MUSIC_BAD_ARGUMENTS",
            message: "Missing Apple Music catalog song id.",
            details: nil
          ))
          return
        }

        authorizeAppleMusicThen(result: result) {
          playCatalogQueue(
            catalogIds: [catalogId],
            startCatalogId: catalogId,
            result: result
          )
        }
      case "playCatalogQueue":
        guard let arguments = call.arguments as? [String: Any],
              let rawCatalogIds = arguments["catalogIds"] as? [String],
              let startCatalogId = arguments["startCatalogId"] as? String,
              !rawCatalogIds.isEmpty,
              !startCatalogId.isEmpty else {
          result(FlutterError(
            code: "APPLE_MUSIC_BAD_ARGUMENTS",
            message: "Missing Apple Music catalog queue.",
            details: nil
          ))
          return
        }

        authorizeAppleMusicThen(result: result) {
          playCatalogQueue(
            catalogIds: rawCatalogIds,
            startCatalogId: startCatalogId,
            result: result
          )
        }
      case "pausePlayback":
        MPMusicPlayerController.applicationQueuePlayer.pause()
        result(true)
      case "resumePlayback":
        let player = MPMusicPlayerController.applicationQueuePlayer
        guard player.nowPlayingItem != nil else {
          result(false)
          return
        }
        player.play()
        result(true)
      case "seekToSeconds":
        guard let arguments = call.arguments as? [String: Any],
              let seconds = arguments["seconds"] as? Double else {
          result(FlutterError(
            code: "APPLE_MUSIC_BAD_ARGUMENTS",
            message: "Missing Apple Music seek target.",
            details: nil
          ))
          return
        }
        result(seekToSeconds(seconds))
      case "playbackSnapshot":
        result(playbackSnapshot())
      case "librarySongs":
        let arguments = call.arguments as? [String: Any] ?? [:]
        let limit = arguments["limit"] as? Int ?? 100
        Task {
          do {
            let matches = try await librarySongs(
              limit: max(1, min(limit, 250))
            )
            await MainActor.run {
              result(matches)
            }
          } catch {
            await MainActor.run {
              result(FlutterError(
                code: "APPLE_MUSIC_LIBRARY_FAILED",
                message: error.localizedDescription,
                details: nil
              ))
            }
          }
        }
      case "searchSongs":
        guard let arguments = call.arguments as? [String: Any],
              let query = arguments["query"] as? String else {
          result(FlutterError(
            code: "APPLE_MUSIC_BAD_ARGUMENTS",
            message: "Missing Apple Music search query.",
            details: nil
          ))
          return
        }

        let limit = arguments["limit"] as? Int ?? 10
        Task {
          do {
            let matches = try await searchSongs(
              query: query,
              limit: max(1, min(limit, 25))
            )
            await MainActor.run {
              result(matches)
            }
          } catch {
            await MainActor.run {
              result(FlutterError(
                code: "APPLE_MUSIC_SEARCH_FAILED",
                message: error.localizedDescription,
                details: nil
              ))
            }
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  @available(iOS 15.0, *)
  private static func authorizationStatusName(
    _ status: MusicAuthorization.Status
  ) -> String {
    switch status {
    case .notDetermined:
      return "notDetermined"
    case .denied:
      return "denied"
    case .restricted:
      return "restricted"
    case .authorized:
      return "authorized"
    @unknown default:
      return "unknown"
    }
  }

  @available(iOS 15.0, *)
  private static func authorizeAppleMusicThen(
    result: @escaping FlutterResult,
    action: @escaping () -> Void
  ) {
    Task {
      let status = await MusicAuthorization.request()
      guard status == .authorized else {
        await MainActor.run {
          result(FlutterError(
            code: "APPLE_MUSIC_NOT_AUTHORIZED",
            message: authorizationStatusName(status),
            details: nil
          ))
        }
        return
      }
      await MainActor.run {
        action()
      }
    }
  }

  @available(iOS 15.0, *)
  private static func subscriptionStatus() async throws -> [String: Any] {
    let subscription = try await MusicSubscription.current
    return [
      "isSupported": true,
      "canPlayCatalogContent": subscription.canPlayCatalogContent,
      "canBecomeSubscriber": subscription.canBecomeSubscriber,
      "hasCloudLibraryEnabled": subscription.hasCloudLibraryEnabled
    ]
  }

  private static func playCatalogQueue(
    catalogIds: [String],
    startCatalogId: String,
    result: @escaping FlutterResult
  ) {
    var seenCatalogIds = Set<String>()
    var cleanCatalogIds: [String] = []
    for catalogId in catalogIds {
      let cleanCatalogId = catalogId.trimmingCharacters(in: .whitespacesAndNewlines)
      if cleanCatalogId.isEmpty || seenCatalogIds.contains(cleanCatalogId) {
        continue
      }
      seenCatalogIds.insert(cleanCatalogId)
      cleanCatalogIds.append(cleanCatalogId)
    }
    let cleanStartCatalogId = startCatalogId.trimmingCharacters(in: .whitespacesAndNewlines)
    if !cleanStartCatalogId.isEmpty && !seenCatalogIds.contains(cleanStartCatalogId) {
      cleanCatalogIds.insert(cleanStartCatalogId, at: 0)
    }
    guard !cleanCatalogIds.isEmpty, !cleanStartCatalogId.isEmpty else {
      result(FlutterError(
        code: "APPLE_MUSIC_BAD_ARGUMENTS",
        message: "Apple Music catalog queue is empty.",
        details: nil
      ))
      return
    }

    let player = MPMusicPlayerController.applicationQueuePlayer
    let descriptor = MPMusicPlayerStoreQueueDescriptor(storeIDs: cleanCatalogIds)
    descriptor.startItemID = cleanStartCatalogId
    player.setQueue(with: descriptor)
    player.prepareToPlay { error in
      DispatchQueue.main.async {
        if let error = error {
          result(FlutterError(
            code: "APPLE_MUSIC_PLAYBACK_FAILED",
            message: error.localizedDescription,
            details: nil
          ))
          return
        }
        player.play()
        result(true)
      }
    }
  }

  private static func playbackSnapshot() -> [String: Any] {
    let player = MPMusicPlayerController.applicationQueuePlayer
    let duration = player.nowPlayingItem?.playbackDuration ?? 0
    let safeDuration = duration.isFinite && duration > 0 ? duration : 0
    let rawPosition = player.currentPlaybackTime
    let position = rawPosition.isFinite && rawPosition > 0 ? rawPosition : 0
    let clampedPosition = safeDuration > 0 ? min(position, safeDuration) : position

    return [
      "isSupported": true,
      "positionSeconds": clampedPosition,
      "durationSeconds": safeDuration,
      "isPlaying": player.playbackState == .playing,
      "playbackState": playbackStateName(player.playbackState),
      "catalogId": player.nowPlayingItem?.playbackStoreID ?? ""
    ]
  }

  private static func seekToSeconds(_ seconds: Double) -> Bool {
    let player = MPMusicPlayerController.applicationQueuePlayer
    guard player.nowPlayingItem != nil else {
      return false
    }

    let duration = player.nowPlayingItem?.playbackDuration ?? 0
    let safeDuration = duration.isFinite && duration > 0 ? duration : seconds
    let safeSeconds = seconds.isFinite && seconds > 0 ? seconds : 0
    player.currentPlaybackTime = min(safeSeconds, safeDuration)
    return true
  }

  private static func playbackStateName(
    _ state: MPMusicPlaybackState
  ) -> String {
    switch state {
    case .stopped:
      return "stopped"
    case .playing:
      return "playing"
    case .paused:
      return "paused"
    case .interrupted:
      return "interrupted"
    case .seekingForward:
      return "seekingForward"
    case .seekingBackward:
      return "seekingBackward"
    @unknown default:
      return "unknown"
    }
  }

  @available(iOS 15.0, *)
  private static func searchSongs(
    query: String,
    limit: Int
  ) async throws -> [[String: Any]] {
    var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
    request.limit = limit
    let response = try await request.response()
    let formatter = ISO8601DateFormatter()

    return response.songs.prefix(limit).map { song in
      musicMetadataDictionary(for: song, formatter: formatter)
    }
  }

  @available(iOS 15.0, *)
  private static func librarySongs(
    limit: Int
  ) async throws -> [[String: Any]] {
    var request = MusicLibraryRequest<Song>()
    request.limit = limit
    let response = try await request.response()
    let formatter = ISO8601DateFormatter()

    return response.items.prefix(limit).map { song in
      musicMetadataDictionary(for: song, formatter: formatter)
    }
  }

  @available(iOS 15.0, *)
  private static func musicMetadataDictionary(
    for song: Song,
    formatter: ISO8601DateFormatter
  ) -> [String: Any] {
    var item: [String: Any] = [
      "id": playParameterId(for: song),
      "title": song.title,
      "artist": song.artistName
    ]

    if let albumTitle = song.albumTitle, !albumTitle.isEmpty {
      item["album"] = albumTitle
    }
    if let artworkUrl = song.artwork?.url(width: 1200, height: 1200) {
      item["artworkUrl"] = artworkUrl.absoluteString
    }
    if let catalogUrl = song.url {
      item["catalogUrl"] = catalogUrl.absoluteString
    }
    if !song.genreNames.isEmpty {
      item["genres"] = song.genreNames
    }
    if let releaseDate = song.releaseDate {
      item["releaseDate"] = formatter.string(from: releaseDate)
    }
    if let trackNumber = song.trackNumber {
      item["trackNumber"] = trackNumber
    }
    if let discNumber = song.discNumber {
      item["discNumber"] = discNumber
    }
    if let duration = song.duration {
      item["durationMs"] = Int(duration * 1000)
    }
    if let isrc = song.isrc, !isrc.isEmpty {
      item["isrc"] = isrc
    }

    return item
  }

  @available(iOS 15.0, *)
  private static func playParameterId(for song: Song) -> String {
    guard let playParameters = song.playParameters,
          let data = try? JSONEncoder().encode(playParameters),
          let json = try? JSONSerialization.jsonObject(with: data),
          let dictionary = json as? [String: Any],
          let id = dictionary["id"] as? String,
          !id.isEmpty else {
      return song.id.rawValue
    }
    return id
  }
}

private final class NativeDeviceShellViewFactory: NSObject, FlutterPlatformViewFactory {
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    NativeDeviceShellPlatformView(frame: frame, arguments: args)
  }
}

private final class NativeClickWheelGlassViewFactory: NSObject, FlutterPlatformViewFactory {
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    NativeClickWheelGlassPlatformView(frame: frame, arguments: args)
  }
}

private final class NativeDeviceShellPlatformView: NSObject, FlutterPlatformView {
  private let containerView: UIView
  private let hostingController: UIHostingController<NativeDeviceShellRootView>

  init(frame: CGRect, arguments args: Any?) {
    let arguments = args as? [String: Any] ?? [:]
    let config = NativeDeviceShellConfig(arguments: arguments)
    let container = UIView(frame: frame)
    container.backgroundColor = .clear
    container.isOpaque = false
    container.clipsToBounds = false
    container.isUserInteractionEnabled = false

    let host = UIHostingController(rootView: NativeDeviceShellRootView(config: config))
    host.view.backgroundColor = .clear
    host.view.isOpaque = false
    host.view.isUserInteractionEnabled = false
    host.view.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(host.view)
    NSLayoutConstraint.activate([
      host.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      host.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      host.view.topAnchor.constraint(equalTo: container.topAnchor),
      host.view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
    ])

    containerView = container
    hostingController = host
    super.init()
  }

  func view() -> UIView {
    containerView
  }
}

private final class NativeClickWheelGlassPlatformView: NSObject, FlutterPlatformView {
  private let containerView: UIView
  private let hostingController: UIHostingController<NativeClickWheelRootView>

  init(frame: CGRect, arguments args: Any?) {
    let arguments = args as? [String: Any] ?? [:]
    let config = NativeClickWheelConfig(arguments: arguments)
    let container = UIView(frame: frame)
    container.backgroundColor = .clear
    container.isOpaque = false
    container.clipsToBounds = false
    container.isUserInteractionEnabled = false

    let host = UIHostingController(rootView: NativeClickWheelRootView(config: config))
    host.view.backgroundColor = .clear
    host.view.isOpaque = false
    host.view.isUserInteractionEnabled = false
    host.view.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(host.view)
    NSLayoutConstraint.activate([
      host.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      host.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      host.view.topAnchor.constraint(equalTo: container.topAnchor),
      host.view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
    ])

    containerView = container
    hostingController = host
    super.init()
  }

  func view() -> UIView {
    containerView
  }
}

private struct NativeDeviceShellConfig {
  let frameStartColor: Color
  let frameEndColor: Color
  let isDark: Bool
  let topContentInset: CGFloat
  let bottomContentInset: CGFloat
  let bodyRadius: CGFloat

  init(arguments: [String: Any]) {
    frameStartColor = arguments.colorValue("frameStartColor", fallback: 0xFFEDEEF1)
    frameEndColor = arguments.colorValue("frameEndColor", fallback: 0xFFD6D8DE)
    isDark = arguments.boolValue("isDark", fallback: false)
    topContentInset = arguments.cgFloatValue("topContentInset", fallback: 72)
    bottomContentInset = arguments.cgFloatValue("bottomContentInset", fallback: 24)
    bodyRadius = arguments.cgFloatValue("bodyRadius", fallback: 48)
  }
}

private struct NativeClickWheelConfig {
  let labelColor: Color
  let iconColor: Color
  let centerStartColor: Color
  let centerEndColor: Color
  let isDark: Bool
  let centerSizeRatio: CGFloat
  let menuText: String

  init(arguments: [String: Any]) {
    labelColor = arguments.colorValue("labelColor", fallback: 0xFFFFFFFF)
    iconColor = arguments.colorValue("iconColor", fallback: 0xFFFFFFFF)
    centerStartColor = arguments.colorValue("centerStartColor", fallback: 0xFFF9F9F9)
    centerEndColor = arguments.colorValue("centerEndColor", fallback: 0xFFE8E8E8)
    isDark = arguments.boolValue("isDark", fallback: false)
    centerSizeRatio = arguments.cgFloatValue("centerSizeRatio", fallback: 0.34)
    menuText = arguments.stringValue("menuText", fallback: "MENU")
  }
}

private struct NativeDeviceShellRootView: View {
  let config: NativeDeviceShellConfig

  var body: some View {
    GeometryReader { proxy in
      if #available(iOS 26.0, *) {
        NativeDeviceShellGlassView(config: config, size: proxy.size)
      } else {
        NativeDeviceShellFallbackView(config: config, size: proxy.size)
      }
    }
    .allowsHitTesting(false)
  }
}

@available(iOS 26.0, *)
private struct NativeDeviceShellGlassView: View {
  let config: NativeDeviceShellConfig
  let size: CGSize

  var body: some View {
    let radius = max(config.bodyRadius, 36)
    GlassEffectContainer(spacing: 28) {
      RoundedRectangle(cornerRadius: radius, style: .continuous)
        .fill(shellGradient)
        .overlay(shellShine(radius: radius))
        .overlay(shellStroke(radius: radius))
        .shadow(color: .black.opacity(config.isDark ? 0.36 : 0.20), radius: 38, x: 0, y: 22)
        .glassEffect(.regular.tint(Color.white.opacity(config.isDark ? 0.06 : 0.14)), in: .rect(cornerRadius: radius))
        .frame(width: size.width, height: size.height)
    }
  }

  private var shellGradient: LinearGradient {
    LinearGradient(
      stops: [
        .init(color: config.frameStartColor.opacity(config.isDark ? 0.46 : 0.72), location: 0.0),
        .init(color: Color.white.opacity(config.isDark ? 0.08 : 0.30), location: 0.20),
        .init(color: config.frameEndColor.opacity(config.isDark ? 0.52 : 0.76), location: 1.0)
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  private func shellShine(radius: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
      .fill(
        LinearGradient(
          stops: [
            .init(color: Color.white.opacity(config.isDark ? 0.18 : 0.52), location: 0.0),
            .init(color: Color.white.opacity(config.isDark ? 0.06 : 0.14), location: 0.36),
            .init(color: Color.clear, location: 0.62)
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .blendMode(.screen)
  }

  private func shellStroke(radius: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
      .strokeBorder(Color.white.opacity(config.isDark ? 0.34 : 0.62), lineWidth: 1.2)
      .overlay(
        RoundedRectangle(cornerRadius: max(radius - 10, 24), style: .continuous)
          .stroke(Color.white.opacity(config.isDark ? 0.08 : 0.24), lineWidth: 0.7)
          .padding(10)
      )
  }
}

private struct NativeDeviceShellFallbackView: View {
  let config: NativeDeviceShellConfig
  let size: CGSize

  var body: some View {
    let radius = max(config.bodyRadius, 36)
    RoundedRectangle(cornerRadius: radius, style: .continuous)
      .fill(.ultraThinMaterial)
      .overlay(
        LinearGradient(
          colors: [
            config.frameStartColor.opacity(config.isDark ? 0.24 : 0.46),
            config.frameEndColor.opacity(config.isDark ? 0.30 : 0.54)
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .overlay(
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .strokeBorder(Color.white.opacity(config.isDark ? 0.32 : 0.58), lineWidth: 1.1)
      )
      .shadow(color: .black.opacity(config.isDark ? 0.34 : 0.20), radius: 34, x: 0, y: 20)
      .frame(width: size.width, height: size.height)
  }
}

private struct NativeClickWheelRootView: View {
  let config: NativeClickWheelConfig

  var body: some View {
    GeometryReader { proxy in
      let side = max(1, min(proxy.size.width, proxy.size.height))
      ZStack {
        if #available(iOS 26.0, *) {
          NativeClickWheelGlassSurface(config: config, size: side)
        } else {
          NativeClickWheelFallbackSurface(config: config, size: side)
        }
        NativeWheelLabels(config: config, size: side)
      }
      .frame(width: side, height: side)
      .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
    }
    .allowsHitTesting(false)
  }
}

@available(iOS 26.0, *)
private struct NativeClickWheelGlassSurface: View {
  let config: NativeClickWheelConfig
  let size: CGFloat

  var body: some View {
    let edge = size / 2
    let centerSize = max(54, size * min(max(config.centerSizeRatio, 0.22), 0.42))
    GlassEffectContainer(spacing: 18) {
      ZStack {
        Circle()
          .fill(wheelFill)
          .overlay(wheelHighlights)
          .overlay(Circle().strokeBorder(Color.white.opacity(0.74), lineWidth: 1.15))
          .shadow(color: .black.opacity(config.isDark ? 0.34 : 0.22), radius: 26, x: 0, y: 15)
          .glassEffect(.regular.tint(Color.white.opacity(config.isDark ? 0.05 : 0.12)), in: .rect(cornerRadius: edge))
        NativeWheelRing(size: size, isDark: config.isDark)
        NativeWheelCenterButton(config: config, centerSize: centerSize)
      }
      .frame(width: size, height: size)
    }
  }

  private var wheelFill: RadialGradient {
    RadialGradient(
      stops: [
        .init(color: Color.white.opacity(config.isDark ? 0.18 : 0.42), location: 0.0),
        .init(color: Color.white.opacity(config.isDark ? 0.08 : 0.24), location: 0.38),
        .init(color: Color.white.opacity(config.isDark ? 0.03 : 0.10), location: 0.72),
        .init(color: Color.white.opacity(config.isDark ? 0.12 : 0.32), location: 1.0)
      ],
      center: .topLeading,
      startRadius: 2,
      endRadius: size
    )
  }

  private var wheelHighlights: some View {
    Circle()
      .fill(
        LinearGradient(
          stops: [
            .init(color: Color.white.opacity(0.62), location: 0.0),
            .init(color: Color.white.opacity(0.14), location: 0.28),
            .init(color: Color.clear, location: 0.62),
            .init(color: Color.black.opacity(config.isDark ? 0.05 : 0.09), location: 1.0)
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .blendMode(.screen)
  }
}

private struct NativeClickWheelFallbackSurface: View {
  let config: NativeClickWheelConfig
  let size: CGFloat

  var body: some View {
    ZStack {
      Circle()
        .fill(.ultraThinMaterial)
        .overlay(
          Circle()
            .fill(Color.white.opacity(config.isDark ? 0.10 : 0.30))
        )
        .overlay(Circle().strokeBorder(Color.white.opacity(0.68), lineWidth: 1.1))
        .shadow(color: .black.opacity(config.isDark ? 0.32 : 0.20), radius: 24, x: 0, y: 14)
      NativeWheelRing(size: size, isDark: config.isDark)
      NativeWheelCenterButton(
        config: config,
        centerSize: max(54, size * min(max(config.centerSizeRatio, 0.22), 0.42))
      )
    }
    .frame(width: size, height: size)
  }
}

private struct NativeWheelRing: View {
  let size: CGFloat
  let isDark: Bool

  var body: some View {
    ZStack {
      Circle()
        .stroke(Color.white.opacity(isDark ? 0.16 : 0.32), lineWidth: 0.8)
        .padding(size * 0.12)
      Circle()
        .stroke(Color.white.opacity(isDark ? 0.10 : 0.20), lineWidth: 0.7)
        .padding(size * 0.26)
      Circle()
        .stroke(Color.black.opacity(isDark ? 0.10 : 0.05), lineWidth: 0.8)
        .padding(size * 0.018)
    }
  }
}

private struct NativeWheelCenterButton: View {
  let config: NativeClickWheelConfig
  let centerSize: CGFloat

  var body: some View {
    Circle()
      .fill(
        LinearGradient(
          colors: [config.centerStartColor, config.centerEndColor],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .overlay(Circle().strokeBorder(Color.white.opacity(0.56), lineWidth: 1.1))
      .shadow(color: .black.opacity(config.isDark ? 0.26 : 0.18), radius: 14, x: 0, y: 7)
      .modifier(NativeCenterGlassModifier(cornerRadius: centerSize / 2))
      .frame(width: centerSize, height: centerSize)
  }
}

private struct NativeCenterGlassModifier: ViewModifier {
  let cornerRadius: CGFloat

  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      content.glassEffect(.regular.tint(Color.white.opacity(0.12)).interactive(), in: .rect(cornerRadius: cornerRadius))
    } else {
      content
    }
  }
}

private struct NativeWheelLabels: View {
  let config: NativeClickWheelConfig
  let size: CGFloat

  var body: some View {
    ZStack {
      Text(config.menuText)
        .font(.system(size: max(17, size * 0.098), weight: .bold, design: .rounded))
        .foregroundStyle(config.labelColor)
        .shadow(color: .white.opacity(0.28), radius: 4, x: 0, y: 0)
        .position(x: size / 2, y: size * 0.16)
      Image(systemName: "backward.end.fill")
        .font(.system(size: max(16, size * 0.052), weight: .bold))
        .foregroundStyle(config.iconColor)
        .position(x: size * 0.22, y: size * 0.50)
      Image(systemName: "forward.end.fill")
        .font(.system(size: max(16, size * 0.052), weight: .bold))
        .foregroundStyle(config.iconColor)
        .position(x: size * 0.78, y: size * 0.50)
      Image(systemName: "playpause.fill")
        .font(.system(size: max(16, size * 0.052), weight: .bold))
        .foregroundStyle(config.iconColor)
        .position(x: size / 2, y: size * 0.84)
    }
    .frame(width: size, height: size)
  }
}

private extension Dictionary where Key == String, Value == Any {
  func colorValue(_ key: String, fallback: UInt32) -> Color {
    Color(argb: uint32Value(key, fallback: fallback))
  }

  func uint32Value(_ key: String, fallback: UInt32) -> UInt32 {
    guard let value = self[key] else {
      return fallback
    }
    if let number = value as? NSNumber {
      return UInt32(truncating: number)
    }
    if let int = value as? Int {
      return UInt32(truncatingIfNeeded: int)
    }
    if let string = value as? String, let parsed = UInt32(string) {
      return parsed
    }
    return fallback
  }

  func boolValue(_ key: String, fallback: Bool) -> Bool {
    if let value = self[key] as? Bool {
      return value
    }
    if let number = self[key] as? NSNumber {
      return number.boolValue
    }
    return fallback
  }

  func cgFloatValue(_ key: String, fallback: CGFloat) -> CGFloat {
    if let number = self[key] as? NSNumber {
      return CGFloat(truncating: number)
    }
    if let double = self[key] as? Double {
      return CGFloat(double)
    }
    if let int = self[key] as? Int {
      return CGFloat(int)
    }
    return fallback
  }

  func stringValue(_ key: String, fallback: String) -> String {
    if let value = self[key] as? String, !value.isEmpty {
      return value
    }
    return fallback
  }
}

private extension Color {
  init(argb: UInt32) {
    let alpha = Double((argb >> 24) & 0xFF) / 255.0
    let red = Double((argb >> 16) & 0xFF) / 255.0
    let green = Double((argb >> 8) & 0xFF) / 255.0
    let blue = Double(argb & 0xFF) / 255.0
    self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
  }
}
