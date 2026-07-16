import AVFoundation
import Flutter
import MediaPlayer
import MusicKit
import UIKit
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var deepLinkChannel: FlutterMethodChannel?
  private var pendingDeepLink: String?

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

    application.beginReceivingRemoteControlEvents()

    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      AppleMusicLookupChannel.register(with: controller.binaryMessenger)
      EqualizerChannel.register(with: controller.binaryMessenger)
      NativeEqPlayerChannel.register(with: controller.binaryMessenger)
      NativeColorPickerChannel.register(with: controller.binaryMessenger)
      NowPlayingChannel.register(with: controller.binaryMessenger)
      WidgetBridgeChannel.register(with: controller.binaryMessenger)
      SiriShortcutChannel.register(with: controller.binaryMessenger)
      deepLinkChannel = DeepLinkChannel.register(
        with: controller.binaryMessenger,
        initialLink: pendingDeepLink
      )
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    handleDeepLink(url.absoluteString)
    return true
  }

  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    if let link = userActivity.userInfo?["url"] as? String {
      handleDeepLink(link)
      return true
    }
    if let link = userActivity.webpageURL?.absoluteString {
      handleDeepLink(link)
      return true
    }
    return false
  }

  private func handleDeepLink(_ link: String) {
    pendingDeepLink = link
    deepLinkChannel?.invokeMethod("handleLink", arguments: link)
  }
}

private enum DeepLinkChannel {
  static func register(
    with messenger: FlutterBinaryMessenger,
    initialLink: String?
  ) -> FlutterMethodChannel {
    let channel = FlutterMethodChannel(
      name: "mo1/deep_link",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      if call.method == "getInitialLink" {
        result(initialLink)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    return channel
  }
}


private enum SiriShortcutChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "mo1/siri_shortcuts",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "donateShortcut":
        guard let arguments = call.arguments as? [String: Any],
              let identifier = arguments["identifier"] as? String,
              let title = arguments["title"] as? String,
              let urlString = arguments["url"] as? String,
              let url = URL(string: urlString) else {
          result(FlutterError(
            code: "BAD_SHORTCUT",
            message: "Shortcut donation payload was invalid.",
            details: nil
          ))
          return
        }
        donateShortcut(
          identifier: identifier,
          title: title,
          suggestedPhrase: arguments["suggestedPhrase"] as? String,
          url: url
        )
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func donateShortcut(
    identifier: String,
    title: String,
    suggestedPhrase: String?,
    url: URL
  ) {
    let activity = NSUserActivity(activityType: "app.mo1.player.dope.shortcut.\(identifier)")
    activity.title = title
    activity.suggestedInvocationPhrase = suggestedPhrase
    activity.isEligibleForSearch = true
    activity.isEligibleForPrediction = true
    activity.userInfo = ["url": url.absoluteString]
    activity.becomeCurrent()
  }
}

private enum WidgetBridgeChannel {
  private static let appGroupIdentifier = "group.com.nightvibes.dope"
  private static let snapshotFileName = "widget_now_playing.json"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "mo1/widgets",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "writeSnapshot":
        guard let snapshot = call.arguments as? [String: Any] else {
          result(FlutterError(
            code: "BAD_WIDGET_SNAPSHOT",
            message: "Widget snapshot payload was invalid.",
            details: nil
          ))
          return
        }
        do {
          try writeSnapshot(snapshot)
          WidgetCenter.shared.reloadAllTimelines()
          result(nil)
        } catch {
          result(FlutterError(
            code: "WIDGET_WRITE_FAILED",
            message: error.localizedDescription,
            details: nil
          ))
        }
      case "clearSnapshot":
        do {
          try clearSnapshot()
          WidgetCenter.shared.reloadAllTimelines()
          result(nil)
        } catch {
          result(FlutterError(
            code: "WIDGET_CLEAR_FAILED",
            message: error.localizedDescription,
            details: nil
          ))
        }
      case "reloadWidgets":
        WidgetCenter.shared.reloadAllTimelines()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func writeSnapshot(_ rawSnapshot: [String: Any]) throws {
    let directory = try appGroupDirectory()
    var snapshot = rawSnapshot
    if let artworkPath = rawSnapshot["artworkPath"] as? String,
       let copied = copyArtwork(
        from: artworkPath,
        to: directory.appendingPathComponent("widget_artwork_current.jpg")
       ) {
      snapshot["artworkFileName"] = copied
    }
    snapshot.removeValue(forKey: "artworkPath")

    if var queue = snapshot["queuePreview"] as? [[String: Any]] {
      for index in queue.indices {
        if let artworkPath = queue[index]["artworkPath"] as? String,
           let copied = copyArtwork(
            from: artworkPath,
            to: directory.appendingPathComponent("widget_artwork_queue_\(index).jpg")
           ) {
          queue[index]["artworkFileName"] = copied
        }
        queue[index].removeValue(forKey: "artworkPath")
      }
      snapshot["queuePreview"] = queue
    }

    let data = try JSONSerialization.data(
      withJSONObject: snapshot,
      options: [.prettyPrinted, .sortedKeys]
    )
    try data.write(
      to: directory.appendingPathComponent(snapshotFileName),
      options: [.atomic]
    )
  }

