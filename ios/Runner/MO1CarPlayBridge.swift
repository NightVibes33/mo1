import Flutter
import Foundation

struct MO1CarPlaySong {
  let originalIndex: Int
  let title: String
  let artist: String
  let album: String
  let duration: Int
  let rating: Int
  let artworkPath: String?

  init?(dictionary: [String: Any]) {
    guard let originalIndex = MO1CarPlaySnapshot.intValue(dictionary["originalIndex"]) else {
      return nil
    }

    self.originalIndex = originalIndex
    self.title = MO1CarPlaySnapshot.stringValue(dictionary["title"], fallback: "Unknown Song")
    self.artist = MO1CarPlaySnapshot.stringValue(dictionary["artist"], fallback: "Unknown Artist")
    self.album = MO1CarPlaySnapshot.stringValue(dictionary["album"], fallback: "Unknown Album")
    self.duration = MO1CarPlaySnapshot.intValue(dictionary["duration"]) ?? 0
    self.rating = MO1CarPlaySnapshot.intValue(dictionary["rating"]) ?? 0
    self.artworkPath = MO1CarPlaySnapshot.optionalString(dictionary["artworkPath"])
  }
}

struct MO1CarPlayCollection {
  let id: String
  let title: String
  let subtitle: String
  let count: Int
  let artworkPath: String?
  let songs: [MO1CarPlaySong]

  init?(dictionary: [String: Any]) {
    self.id = MO1CarPlaySnapshot.stringValue(dictionary["id"], fallback: UUID().uuidString)
    self.title = MO1CarPlaySnapshot.stringValue(dictionary["title"], fallback: "Untitled")
    self.subtitle = MO1CarPlaySnapshot.stringValue(dictionary["subtitle"], fallback: "")
    self.count = MO1CarPlaySnapshot.intValue(dictionary["count"]) ?? 0
    self.artworkPath = MO1CarPlaySnapshot.optionalString(dictionary["artworkPath"])
    self.songs = MO1CarPlaySnapshot.songs(from: dictionary["songs"])
  }
}

struct MO1CarPlaySnapshot {
  let songCount: Int
  let albumCount: Int
  let artistCount: Int
  let playlistCount: Int
  let isPlaying: Bool
  let elapsed: Int
  let duration: Int
  let current: MO1CarPlaySong?
  let songs: [MO1CarPlaySong]
  let recentlyAdded: [MO1CarPlaySong]
  let albums: [MO1CarPlayCollection]
  let artists: [MO1CarPlayCollection]
  let playlists: [MO1CarPlayCollection]

  static let empty = MO1CarPlaySnapshot(dictionary: [:])

  init(dictionary: [String: Any]) {
    self.songCount = Self.intValue(dictionary["songCount"]) ?? 0
    self.albumCount = Self.intValue(dictionary["albumCount"]) ?? 0
    self.artistCount = Self.intValue(dictionary["artistCount"]) ?? 0
    self.playlistCount = Self.intValue(dictionary["playlistCount"]) ?? 0
    self.isPlaying = dictionary["isPlaying"] as? Bool ?? false
    self.elapsed = Self.intValue(dictionary["elapsed"]) ?? 0
    self.duration = Self.intValue(dictionary["duration"]) ?? 0
    if let currentDictionary = dictionary["current"] as? [String: Any] {
      self.current = MO1CarPlaySong(dictionary: currentDictionary)
    } else {
      self.current = nil
    }
    self.songs = Self.songs(from: dictionary["songs"])
    self.recentlyAdded = Self.songs(from: dictionary["recentlyAdded"])
    self.albums = Self.collections(from: dictionary["albums"])
    self.artists = Self.collections(from: dictionary["artists"])
    self.playlists = Self.collections(from: dictionary["playlists"])
  }

  static func songs(from value: Any?) -> [MO1CarPlaySong] {
    guard let array = value as? [[String: Any]] else {
      return []
    }
    return array.compactMap(MO1CarPlaySong.init(dictionary:))
  }

  static func collections(from value: Any?) -> [MO1CarPlayCollection] {
    guard let array = value as? [[String: Any]] else {
      return []
    }
    return array.compactMap(MO1CarPlayCollection.init(dictionary:))
  }

  static func intValue(_ value: Any?) -> Int? {
    if let value = value as? Int {
      return value
    }
    if let value = value as? Double {
      return Int(value)
    }
    if let value = value as? NSNumber {
      return value.intValue
    }
    if let value = value as? String {
      return Int(value)
    }
    return nil
  }

  static func optionalString(_ value: Any?) -> String? {
    guard let string = value as? String else {
      return nil
    }
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  static func stringValue(_ value: Any?, fallback: String) -> String {
    return optionalString(value) ?? fallback
  }
}

final class MO1CarPlayBridge {
  static let shared = MO1CarPlayBridge()

  private var channel: FlutterMethodChannel?
  private var snapshotHandler: ((MO1CarPlaySnapshot) -> Void)?
  private(set) var latestSnapshot = MO1CarPlaySnapshot.empty

  private init() {}

  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "mo1/carplay",
      binaryMessenger: messenger
    )
    self.channel = channel

    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "updateSnapshot" else {
        result(FlutterMethodNotImplemented)
        return
      }

      guard let dictionary = call.arguments as? [String: Any] else {
        result(nil)
        return
      }

      self?.updateSnapshot(from: dictionary)
      result(nil)
    }
  }

  func observeSnapshots(_ handler: @escaping (MO1CarPlaySnapshot) -> Void) {
    snapshotHandler = handler
    handler(latestSnapshot)
  }

  func clearObserver() {
    snapshotHandler = nil
  }

  func requestSnapshot(completion: ((MO1CarPlaySnapshot) -> Void)? = nil) {
    guard let channel else {
      completion?(latestSnapshot)
      return
    }

    channel.invokeMethod("librarySnapshot", arguments: nil) { [weak self] result in
      guard let self else {
        return
      }
      if let dictionary = result as? [String: Any] {
        self.updateSnapshot(from: dictionary)
      }
      completion?(self.latestSnapshot)
    }
  }

  func sendCommand(
    _ method: String,
    arguments: Any? = nil,
    completion: ((MO1CarPlaySnapshot) -> Void)? = nil
  ) {
    guard let channel else {
      completion?(latestSnapshot)
      return
    }

    channel.invokeMethod(method, arguments: arguments) { [weak self] result in
      guard let self else {
        return
      }
      if let dictionary = result as? [String: Any] {
        self.updateSnapshot(from: dictionary)
      } else {
        self.requestSnapshot()
      }
      completion?(self.latestSnapshot)
    }
  }

  private func updateSnapshot(from dictionary: [String: Any]) {
    let snapshot = MO1CarPlaySnapshot(dictionary: dictionary)
    latestSnapshot = snapshot
    DispatchQueue.main.async { [weak self] in
      self?.snapshotHandler?(snapshot)
    }
  }
}
