import AVFoundation
import Flutter
import MediaPlayer
import MusicKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    NativeCrashLogWriter.install()

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
      NativeColorPickerChannel.register(with: controller.binaryMessenger)
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

private enum NativeColorPickerChannel {
  static var activeSession: NativeColorPickerSession?

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "mo1/color_picker",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "pickColor" else {
        result(FlutterMethodNotImplemented)
        return
      }

      guard let rootViewController = UIApplication.shared.topMostViewController() else {
        result(FlutterError(
          code: "COLOR_PICKER_UNAVAILABLE",
          message: "Unable to present the native color picker.",
          details: nil
        ))
        return
      }

      let arguments = call.arguments as? [String: Any] ?? [:]
      let initialHex = arguments["initialHex"] as? String
      let session = NativeColorPickerSession(
        presenter: rootViewController,
        initialHex: initialHex,
        result: result
      )
      activeSession = session
      session.present()
    }
  }
}

private final class NativeColorPickerSession: NSObject,
  UIColorPickerViewControllerDelegate,
  UIAdaptivePresentationControllerDelegate {
  private weak var presenter: UIViewController?
  private let result: FlutterResult
  private let initialHex: String?
  private var didFinish = false
  private let pickerViewController = UIColorPickerViewController()

  init(
    presenter: UIViewController,
    initialHex: String?,
    result: @escaping FlutterResult
  ) {
    self.presenter = presenter
    self.initialHex = initialHex
    self.result = result
    super.init()
  }

  func present() {
    pickerViewController.delegate = self
    pickerViewController.supportsAlpha = false
    pickerViewController.modalPresentationStyle = .formSheet
    pickerViewController.presentationController?.delegate = self

    if let initialHex,
       let initialColor = Self.color(from: initialHex) {
      pickerViewController.selectedColor = initialColor
    }

    presenter?.present(pickerViewController, animated: true)
  }

  func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
    finish(with: viewController.selectedColor)
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    finish(with: pickerViewController.selectedColor)
  }

  private func finish(with color: UIColor) {
    guard !didFinish else {
      return
    }
    didFinish = true
    NativeColorPickerChannel.activeSession = nil
    result(Self.hexString(from: color))
  }

  private static func color(from hex: String) -> UIColor? {
    let normalized = hex.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalized.count == 6, let value = Int(normalized, radix: 16) else {
      return nil
    }

    let red = CGFloat((value >> 16) & 0xFF) / 255.0
    let green = CGFloat((value >> 8) & 0xFF) / 255.0
    let blue = CGFloat(value & 0xFF) / 255.0
    return UIColor(red: red, green: green, blue: blue, alpha: 1)
  }

  private static func hexString(from color: UIColor) -> String {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

    let rgb = (Int(round(red * 255.0)) << 16) |
      (Int(round(green * 255.0)) << 8) |
      Int(round(blue * 255.0))
    return String(format: "#%06X", rgb)
  }
}

private extension UIApplication {
  func topMostViewController(
    base: UIViewController? = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)?
      .rootViewController
  ) -> UIViewController? {
    if let navigationController = base as? UINavigationController {
      return topMostViewController(base: navigationController.visibleViewController)
    }
    if let tabBarController = base as? UITabBarController,
       let selectedViewController = tabBarController.selectedViewController {
      return topMostViewController(base: selectedViewController)
    }
    if let presentedViewController = base?.presentedViewController {
      return topMostViewController(base: presentedViewController)
    }
    return base
  }
}
private enum AppleMusicLookupChannel {
  private enum PlaybackBackend {
    case mediaPlayer
    case musicKit
  }

  private enum AppleMusicPlaybackError: Error {
    case emptyQueue
  }

