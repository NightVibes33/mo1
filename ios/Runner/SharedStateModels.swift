import Foundation

struct NativeTrackSnapshot: Codable {
  let trackId: String
  let title: String
  let artist: String
  let album: String
  let isPlaying: Bool
  let isAppleMusic: Bool
  let isOnDevice: Bool
  let lastUpdated: Date
}

struct NativeLibrarySnapshot: Codable {
  let version: Int
  let totalTracks: Int
  let localTracks: Int
  let appleMusicTracks: Int
  let totalAlbums: Int
  let currentRoute: String
  let updatedAt: Date
}
