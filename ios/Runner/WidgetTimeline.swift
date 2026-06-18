import WidgetKit
import SwiftUI

struct DopiWidgetEntry: TimelineEntry {
  let date: Date
  let title: String
  let artist: String
  let isPlaying: Bool
}

struct DopiWidgetProvider: TimelineProvider {
  private let dataManager = WidgetDataManager.shared

  func placeholder(in context: Context) -> DopiWidgetEntry {
    DopiWidgetEntry(date: .now, title: "No Music", artist: "døPi", isPlaying: false)
  }

  private func currentEntry() -> DopiWidgetEntry {
    guard let snapshot = dataManager.loadCurrentTrack() else {
      return placeholder()
    }
    return DopiWidgetEntry(
      date: snapshot.lastUpdated,
      title: snapshot.title,
      artist: snapshot.artist.isEmpty ? snapshot.album : snapshot.artist,
      isPlaying: snapshot.isPlaying
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (DopiWidgetEntry) -> Void) {
    completion(currentEntry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<DopiWidgetEntry>) -> Void) {
    let entry = currentEntry()
    completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60))))
  }
}

struct DopiWidgetView: View {
  var entry: DopiWidgetEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(entry.title).font(.headline)
      Text(entry.artist).font(.subheadline)
      Text(entry.isPlaying ? "Playing" : "Paused").font(.caption)
    }
    .padding()
  }
}
