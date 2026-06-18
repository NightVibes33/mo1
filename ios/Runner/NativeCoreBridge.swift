import Flutter
import Foundation

final class NativeCoreBridge {
  static let shared = NativeCoreBridge()
  static let appGroupIdentifier = "group.com.nightvibes.dopi"
  private static let nowPlayingKey = "native.core.nowPlaying"
  private static let libraryKey = "native.core.library"

  private let queue = DispatchQueue(label: "mo1.native_core.bridge", qos: .utility)
  private var nowPlayingSnapshot: [String: Any] = [:]
  private var librarySummary: [String: Any] = [:]
  private var sharedDefaults: UserDefaults? {
    UserDefaults(suiteName: Self.appGroupIdentifier)
  }

  private init() {
    nowPlayingSnapshot = Self.dictionary(from: sharedDefaults?.dictionary(forKey: Self.nowPlayingKey))
    librarySummary = Self.dictionary(from: sharedDefaults?.dictionary(forKey: Self.libraryKey))
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    queue.async { [weak self] in
      guard let self else {
        DispatchQueue.main.async { result(false) }
        return
      }

      switch call.method {
      case "syncNowPlaying":
        self.nowPlayingSnapshot = Self.sanitize(call.arguments)
        self.sharedDefaults?.set(self.nowPlayingSnapshot, forKey: Self.nowPlayingKey)
        self.persistWidgetTrack(from: self.nowPlayingSnapshot)
        DispatchQueue.main.async { result(true) }
      case "syncLibrarySummary":
        self.librarySummary = Self.sanitize(call.arguments)
        self.sharedDefaults?.set(self.librarySummary, forKey: Self.libraryKey)
        self.persistWidgetLibrary(from: self.librarySummary)
        DispatchQueue.main.async { result(true) }
      case "getSnapshot":
        DispatchQueue.main.async {
          result([
            "nowPlaying": self.nowPlayingSnapshot,
            "library": self.librarySummary,
          ])
        }
      case "clear":
        self.nowPlayingSnapshot = [:]
        self.librarySummary = [:]
        self.sharedDefaults?.removeObject(forKey: Self.nowPlayingKey)
        self.sharedDefaults?.removeObject(forKey: Self.libraryKey)
        WidgetDataManager.shared.clear()
        DispatchQueue.main.async { result(true) }
      default:
        DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
      }
    }
  }

  private static func dictionary(from value: [String: Any]?) -> [String: Any] {
    value ?? [:]
  }

  private func persistWidgetTrack(from snapshot: [String: Any]) {
    let trackId = (snapshot["filePath"] as? String) ?? ""
    let title = (snapshot["trackName"] as? String) ?? "Unknown Song"
    let artist = (snapshot["artist"] as? String) ?? "Unknown Artist"
    let album = (snapshot["albumName"] as? String) ?? "Unknown Album"
    let isPlaying = snapshot["isPlaying"] as? Bool ?? false
    let isAppleMusic = snapshot["isAppleMusic"] as? Bool ?? false
    let isOnDevice = snapshot["isOnDevice"] as? Bool ?? false
    WidgetDataManager.shared.saveCurrentTrack(
      NativeTrackSnapshot(
        trackId: trackId,
        title: title,
        artist: artist,
        album: album,
        isPlaying: isPlaying,
        isAppleMusic: isAppleMusic,
        isOnDevice: isOnDevice,
        lastUpdated: Date()
      )
    )
  }

  private func persistWidgetLibrary(from snapshot: [String: Any]) {
    let totalTracks = snapshot["totalTracks"] as? Int ?? 0
    let localTracks = snapshot["localTracks"] as? Int ?? 0
    let appleMusicTracks = snapshot["appleMusicTracks"] as? Int ?? 0
    let totalAlbums = snapshot["totalAlbums"] as? Int ?? 0
    let currentRoute = snapshot["currentRoute"] as? String ?? ""
    WidgetDataManager.shared.saveLibrarySummary(
      NativeLibrarySnapshot(
        version: 1,
        totalTracks: totalTracks,
        localTracks: localTracks,
        appleMusicTracks: appleMusicTracks,
        totalAlbums: totalAlbums,
        currentRoute: currentRoute,
        updatedAt: Date()
      )
    )
  }

  private static func sanitize(_ value: Any?) -> [String: Any] {
    guard let dictionary = value as? [String: Any] else { return [:] }
    var cleaned: [String: Any] = [:]
    for (key, entry) in dictionary {
      if entry is String || entry is Bool || entry is Int || entry is Double || entry is NSNumber {
        cleaned[key] = entry
      } else if let nested = entry as? [String: Any] {
        cleaned[key] = sanitize(nested)
      } else if let nested = entry as? [Any] {
        cleaned[key] = nested.compactMap { element -> Any? in
          if element is String || element is Bool || element is Int || element is Double || element is NSNumber {
            return element
          }
          if let nestedMap = element as? [String: Any] {
            return sanitize(nestedMap)
          }
          return nil
        }
      }
    }
    return cleaned
  }
}

final class NativeCoreBridgeChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "mo1/native_core", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      NativeCoreBridge.shared.handle(call, result: result)
    }
  }
}