  private static func clearSnapshot() throws {
    let directory = try appGroupDirectory()
    let file = directory.appendingPathComponent(snapshotFileName)
    if FileManager.default.fileExists(atPath: file.path) {
      try FileManager.default.removeItem(at: file)
    }
  }

  private static func appGroupDirectory() throws -> URL {
    guard let directory = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupIdentifier
    ) else {
      throw NSError(
        domain: "WidgetBridgeChannel",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "App Group directory unavailable."]
      )
    }
    return directory
  }

  private static func copyArtwork(from path: String, to destination: URL) -> String? {
    let source = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: source.path) else {
      return nil
    }
    do {
      if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
      }
      try FileManager.default.copyItem(at: source, to: destination)
      return destination.lastPathComponent
    } catch {
      return nil
    }
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
      let preampDb = arguments["preampDb"] as? Double ?? 0

      if presetName == "off" || presetName == "flat" {
        result([
          "isApplied": true,
          "backend": "neutral",
          "message": "Neutral equalizer curve selected.",
          "preampDb": preampDb
        ])
        return
      }

      result([
        "isApplied": false,
        "backend": "just_audio_avplayer",
        "message": "The current iOS playback backend uses just_audio/AVPlayer; " +
          "audible EQ requires an AVAudioEngine-backed player.",
        "preampDb": preampDb
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

private enum NowPlayingChannel {
  private static var channel: FlutterMethodChannel?
  private static var remoteCommandsConfigured = false

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "mo1/now_playing",
      binaryMessenger: messenger
    )
    self.channel = channel
    configureRemoteCommands()
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "updateNowPlaying":
        let arguments = call.arguments as? [String: Any] ?? [:]
        updateNowPlaying(using: arguments)
        result(nil)
      case "clearNowPlaying":
        clearNowPlaying()
        result(nil)
      case "remoteCommandsReady":
        configureRemoteCommands()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func configureRemoteCommands() {
    guard !remoteCommandsConfigured else {
      return
    }
    remoteCommandsConfigured = true

    let commandCenter = MPRemoteCommandCenter.shared()
    commandCenter.playCommand.isEnabled = true
    commandCenter.pauseCommand.isEnabled = true
    commandCenter.togglePlayPauseCommand.isEnabled = true
    commandCenter.nextTrackCommand.isEnabled = true
    commandCenter.previousTrackCommand.isEnabled = true
    commandCenter.changePlaybackPositionCommand.isEnabled = true

    commandCenter.playCommand.addTarget { _ in
      sendRemoteCommand("play")
    }
    commandCenter.pauseCommand.addTarget { _ in
      sendRemoteCommand("pause")
    }
    commandCenter.togglePlayPauseCommand.addTarget { _ in
      sendRemoteCommand("play-pause")
    }
    commandCenter.nextTrackCommand.addTarget { _ in
      sendRemoteCommand("next")
    }
    commandCenter.previousTrackCommand.addTarget { _ in
      sendRemoteCommand("previous")
    }
    commandCenter.changePlaybackPositionCommand.addTarget { event in
      guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
        return .commandFailed
      }
      sendRemoteCommand("seek", arguments: ["positionSeconds": positionEvent.positionTime])
      return .success
    }
  }

  private static func sendRemoteCommand(
    _ action: String,
    arguments: [String: Any] = [:]
  ) -> MPRemoteCommandHandlerStatus {
    var payload = arguments
    payload["action"] = action
    channel?.invokeMethod("remoteCommand", arguments: payload)
    return .success
  }

  private static func updateNowPlaying(using arguments: [String: Any]) {
    let title = (arguments["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let artist = (arguments["artist"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let album = (arguments["album"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let artworkPath = arguments["artworkPath"] as? String
    let identifier = arguments["id"] as? String
    let durationSeconds = doubleValue(arguments["durationSeconds"])
    let positionSeconds = max(0, doubleValue(arguments["positionSeconds"]) ?? 0)
    let isPlaying = arguments["isPlaying"] as? Bool ?? false

    var info: [String: Any] = [:]
    info[MPMediaItemPropertyTitle] = (title?.isEmpty == false ? title : "Unknown Song")

    if let artist, !artist.isEmpty {
      info[MPMediaItemPropertyArtist] = artist
    }
    if let album, !album.isEmpty {
      info[MPMediaItemPropertyAlbumTitle] = album
    }
    if let identifier, !identifier.isEmpty {
      info[MPNowPlayingInfoPropertyExternalContentIdentifier] = identifier
    }
    if let durationSeconds, durationSeconds > 0 {
      info[MPMediaItemPropertyPlaybackDuration] = durationSeconds
    }

    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = positionSeconds
    info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

    if let artwork = artwork(from: artworkPath) {
      info[MPMediaItemPropertyArtwork] = artwork
    }

    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    if #available(iOS 13.0, *) {
      MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }
  }

  private static func clearNowPlaying() {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    if #available(iOS 13.0, *) {
      MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
  }

  private static func artwork(from rawPath: String?) -> MPMediaItemArtwork? {
    guard let rawPath else {
      return nil
    }

    let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return nil
    }

    if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
      return nil
    }

    let url: URL
    if trimmed.hasPrefix("file://"), let fileURL = URL(string: trimmed) {
      url = fileURL
    } else {
      url = URL(fileURLWithPath: trimmed)
    }

    guard let image = UIImage(contentsOfFile: url.path) else {
      return nil
    }

    return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
  }

  private static func doubleValue(_ value: Any?) -> Double? {
    switch value {
    case let number as NSNumber:
      return number.doubleValue
    case let string as String:
      return Double(string)
    default:
      return nil
    }
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
        } else if call.method == "addCatalogSongToLibrary" {
          result(false)
        } else if call.method == "playbackSnapshot" {
          result([
            "isSupported": false,
            "positionSeconds": 0,
            "durationSeconds": 0,
            "isPlaying": false,
            "playbackState": "unsupported",
            "backend": "unsupported",
            "transitionStyle": "off"
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
      case "skipToNextInCurrentQueue":
        skipToNextInCurrentQueue(result: result)
      case "skipToPreviousInCurrentQueue":
        skipToPreviousInCurrentQueue(result: result)
      case "restartCurrentItem":
        result(restartCurrentItem())
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
              limit: max(1, min(limit, 300))
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
      case "addCatalogSongToLibrary":
        guard let arguments = call.arguments as? [String: Any],
              let catalogId = arguments["catalogId"] as? String,
              !catalogId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          result(FlutterError(
            code: "APPLE_MUSIC_BAD_ARGUMENTS",
            message: "Missing Apple Music catalog id.",
            details: nil
          ))
          return
        }

        authorizeAppleMusicThen(result: result) {
          Task {
            do {
              let mediaStatus = await requestMediaLibraryAuthorization()
              guard mediaStatus == .authorized else {
                await MainActor.run {
                  result(FlutterError(
                    code: "APPLE_MUSIC_LIBRARY_NOT_AUTHORIZED",
                    message: "Media library access is required to add songs.",
                    details: nil
                  ))
                }
                return
              }

              try await addCatalogSongToLibrary(catalogId: catalogId)
              await MainActor.run {
                result([
                  "isSuccess": true,
                  "backend": "mediaLibrary",
                  "message": "Added to Apple Music library."
                ])
              }
            } catch {
              await MainActor.run {
                result(FlutterError(
                  code: "APPLE_MUSIC_LIBRARY_ADD_FAILED",
                  message: error.localizedDescription,
                  details: nil
                ))
              }
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
  private static func addCatalogSongToLibrary(catalogId: String) async throws {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, Error>) in
      MPMediaLibrary.default().addItem(withProductID: catalogId) { _, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        continuation.resume(returning: ())
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
    let wasAlreadyPlaying = player.playbackState == .playing
    if wasAlreadyPlaying {
      player.pause()
      player.currentPlaybackTime = 0
    }
    player.stop()
    player.currentPlaybackTime = 0

    let configureQueue = {
      let descriptor = MPMusicPlayerStoreQueueDescriptor(storeIDs: catalogIds)
      descriptor.startItemID = startCatalogId
      logAppleMusicDebug(
        "Queue rebuild using store queue descriptor",
        data: [
          "startCatalogId": startCatalogId,
          "queueSize": catalogIds.count,
          "wasAlreadyPlaying": wasAlreadyPlaying
        ]
      )
      player.setQueue(with: descriptor)
      player.currentPlaybackTime = 0
      player.prepareToPlay { error in
        DispatchQueue.main.async {
          if let error = error {
            guard let mediaDescriptor = mediaItemQueueDescriptor(
              catalogIds: catalogIds,
              startCatalogId: startCatalogId
            ) else {
              result(FlutterError(
                code: "APPLE_MUSIC_PLAYBACK_FAILED",
                message: error.localizedDescription,
                details: ["backend": "storeQueue"]
              ))
              return
            }

            logAppleMusicDebug(
              "Store queue failed; falling back to media library descriptor",
              data: [
                "startCatalogId": startCatalogId,
                "queueSize": catalogIds.count,
                "error": error.localizedDescription
              ]
            )
            player.pause()
            player.currentPlaybackTime = 0
            player.stop()
            player.currentPlaybackTime = 0
            player.setQueue(with: mediaDescriptor)
            player.currentPlaybackTime = 0
            player.prepareToPlay { fallbackError in
              DispatchQueue.main.async {
                if let fallbackError = fallbackError {
                  result(FlutterError(
                    code: "APPLE_MUSIC_PLAYBACK_FAILED",
                    message: fallbackError.localizedDescription,
                    details: ["backend": "mediaLibrary"]
                  ))
                  return
                }
                startPreparedMediaPlayerQueue(
                  player: player,
                  startCatalogId: startCatalogId,
                  backend: "mediaLibrary",
                  result: result
                )
              }
            }
            return
          }

          startPreparedMediaPlayerQueue(
            player: player,
            startCatalogId: startCatalogId,
            backend: "storeQueue",
            result: result
          )
        }
      }
    }

    if wasAlreadyPlaying {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
        player.currentPlaybackTime = 0
        configureQueue()
      }
      return
    }

    configureQueue()
  }

  private static func startPreparedMediaPlayerQueue(
    player: MPMusicPlayerController,
    startCatalogId: String,
    backend: String,
    result: @escaping FlutterResult
  ) {
    playbackBackend = .mediaPlayer
    player.currentPlaybackTime = 0
    player.play()
    logAppleMusicDebug(
      "Started Apple Music queue from zero",
      data: ["backend": backend, "startCatalogId": startCatalogId]
    )
    result(true)
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
    let wasAlreadyPlaying = player.state.playbackStatus == .playing
    if wasAlreadyPlaying {
      player.pause()
      player.playbackTime = 0
      try await Task.sleep(nanoseconds: 120_000_000)
    }
    player.stop()
    MPMusicPlayerController.applicationQueuePlayer.pause()
    MPMusicPlayerController.applicationQueuePlayer.currentPlaybackTime = 0
    MPMusicPlayerController.applicationQueuePlayer.stop()
    applyCurrentMusicKitTransitionIfAvailable()
    player.queue = ApplicationMusicPlayer.Queue(for: songs, startingAt: startSong)
    player.playbackTime = 0
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
      "catalogId": player.nowPlayingItem?.playbackStoreID ?? "",
      "backend": "mediaPlayer",
      "transitionStyle": transitionStyle
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
      "catalogId": catalogId,
      "backend": "musicKit",
      "transitionStyle": transitionStyle
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

  private static func skipToNextInCurrentQueue(result: @escaping FlutterResult) {
    if playbackBackend == .musicKit, #available(iOS 15.0, *) {
      Task { @MainActor in
        do {
          try await ApplicationMusicPlayer.shared.skipToNextEntry()
          result(true)
        } catch {
          result(FlutterError(
            code: "APPLE_MUSIC_SKIP_FAILED",
            message: error.localizedDescription,
            details: ["backend": "musicKit", "direction": "next"]
          ))
        }
      }
      return
    }
    result(skipToNextMediaPlayerItem())
  }

  private static func skipToNextMediaPlayerItem() -> Bool {
    let player = MPMusicPlayerController.applicationQueuePlayer
    guard let currentItem = player.nowPlayingItem else {
      logAppleMusicDebug("Skip next ignored because queue is empty")
      return false
    }
    let previousIdentifier = currentMediaPlayerIdentifier(currentItem)
    logAppleMusicDebug(
      "Advancing Apple Music queue",
      data: [
        "from": previousIdentifier ?? "",
        "positionSeconds": player.currentPlaybackTime
      ]
    )
    player.skipToNextItem()
    logAppleMusicDebug(
      "Requested native Apple Music queue advance",
      data: ["reason": "queueReuseNext"]
    )
    return true
  }

  private static func skipToPreviousInCurrentQueue(result: @escaping FlutterResult) {
    if playbackBackend == .musicKit, #available(iOS 15.0, *) {
      Task { @MainActor in
        do {
          try await ApplicationMusicPlayer.shared.skipToPreviousEntry()
          result(true)
        } catch {
          result(FlutterError(
            code: "APPLE_MUSIC_SKIP_FAILED",
            message: error.localizedDescription,
            details: ["backend": "musicKit", "direction": "previous"]
          ))
        }
      }
      return
    }
    result(skipToPreviousMediaPlayerItem())
  }

  private static func skipToPreviousMediaPlayerItem() -> Bool {
    let player = MPMusicPlayerController.applicationQueuePlayer
    guard let currentItem = player.nowPlayingItem else {
      logAppleMusicDebug("Skip previous ignored because queue is empty")
      return false
    }
    let previousIdentifier = currentMediaPlayerIdentifier(currentItem)
    logAppleMusicDebug(
      "Rewinding Apple Music queue to previous item",
      data: [
        "from": previousIdentifier ?? "",
        "positionSeconds": player.currentPlaybackTime
      ]
    )
    player.skipToPreviousItem()
    logAppleMusicDebug(
      "Requested native Apple Music queue rewind",
      data: ["reason": "queueReusePrevious"]
    )
    return true
  }

  private static func restartCurrentItem() -> Bool {
    if playbackBackend == .musicKit, #available(iOS 15.0, *) {
      let player = ApplicationMusicPlayer.shared
      guard player.queue.currentEntry != nil else {
        return false
      }
      player.playbackTime = 0
      return true
    }
    let player = MPMusicPlayerController.applicationQueuePlayer
    guard player.nowPlayingItem != nil else {
      logAppleMusicDebug("Restart current item ignored because queue is empty")
      return false
    }
    player.currentPlaybackTime = 0
    logAppleMusicDebug("Restarted current Apple Music item at zero")
    return true
  }

  private static func currentMediaPlayerIdentifier(_ item: MPMediaItem?) -> String? {
    guard let item else {
      return nil
    }
    return preferredMediaItemIdentifier(item)
  }

  private static func logAppleMusicDebug(
    _ message: String,
    data: [String: Any] = [:]
  ) {
    let payload = data
      .map { "\($0.key)=\($0.value)" }
      .sorted()
      .joined(separator: " | ")
    if payload.isEmpty {
      NSLog("døPe apple_music: \(message)")
    } else {
      NSLog("døPe apple_music: \(message) | \(payload)")
    }
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
      "artist": item.artist ?? item.albumArtist ?? "",
      "isExplicit": item.isExplicitItem
    ]

    if item.isExplicitItem {
      result["contentRating"] = "explicit"
    }
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
    let dateAdded = item.dateAdded
    result["dateAddedMs"] = Int(dateAdded.timeIntervalSince1970 * 1000)
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
    if let ratingText = contentRatingText(for: song) {
      item["contentRating"] = ratingText
      item["isExplicit"] = isExplicitRatingText(ratingText)
    }

    return item
  }

  private static func isExplicitRatingText(_ ratingText: String) -> Bool {
    let normalized = ratingText
      .lowercased()
      .replacingOccurrences(
        of: "[^a-z0-9]+",
        with: "",
        options: .regularExpression
      )
    if normalized.isEmpty ||
        normalized == "false" ||
        normalized == "0" ||
        normalized == "no" ||
        normalized == "none" ||
        normalized == "clean" ||
        normalized == "notexplicit" ||
        normalized == "nonexplicit" ||
        normalized == "noadvisory" {
      return false
    }
    return normalized == "explicit" ||
      normalized == "explicitcontent" ||
      normalized == "parentalratingexplicit" ||
      normalized == "contentadvisoryexplicit" ||
      normalized == "contentratingexplicit" ||
      normalized == "explicitlyrics" ||
      normalized == "parentaladvisory" ||
      normalized == "parentaladvisoryexplicit" ||
      normalized == "true" ||
      normalized == "1" ||
      normalized == "yes" ||
      normalized == "e" ||
      normalized.contains("explicit")
  }

  @available(iOS 15.0, *)
  private static func contentRatingText(for song: Song) -> String? {
    if let contentRating = song.contentRating {
      return String(describing: contentRating).lowercased()
    }

    guard let data = try? JSONEncoder().encode(song),
          let json = try? JSONSerialization.jsonObject(with: data) else {
      return nil
    }

    return nestedStringValue(named: "contentRating", in: json)?.lowercased()
  }

  private static func nestedStringValue(named key: String, in value: Any) -> String? {
    if let dictionary = value as? [String: Any] {
      if let direct = dictionary[key] as? String, !direct.isEmpty {
        return direct
      }
      for nested in dictionary.values {
        if let found = nestedStringValue(named: key, in: nested) {
          return found
        }
      }
      return nil
    }

    if let array = value as? [Any] {
      for nested in array {
        if let found = nestedStringValue(named: key, in: nested) {
          return found
        }
      }
    }

    return nil
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


private enum NativeEqPlayerChannel {
  private static let player = NativeEqPlayer()

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "mo1/native_eq_player",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      let arguments = call.arguments as? [String: Any] ?? [:]
      do {
        switch call.method {
        case "loadQueue":
          let items = arguments["items"] as? [[String: Any]] ?? []
          let startIndex = arguments["startIndex"] as? Int ?? 0
          let bandGains = doubleArray(arguments["bandGainsDb"])
          let preampDb = arguments["preampDb"] as? Double ?? 0
          try player.loadQueue(
            items: items,
            startIndex: startIndex,
            bandGains: bandGains,
            preampDb: preampDb
          )
          result(true)
        case "play":
          try player.play()
          result(true)
        case "pause":
          player.pause()
          result(true)
        case "stop":
          player.stop()
          result(true)
        case "seekToSeconds":
          let seconds = arguments["seconds"] as? Double ?? 0
          try player.seek(to: seconds)
          result(true)
        case "seekToIndex":
          let index = arguments["index"] as? Int ?? 0
          let seconds = arguments["seconds"] as? Double ?? 0
          try player.seek(toIndex: index, seconds: seconds)
          result(true)
        case "next":
          result(player.next())
        case "previous":
          result(player.previous())
        case "setPreset":
          let bandGains = doubleArray(arguments["bandGainsDb"])
          let preampDb = arguments["preampDb"] as? Double ?? 0
          let isApplied = player.setBandGains(bandGains, preampDb: preampDb)
          result([
            "isApplied": isApplied,
            "backend": "av_audio_engine",
            "message": isApplied
              ? "Native EQ preset applied."
              : "Native EQ player has no loaded audio.",
            "preampDb": preampDb
          ])
        case "setVolume":
          let value = arguments["value"] as? Double ?? 1
          player.setVolume(Float(max(0, min(1, value))))
          result(true)
        case "snapshot":
          result(player.snapshot())
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(
          code: "NATIVE_EQ_PLAYER_FAILED",
          message: error.localizedDescription,
          details: player.snapshot()
        ))
      }
    }
  }

  private static func doubleArray(_ value: Any?) -> [Double] {
    guard let values = value as? [Any] else {
      return []
    }
    return values.compactMap { entry in
      if let double = entry as? Double { return double }
      if let int = entry as? Int { return Double(int) }
      if let number = entry as? NSNumber { return number.doubleValue }
      return nil
    }
  }

}