  private static var playbackBackend = PlaybackBackend.mediaPlayer
  private static var transitionStyle = "off"
  private static var transitionDurationSeconds: TimeInterval = 6

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
                    call.method == "seekToSeconds" ||
                    call.method == "setTransitionStyle" {
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

        updateTransitionConfiguration(arguments: arguments)
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

        updateTransitionConfiguration(arguments: arguments)
        authorizeAppleMusicThen(result: result) {
          playCatalogQueue(
            catalogIds: rawCatalogIds,
            startCatalogId: startCatalogId,
            result: result
          )
        }
      case "setTransitionStyle":
        let arguments = call.arguments as? [String: Any] ?? [:]
        updateTransitionConfiguration(arguments: arguments)
        result(applyCurrentMusicKitTransitionIfAvailable())
      case "pausePlayback":
        if playbackBackend == .musicKit {
          pauseMusicKitPlayback()
          result(true)
          return
        }
        MPMusicPlayerController.applicationQueuePlayer.pause()
        result(true)
      case "resumePlayback":
        if playbackBackend == .musicKit {
          resumeMusicKitPlayback(result: result)
          return
        }
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
        guard #available(iOS 16.0, *) else {
          result([])
          return
        }
        let arguments = call.arguments as? [String: Any] ?? [:]
        let requestedLimit = arguments["limit"] as? Int ?? 0
        Task {
          do {
            let matches = try await librarySongs(
              limit: normalizedLibraryLimit(requestedLimit)
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
    let cleanCatalogIds = normalizedCatalogIds(
      catalogIds: catalogIds,
      startCatalogId: startCatalogId
    )
    let cleanStartCatalogId = startCatalogId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanCatalogIds.isEmpty, !cleanStartCatalogId.isEmpty else {
      result(FlutterError(
        code: "APPLE_MUSIC_BAD_ARGUMENTS",
        message: "Apple Music catalog queue is empty.",
        details: nil
      ))
      return
    }

    if shouldUseMusicKitTransition() {
      Task {
        do {
          try await playCatalogQueueWithMusicKit(
            catalogIds: cleanCatalogIds,
            startCatalogId: cleanStartCatalogId
          )
          await MainActor.run {
            result(true)
          }
        } catch {
          await MainActor.run {
            playCatalogQueueWithMediaPlayer(
              catalogIds: cleanCatalogIds,
              startCatalogId: cleanStartCatalogId,
              result: result
            )
          }
        }
      }
      return
    }

    playCatalogQueueWithMediaPlayer(
      catalogIds: cleanCatalogIds,
      startCatalogId: cleanStartCatalogId,
      result: result
    )
  }

  private static func normalizedCatalogIds(
    catalogIds: [String],
    startCatalogId: String
  ) -> [String] {
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
    return cleanCatalogIds
  }

  private static func playCatalogQueueWithMediaPlayer(
    catalogIds: [String],
    startCatalogId: String,
    result: @escaping FlutterResult
  ) {
    if #available(iOS 15.0, *) {
      ApplicationMusicPlayer.shared.stop()
    }
    let player = MPMusicPlayerController.applicationQueuePlayer
    if let mediaDescriptor = mediaItemQueueDescriptor(
      catalogIds: catalogIds,
      startCatalogId: startCatalogId
    ) {
      player.setQueue(with: mediaDescriptor)
      player.prepareToPlay { error in
        DispatchQueue.main.async {
          if let error = error {
            result(FlutterError(
              code: "APPLE_MUSIC_PLAYBACK_FAILED",
              message: error.localizedDescription,
              details: ["backend": "mediaLibrary"]
            ))
            return
          }
          playbackBackend = .mediaPlayer
          player.play()
          result(true)
        }
      }
      return
    }

    let descriptor = MPMusicPlayerStoreQueueDescriptor(storeIDs: catalogIds)
    descriptor.startItemID = startCatalogId
    player.setQueue(with: descriptor)
    player.prepareToPlay { error in
      DispatchQueue.main.async {
        if let error = error {
          result(FlutterError(
            code: "APPLE_MUSIC_PLAYBACK_FAILED",
            message: error.localizedDescription,
            details: ["backend": "storeQueue"]
          ))
          return
        }
        playbackBackend = .mediaPlayer
        player.play()
        result(true)
      }
    }
  }

  @available(iOS 15.0, *)
  @MainActor
  private static func playCatalogQueueWithMusicKit(
    catalogIds: [String],
    startCatalogId: String
  ) async throws {
    let songs = try await catalogSongs(catalogIds: catalogIds)
    guard !songs.isEmpty else {
      throw AppleMusicPlaybackError.emptyQueue
    }

    let startSong = songs.first { song in
      playParameterId(for: song) == startCatalogId || song.id.rawValue == startCatalogId
    } ?? songs[0]

    let player = ApplicationMusicPlayer.shared
    MPMusicPlayerController.applicationQueuePlayer.stop()
    applyCurrentMusicKitTransitionIfAvailable()
    player.queue = ApplicationMusicPlayer.Queue(for: songs, startingAt: startSong)
    try await player.prepareToPlay()
    try await player.play()
    playbackBackend = .musicKit
  }

  @available(iOS 15.0, *)
  private static func catalogSongs(catalogIds: [String]) async throws -> [Song] {
    let ids = catalogIds.map { MusicItemID($0) }
    var request = MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: ids)
    request.limit = max(1, min(ids.count, 300))
    let response = try await request.response()
    let foundSongs = Array(response.items)
    return catalogIds.compactMap { catalogId in
      foundSongs.first { song in
        playParameterId(for: song) == catalogId || song.id.rawValue == catalogId
      }
    }
  }

