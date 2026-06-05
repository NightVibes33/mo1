import AVFoundation
import Flutter
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
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

private enum AppleMusicLookupChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "mo1/apple_music",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "searchSongs" else {
        result(FlutterMethodNotImplemented)
        return
      }

      guard #available(iOS 15.0, *) else {
        result([])
        return
      }

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
      var item: [String: Any] = [
        "id": song.id.rawValue,
        "title": song.title,
        "artist": song.artistName
      ]

      if let albumTitle = song.albumTitle, !albumTitle.isEmpty {
        item["album"] = albumTitle
      }
      if let artworkUrl = song.artwork?.url(width: 1200, height: 1200) {
        item["artworkUrl"] = artworkUrl.absoluteString
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
  }
}