private final class NativeEqPlayer: NSObject {
  private struct QueueItem {
    let id: String
    let filePath: String
    let title: String
    let artist: String
    let album: String
    let durationMs: Int
  }

  private enum PlayerError: LocalizedError {
    case emptyQueue
    case badIndex
    case unreadableFile(String)

    var errorDescription: String? {
      switch self {
      case .emptyQueue:
        return "Native EQ queue is empty."
      case .badIndex:
        return "Native EQ queue index is invalid."
      case .unreadableFile(let path):
        return "Native EQ cannot read file: \(path)"
      }
    }
  }

  private let engine = AVAudioEngine()
  private let playerNode = AVAudioPlayerNode()
  private let eq = AVAudioUnitEQ(numberOfBands: 10)
  private var queue: [QueueItem] = []
  private var currentIndex = 0
  private var currentFile: AVAudioFile?
  private var currentSampleRate: Double = 44100
  private var scheduledFrame: AVAudioFramePosition = 0
  private var pausedFrame: AVAudioFramePosition = 0
  private var isLoaded = false
  private var isPlaying = false
  private var lastError = ""
  private var lastStage = "idle"
  private var currentBandGains: [Float] = Array(repeating: 0, count: 10)
  private var currentPreampDb: Float = 0
  private var eqRampTimer: Timer?
  private var completionSerial = 0
  private var completedIndex = -1
  private var scheduleGeneration = 0

