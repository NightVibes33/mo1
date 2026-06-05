import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct MO1LiveActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var progress: Double
    var elapsed: Int
    var duration: Int
  }

  var id: String
}