  private static func updateTransitionConfiguration(arguments: [String: Any]) {
    if let style = arguments["transitionStyle"] as? String {
      transitionStyle = style
    }
    if let seconds = arguments["transitionDurationSeconds"] as? Double,
       seconds.isFinite {
      transitionDurationSeconds = max(1, min(seconds, 12))
    } else if let seconds = arguments["transitionDurationSeconds"] as? Int {
      transitionDurationSeconds = TimeInterval(max(1, min(seconds, 12)))
    }
  }

  private static func shouldUseMusicKitTransition() -> Bool {
    guard transitionStyle != "off" else {
      return false
    }
    if #available(iOS 18.0, *) {
      return true
    }
    return false
  }

  @discardableResult
  private static func applyCurrentMusicKitTransitionIfAvailable() -> Bool {
    if #available(iOS 18.0, *) {
      applyCurrentMusicKitTransition()
      return true
    }
    return false
  }

  @available(iOS 18.0, *)
  private static func applyCurrentMusicKitTransition() {
    let player = ApplicationMusicPlayer.shared
    switch transitionStyle {
    case "crossfade":
      player.transition = .crossfade(duration: transitionDurationSeconds)
    case "autoMix":
      player.transition = .crossfade(duration: nil)
    default:
      player.transition = .none
    }
  }

  @available(iOS 15.0, *)
  private static func pauseMusicKitPlayback() {
    ApplicationMusicPlayer.shared.pause()
  }

  @available(iOS 15.0, *)
  private static func resumeMusicKitPlayback(result: @escaping FlutterResult) {
    Task {
      do {
        try await ApplicationMusicPlayer.shared.play()
        await MainActor.run {
          result(true)
        }
      } catch {
        await MainActor.run {
          result(FlutterError(
            code: "APPLE_MUSIC_PLAYBACK_FAILED",
            message: error.localizedDescription,
            details: ["backend": "musicKit"]
          ))
        }
      }
    }
  }

  private static func playbackSnapshot() -> [String: Any] {
    if playbackBackend == .musicKit, #available(iOS 15.0, *) {
      return musicKitPlaybackSnapshot()
    }

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

  @available(iOS 15.0, *)
  private static func musicKitPlaybackSnapshot() -> [String: Any] {
    let player = ApplicationMusicPlayer.shared
    let rawPosition = player.playbackTime
    let position = rawPosition.isFinite && rawPosition > 0 ? rawPosition : 0
    var duration: TimeInterval = 0
    var catalogId = ""
    if let currentEntry = player.queue.currentEntry {
      switch currentEntry.item {
      case .song(let song):
        if let songDuration = song.duration, songDuration.isFinite && songDuration > 0 {
          duration = songDuration
        }
        catalogId = playParameterId(for: song)
      default:
        break
      }
    }
    let clampedPosition = duration > 0 ? min(position, duration) : position
    let playbackStatus = player.state.playbackStatus

    return [
      "isSupported": true,
      "positionSeconds": clampedPosition,
      "durationSeconds": duration,
      "isPlaying": playbackStatus == .playing,
      "playbackState": String(describing: playbackStatus),
      "catalogId": catalogId
    ]
  }

  private static func seekToSeconds(_ seconds: Double) -> Bool {
    if playbackBackend == .musicKit, #available(iOS 15.0, *) {
      return seekMusicKitToSeconds(seconds)
    }

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

  @available(iOS 15.0, *)
  private static func seekMusicKitToSeconds(_ seconds: Double) -> Bool {
    guard ApplicationMusicPlayer.shared.queue.currentEntry != nil else {
      return false
    }
    ApplicationMusicPlayer.shared.playbackTime = seconds.isFinite && seconds > 0 ? seconds : 0
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
  private static func normalizedLibraryLimit(_ limit: Int) -> Int {
    if limit <= 0 {
      return 0
    }
    return max(1, min(limit, 10000))
  }

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

  @available(iOS 16.0, *)
  private static func librarySongs(
    limit: Int
  ) async throws -> [[String: Any]] {
    let mediaStatus = await requestMediaLibraryAuthorization()
    if mediaStatus == .authorized {
      let mediaMatches = mediaLibrarySongs(limit: limit)
      if !mediaMatches.isEmpty {
        return mediaMatches
      }
    }

    var request = MusicLibraryRequest<Song>()
    let effectiveLimit = limit > 0 ? limit : 10000
    request.limit = effectiveLimit
    let response = try await request.response()
    let formatter = ISO8601DateFormatter()

    if limit > 0 {
      return response.items.prefix(limit).map { song in
        musicMetadataDictionary(for: song, formatter: formatter)
      }
    }

    return response.items.map { song in
      musicMetadataDictionary(for: song, formatter: formatter)
    }
  }

  private static func requestMediaLibraryAuthorization() async -> MPMediaLibraryAuthorizationStatus {
    let currentStatus = MPMediaLibrary.authorizationStatus()
    if currentStatus != .notDetermined {
      return currentStatus
    }

    return await withCheckedContinuation { continuation in
      MPMediaLibrary.requestAuthorization { status in
        continuation.resume(returning: status)
      }
    }
  }

  private static func mediaLibrarySongs(limit: Int) -> [[String: Any]] {
    guard let items = MPMediaQuery.songs().items else {
      return []
    }

    var seenIds = Set<String>()
    var results: [[String: Any]] = []
    for item in items {
      guard let id = preferredMediaItemIdentifier(item),
            !seenIds.contains(id) else {
        continue
      }
      seenIds.insert(id)
      results.append(mediaMetadataDictionary(for: item, identifier: id))
      if limit > 0 && results.count >= limit {
        break
      }
    }
    return results
  }

  private static func mediaItemQueueDescriptor(
    catalogIds: [String],
    startCatalogId: String
  ) -> MPMusicPlayerMediaItemQueueDescriptor? {
    guard MPMediaLibrary.authorizationStatus() == .authorized,
          let libraryItems = MPMediaQuery.songs().items,
          !libraryItems.isEmpty else {
      return nil
    }

    let requestedIds = catalogIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard !requestedIds.isEmpty else {
      return nil
    }

    let matchedItems = requestedIds.compactMap { requestedId in
      libraryItems.first { item in
        mediaItemIdentifiers(item).contains(requestedId)
      }
    }
    guard !matchedItems.isEmpty else {
      return nil
    }

    let collection = MPMediaItemCollection(items: matchedItems)
    let descriptor = MPMusicPlayerMediaItemQueueDescriptor(itemCollection: collection)
    descriptor.startItem = matchedItems.first { item in
      mediaItemIdentifiers(item).contains(startCatalogId)
    } ?? matchedItems.first
    return descriptor
  }

  private static func mediaMetadataDictionary(
    for item: MPMediaItem,
    identifier: String
  ) -> [String: Any] {
    var result: [String: Any] = [
      "id": identifier,
      "title": item.title ?? "",
      "artist": item.artist ?? item.albumArtist ?? ""
    ]

    if let album = item.albumTitle, !album.isEmpty {
      result["album"] = album
    }
    if let albumArtist = item.albumArtist, !albumArtist.isEmpty {
      result["albumArtist"] = albumArtist
    }
    if let genre = item.genre, !genre.isEmpty {
      result["genres"] = [genre]
    }
    if item.albumTrackNumber > 0 {
      result["trackNumber"] = item.albumTrackNumber
    }
    if item.albumTrackCount > 0 {
      result["trackCount"] = item.albumTrackCount
    }
    if item.discNumber > 0 {
      result["discNumber"] = item.discNumber
    }
    if item.playbackDuration.isFinite && item.playbackDuration > 0 {
      result["durationMs"] = Int(item.playbackDuration * 1000)
    }
    if let artworkPath = cachedArtworkPath(for: item, identifier: identifier) {
      result["artworkUrl"] = artworkPath
    }

    return result
  }

  private static func preferredMediaItemIdentifier(_ item: MPMediaItem) -> String? {
    for identifier in mediaItemIdentifiers(item) {
      if !identifier.isEmpty && identifier != "0" {
        return identifier
      }
    }
    return nil
  }

  private static func mediaItemIdentifiers(_ item: MPMediaItem) -> [String] {
    var identifiers: [String] = []
    let playbackStoreId = item.playbackStoreID.trimmingCharacters(in: .whitespacesAndNewlines)
    if !playbackStoreId.isEmpty && playbackStoreId != "0" {
      identifiers.append(playbackStoreId)
    }
    let persistentId = String(item.persistentID)
    if !persistentId.isEmpty && persistentId != "0" {
      identifiers.append(persistentId)
    }
    return identifiers
  }

  private static func cachedArtworkPath(
    for item: MPMediaItem,
    identifier: String
  ) -> String? {
    guard let artwork = item.artwork,
          let image = artwork.image(at: CGSize(width: 1200, height: 1200)),
          let data = image.jpegData(compressionQuality: 0.92) else {
      return nil
    }

    do {
      let documentsDirectory = try FileManager.default.url(
        for: .documentDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
      let artworkDirectory = documentsDirectory.appendingPathComponent(
        "døPe/AppleMusicArtwork",
        isDirectory: true
      )
      try FileManager.default.createDirectory(
        at: artworkDirectory,
        withIntermediateDirectories: true
      )
      let safeName = identifier.replacingOccurrences(
        of: "[^A-Za-z0-9_-]+",
        with: "_",
        options: .regularExpression
      )
      let destination = artworkDirectory.appendingPathComponent("\(safeName).jpg")
      if !FileManager.default.fileExists(atPath: destination.path) {
        try data.write(to: destination, options: .atomic)
      }
      return destination.path
    } catch {
      return nil
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


private enum NativeCrashLogWriter {
  private static let appFolderName = "døPe"

  static func install() {
    NSSetUncaughtExceptionHandler { exception in
      NativeCrashLogWriter.writeException(exception)
    }
    write(
      level: "INFO",
      category: "native",
      message: "AppDelegate launched",
      data: [:]
    )
  }

  private static func writeException(_ exception: NSException) {
    write(
      level: "ERROR",
      category: "native_exception",
      message: exception.name.rawValue,
      data: [
        "reason": exception.reason ?? "",
        "callStackSymbols": exception.callStackSymbols.joined(separator: "\\n")
      ]
    )
  }

  private static func write(
    level: String,
    category: String,
    message: String,
    data: [String: Any]
  ) {
    guard let documentsDirectory = FileManager.default.urls(
      for: .documentDirectory,
      in: .userDomainMask
    ).first else {
      return
    }

    let appDirectory = documentsDirectory.appendingPathComponent(appFolderName)
    let crashLog = appDirectory.appendingPathComponent("crash.log")
    do {
      try FileManager.default.createDirectory(
        at: appDirectory,
        withIntermediateDirectories: true
      )
      let timestamp = ISO8601DateFormatter().string(from: Date())
      let dataText = data
        .map { (key: $0.key, value: String(describing: $0.value)) }
        .filter { !$0.value.isEmpty }
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: " | ")
      let line = dataText.isEmpty
        ? "[\(timestamp)][\(level)][\(category)] \(message)\n"
        : "[\(timestamp)][\(level)][\(category)] \(message) | \(dataText)\n"
      if let bytes = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: crashLog.path) {
          let handle = try FileHandle(forWritingTo: crashLog)
          handle.seekToEndOfFile()
          handle.write(bytes)
          handle.closeFile()
        } else {
          try bytes.write(to: crashLog)
        }
      }
    } catch {
      NSLog("døPe native crash log write failed: \(error.localizedDescription)")
    }
  }
}
