import Foundation

final class WidgetDataManager {
  static let shared = WidgetDataManager()
  private static let appGroupIdentifier = "group.com.nightvibes.dopi"
  private let defaults = UserDefaults(suiteName: WidgetDataManager.appGroupIdentifier)
  private let trackKey = "widget.currentTrack"
  private let libraryKey = "widget.library"

  private init() {}

  func loadCurrentTrack() -> NativeTrackSnapshot? {
    guard let defaults else { return nil }
    guard let data = defaults.data(forKey: trackKey) else { return nil }
    return try? JSONDecoder().decode(NativeTrackSnapshot.self, from: data)
  }

  func loadLibrarySummary() -> NativeLibrarySnapshot? {
    guard let defaults else { return nil }
    guard let data = defaults.data(forKey: libraryKey) else { return nil }
    return try? JSONDecoder().decode(NativeLibrarySnapshot.self, from: data)
  }

  func saveCurrentTrack(_ snapshot: NativeTrackSnapshot) {
    guard let defaults else { return }
    if let data = try? JSONEncoder().encode(snapshot) {
      defaults.set(data, forKey: trackKey)
    }
  }

  func saveLibrarySummary(_ snapshot: NativeLibrarySnapshot) {
    guard let defaults else { return }
    if let data = try? JSONEncoder().encode(snapshot) {
      defaults.set(data, forKey: libraryKey)
    }
  }

  func clear() {
    defaults?.removeObject(forKey: trackKey)
    defaults?.removeObject(forKey: libraryKey)
  }
}