  override init() {
    super.init()
    engine.attach(playerNode)
    engine.attach(eq)
    engine.connect(playerNode, to: eq, format: nil)
    engine.connect(eq, to: engine.mainMixerNode, format: nil)
    configureEqBands([], preampDb: 0)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAudioSessionInterruption(_:)),
      name: AVAudioSession.interruptionNotification,
      object: AVAudioSession.sharedInstance()
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAudioRouteChange(_:)),
      name: AVAudioSession.routeChangeNotification,
      object: AVAudioSession.sharedInstance()
    )
  }

  @objc private func handleAudioSessionInterruption(_ notification: Notification) {
    guard let info = notification.userInfo,
          let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
    switch type {
    case .began:
      pause()
    case .ended:
      if let rawOptions = info[AVAudioSessionInterruptionOptionKey] as? UInt {
        let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
        if options.contains(.shouldResume) { try? play() }
      }
    @unknown default:
      pause()
    }
  }

  @objc private func handleAudioRouteChange(_ notification: Notification) {
    guard let info = notification.userInfo,
          let rawReason = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
          let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) else { return }
    if reason == .oldDeviceUnavailable {
      pause()
    }
  }

  func loadQueue(
    items rawItems: [[String: Any]],
    startIndex: Int,
    bandGains: [Double],
    preampDb: Double
  ) throws {
    lastStage = "activating_audio_session"
    try activateAudioSession()
    stop()
    lastStage = "parsing_queue"
    queue = rawItems.compactMap { item in
      guard let filePath = item["filePath"] as? String, !filePath.isEmpty else {
        return nil
      }
      return QueueItem(
        id: item["id"] as? String ?? filePath,
        filePath: filePath,
        title: item["title"] as? String ?? "Unknown Song",
        artist: item["artist"] as? String ?? "Unknown Artist",
        album: item["album"] as? String ?? "Unknown Album",
        durationMs: item["durationMs"] as? Int ?? 0
      )
    }
    guard !queue.isEmpty else { throw PlayerError.emptyQueue }
    guard startIndex >= 0 && startIndex < queue.count else { throw PlayerError.badIndex }
    currentIndex = startIndex
    configureEqBands(bandGains, preampDb: preampDb)
    lastStage = "loading_initial_file"
    try loadCurrentFile(startFrame: 0, autoPlay: false)
    lastStage = "ready"
  }

  func play() throws {
    do {
      try activateAudioSession()
      if !isLoaded, !queue.isEmpty {
        try loadCurrentFile(startFrame: pausedFrame, autoPlay: false)
      }
      if !engine.isRunning {
        engine.prepare()
        try engine.start()
      }
      playerNode.play()
      isPlaying = true
      completedIndex = -1
      lastError = ""
    } catch {
      lastError = error.localizedDescription
      isPlaying = false
      throw error
    }
  }

  func pause() {
    pausedFrame = currentFramePosition()
    playerNode.pause()
    isPlaying = false
  }

  func stop() {
    scheduleGeneration += 1
    eqRampTimer?.invalidate()
    eqRampTimer = nil
    playerNode.stop()
    engine.stop()
    currentFile = nil
    scheduledFrame = 0
    pausedFrame = 0
    isLoaded = false
    isPlaying = false
    completedIndex = -1
  }

  func seek(to seconds: Double) throws {
    try seek(toIndex: currentIndex, seconds: seconds)
  }

  func seek(toIndex index: Int, seconds: Double) throws {
    guard index >= 0 && index < queue.count else { throw PlayerError.badIndex }
    let wasPlaying = isPlaying
    currentIndex = index
    let frame = AVAudioFramePosition(max(0, seconds) * currentSampleRate)
    try loadCurrentFile(startFrame: frame, autoPlay: wasPlaying)
  }

  @discardableResult
  func next() -> Bool {
    guard currentIndex + 1 < queue.count else { return false }
    do {
      try seek(toIndex: currentIndex + 1, seconds: 0)
      return true
    } catch {
      lastError = error.localizedDescription
      return false
    }
  }

  @discardableResult
  func previous() -> Bool {
    if currentFramePositionSeconds() > 3 {
      do {
        try seek(to: 0)
        return true
      } catch {
        lastError = error.localizedDescription
        return false
      }
    }
    guard currentIndex > 0 else {
      do {
        try seek(to: 0)
        return true
      } catch {
        lastError = error.localizedDescription
        return false
      }
    }
    do {
      try seek(toIndex: currentIndex - 1, seconds: 0)
      return true
    } catch {
      lastError = error.localizedDescription
      return false
    }
  }

  @discardableResult
  func setBandGains(_ gains: [Double], preampDb: Double) -> Bool {
    rampEqBands(to: gains, preampDb: preampDb)
    return isLoaded
  }

  func setVolume(_ value: Float) {
    playerNode.volume = value
  }

  func snapshot() -> [String: Any] {
    return [
      "isSupported": true,
      "isLoaded": isLoaded,
      "isPlaying": isPlaying,
      "currentIndex": currentIndex,
      "positionSeconds": currentFramePositionSeconds(),
      "durationSeconds": durationSeconds(),
      "completionSerial": completionSerial,
      "completedIndex": completedIndex,
      "error": lastError,
      "stage": lastStage,
      "preampDb": Double(currentPreampDb)
    ]
  }

  private func loadCurrentFile(
    startFrame requestedStartFrame: AVAudioFramePosition,
    autoPlay: Bool
  ) throws {
    try activateAudioSession()
    guard currentIndex >= 0 && currentIndex < queue.count else { throw PlayerError.badIndex }
    let item = queue[currentIndex]
    let url = URL(fileURLWithPath: item.filePath)
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw PlayerError.unreadableFile(item.filePath)
    }

    scheduleGeneration += 1
    let generation = scheduleGeneration
    let scheduledIndex = currentIndex
    playerNode.stop()
    if engine.isRunning {
      engine.stop()
    }
    lastStage = "opening_audio_file"
    let file = try AVAudioFile(forReading: url)
    guard file.length > 0 else {
      throw PlayerError.unreadableFile(item.filePath)
    }
    currentFile = file
    currentSampleRate = file.processingFormat.sampleRate
    lastStage = "connecting_audio_engine"
    engine.disconnectNodeInput(eq)
    engine.disconnectNodeOutput(playerNode)
    engine.disconnectNodeOutput(eq)
    engine.connect(playerNode, to: eq, format: file.processingFormat)
    engine.connect(eq, to: engine.mainMixerNode, format: nil)
    let startFrame = min(max(0, requestedStartFrame), file.length - 1)
    scheduledFrame = startFrame
    pausedFrame = startFrame
    let frameCount = AVAudioFrameCount(max(1, file.length - startFrame))
    lastStage = "scheduling_audio_segment"
    playerNode.scheduleSegment(
      file,
      startingFrame: startFrame,
      frameCount: frameCount,
      at: nil
    ) { [weak self] in
      DispatchQueue.main.async {
        guard let self else { return }
        if self.isPlaying,
           self.scheduleGeneration == generation,
           self.currentIndex == scheduledIndex {
          self.completedIndex = scheduledIndex
          self.completionSerial += 1
          self.isPlaying = false
          self.isLoaded = false
          self.playerNode.stop()
        }
      }
    }
    isLoaded = true
    lastError = ""
    lastStage = "ready"
    if autoPlay {
      try play()
    }
  }

  private func activateAudioSession() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(
      .playback,
      mode: .default,
      options: [.allowAirPlay, .allowBluetoothA2DP]
    )
    try session.setActive(true)
  }

  private func configureEqBands(_ gains: [Double], preampDb: Double) {
    eqRampTimer?.invalidate()
    eqRampTimer = nil
    applyEqBandGains(normalizedBandGains(gains), preampDb: normalizedPreamp(preampDb))
  }

  private func rampEqBands(to gains: [Double], preampDb: Double) {
    let targetGains = normalizedBandGains(gains)
    let targetPreamp = normalizedPreamp(preampDb)
    let startGains = currentBandGains
    let startPreamp = currentPreampDb
    eqRampTimer?.invalidate()

    let steps = 20
    var step = 0
    eqRampTimer = Timer.scheduledTimer(
      withTimeInterval: 0.012,
      repeats: true
    ) { [weak self] timer in
      guard let self else {
        timer.invalidate()
        return
      }
      step += 1
      let progress = Float(step) / Float(steps)
      let interpolated = zip(startGains, targetGains).map { start, target in
        start + (target - start) * progress
      }
      let interpolatedPreamp = startPreamp + (targetPreamp - startPreamp) * progress
      self.applyEqBandGains(interpolated, preampDb: interpolatedPreamp)
      if step >= steps {
        timer.invalidate()
        self.eqRampTimer = nil
        self.applyEqBandGains(targetGains, preampDb: targetPreamp)
      }
    }
  }

  private func normalizedBandGains(_ gains: [Double]) -> [Float] {
    return (0..<eq.bands.count).map { index in
      Float(index < gains.count ? gains[index] : 0)
    }
  }

  private func normalizedPreamp(_ value: Double) -> Float {
    return Float(max(-12, min(0, value)))
  }

  private func applyEqBandGains(_ gains: [Float], preampDb: Float) {
    let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    currentBandGains = gains
    currentPreampDb = preampDb
    eq.globalGain = preampDb
    let isNeutral = gains.allSatisfy { abs($0) < 0.001 } && abs(preampDb) < 0.001
    for (index, band) in eq.bands.enumerated() {
      band.filterType = .parametric
      band.frequency = frequencies[min(index, frequencies.count - 1)]
      band.bandwidth = 1
      band.gain = index < gains.count ? gains[index] : 0
      band.bypass = isNeutral
    }
  }

  private func setEqBypass(_ bypass: Bool) {
    for band in eq.bands {
      band.bypass = bypass
    }
  }

  private func currentFramePosition() -> AVAudioFramePosition {
    guard isLoaded else { return 0 }
    if isPlaying,
       let nodeTime = playerNode.lastRenderTime,
       let playerTime = playerNode.playerTime(forNodeTime: nodeTime) {
      return scheduledFrame + AVAudioFramePosition(playerTime.sampleTime)
    }
    return pausedFrame
  }

  private func currentFramePositionSeconds() -> Double {
    let seconds = Double(currentFramePosition()) / max(1, currentSampleRate)
    return min(max(0, seconds), durationSeconds())
  }

  private func durationSeconds() -> Double {
    if let currentFile {
      return Double(currentFile.length) / max(1, currentFile.processingFormat.sampleRate)
    }
    guard currentIndex >= 0 && currentIndex < queue.count else { return 0 }
    return Double(queue[currentIndex].durationMs) / 1000
  }
}
