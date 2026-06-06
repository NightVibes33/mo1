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
        guard #available(iOS 16.0, *) else {
          result([])
          return
        }
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
    if let mediaDescriptor = mediaItemQueueDescriptor(
      catalogIds: cleanCatalogIds,
      startCatalogId: cleanStartCatalogId
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
          player.play()
          result(true)
        }
      }
      return
    }

    let descriptor = MPMusicPlayerStoreQueueDescriptor(storeIDs: cleanCatalogIds)
    descriptor.startItemID = cleanStartCatalogId
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
    request.limit = limit
    let response = try await request.response()
    let formatter = ISO8601DateFormatter()

    return response.items.prefix(limit).map { song in
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
      if results.count >= limit {
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
      let cachesDirectory = try FileManager.default.url(
        for: .cachesDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
      let artworkDirectory = cachesDirectory.appendingPathComponent(
        "ClassiPod/AppleMusicArtwork",
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
