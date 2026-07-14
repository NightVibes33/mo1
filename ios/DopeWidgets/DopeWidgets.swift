import SwiftUI
import UIKit
import WidgetKit

private let appGroupIdentifier = "group.com.nightvibes.dope"
private let snapshotFileName = "widget_now_playing.json"

struct DopeWidgetSnapshot: Decodable, Hashable {
  struct QueueItem: Decodable, Hashable {
    let title: String
    let artist: String?
    let sourceType: String
    let isExplicit: Bool
    let artworkFileName: String?
  }

  let schemaVersion: Int
  let trackTitle: String
  let artistName: String?
  let albumName: String?
  let sourceType: String
  let isExplicit: Bool
  let isPlaying: Bool
  let queueIndex: Int
  let queueCount: Int
  let eqName: String
  let eqSupported: Bool
  let artworkFileName: String?
  let lastUpdatedEpochMs: Int64
  let deepLink: String
  let queuePreview: [QueueItem]

  static let empty = DopeWidgetSnapshot(
    schemaVersion: 1,
    trackTitle: "Open døPe",
    artistName: "Choose music to start",
    albumName: "",
    sourceType: "none",
    isExplicit: false,
    isPlaying: false,
    queueIndex: 0,
    queueCount: 0,
    eqName: "Off",
    eqSupported: false,
    artworkFileName: nil,
    lastUpdatedEpochMs: 0,
    deepLink: "dope://now-playing",
    queuePreview: []
  )
}

struct DopeWidgetEntry: TimelineEntry {
  let date: Date
  let snapshot: DopeWidgetSnapshot
}

struct DopeTimelineProvider: TimelineProvider {
  func placeholder(in context: Context) -> DopeWidgetEntry {
    DopeWidgetEntry(date: Date(), snapshot: .empty)
  }

  func getSnapshot(in context: Context, completion: @escaping (DopeWidgetEntry) -> Void) {
    completion(DopeWidgetEntry(date: Date(), snapshot: loadSnapshot()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<DopeWidgetEntry>) -> Void) {
    let entry = DopeWidgetEntry(date: Date(), snapshot: loadSnapshot())
    completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
  }

  private func loadSnapshot() -> DopeWidgetSnapshot {
    guard let url = FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
      .appendingPathComponent(snapshotFileName),
      let data = try? Data(contentsOf: url),
      let snapshot = try? JSONDecoder().decode(DopeWidgetSnapshot.self, from: data)
    else {
      return .empty
    }
    return snapshot
  }
}

private enum DopeWidgetKind {
  static let nowPlaying = "DopeNowPlayingWidget"
  static let miniIpod = "DopeMiniIpodWidget"
  static let queue = "DopeQueueWidget"
  static let eq = "DopeEqWidget"
}

@main
struct DopeWidgetsBundle: WidgetBundle {
  var body: some Widget {
    DopeNowPlayingWidget()
    DopeMiniIpodWidget()
    DopeQueueWidget()
    DopeEqWidget()
  }
}

struct DopeNowPlayingWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: DopeWidgetKind.nowPlaying, provider: DopeTimelineProvider()) { entry in
      DopeNowPlayingView(entry: entry)
    }
    .configurationDisplayName("døPe Now Playing")
    .description("Show your current døPe song, source, and quick controls.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

struct DopeMiniIpodWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: DopeWidgetKind.miniIpod, provider: DopeTimelineProvider()) { entry in
      DopeMiniIpodView(entry: entry)
    }
    .configurationDisplayName("døPe Mini iPod")
    .description("A mini iPod-style companion for døPe.")
    .supportedFamilies([.systemMedium, .systemLarge])
  }
}

struct DopeQueueWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: DopeWidgetKind.queue, provider: DopeTimelineProvider()) { entry in
      DopeQueueView(entry: entry)
    }
    .configurationDisplayName("døPe Queue")
    .description("Preview what is playing next in døPe.")
    .supportedFamilies([.systemLarge])
  }
}

struct DopeEqWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: DopeWidgetKind.eq, provider: DopeTimelineProvider()) { entry in
      DopeEqView(entry: entry)
    }
    .configurationDisplayName("døPe EQ")
    .description("Show EQ and source support for the current døPe song.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

struct DopeNowPlayingView: View {
  @Environment(\.widgetFamily) private var family
  let entry: DopeWidgetEntry

  var body: some View {
    Link(destination: widgetURL("now-playing")) {
      ZStack {
        DopeBackground(snapshot: entry.snapshot)
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 10) {
          HStack(alignment: .top) {
            DopeArtwork(snapshot: entry.snapshot, size: family == .systemSmall ? 54 : 78)
            if family != .systemSmall {
              VStack(alignment: .leading, spacing: 4) {
                DopeSourceBadge(snapshot: entry.snapshot)
                Text(entry.snapshot.trackTitle)
                  .font(.headline.weight(.black))
                  .lineLimit(2)
                Text(entry.snapshot.artistName ?? "Unknown Artist")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
            }
          }
          if family == .systemSmall {
            DopeSourceBadge(snapshot: entry.snapshot)
            Text(entry.snapshot.trackTitle)
              .font(.caption.weight(.black))
              .lineLimit(2)
          } else {
            Spacer(minLength: 4)
            DopeControlRow(snapshot: entry.snapshot)
          }
        }
        .padding(12)
      }
    }
    .widgetURL(widgetURL("now-playing"))
  }
}

struct DopeMiniIpodView: View {
  @Environment(\.widgetFamily) private var family
  let entry: DopeWidgetEntry

  var body: some View {
    ZStack {
      LinearGradient(colors: [.red.opacity(0.78), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
      VStack(spacing: 10) {
        Link(destination: widgetURL("now-playing")) {
          HStack(spacing: 10) {
            DopeArtwork(snapshot: entry.snapshot, size: family == .systemLarge ? 92 : 70)
            VStack(alignment: .leading, spacing: 4) {
              Text("døPe")
                .font(.caption.weight(.black))
              Text(entry.snapshot.trackTitle)
                .font(.headline.weight(.black))
                .lineLimit(2)
              Text(entry.snapshot.artistName ?? "Unknown Artist")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
              DopeSourceBadge(snapshot: entry.snapshot)
            }
            Spacer(minLength: 0)
          }
          .padding(12)
          .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 18))
        }
        if family == .systemLarge {
          Spacer(minLength: 2)
          ZStack {
            Circle().fill(.black.opacity(0.72))
            Circle().stroke(.white.opacity(0.10), lineWidth: 2)
            Circle().fill(.red.opacity(0.35)).frame(width: 82, height: 82)
            VStack {
              Link("⌃", destination: widgetURL("eq"))
                .font(.title2.weight(.bold))
              Spacer()
              HStack {
                Link("◀", destination: widgetURL("action/previous"))
                Spacer()
                Link(entry.snapshot.isPlaying ? "Ⅱ" : "▶", destination: widgetURL("action/play-pause"))
                Spacer()
                Link("▶", destination: widgetURL("action/next"))
              }
              .font(.title3.weight(.black))
              Spacer()
            }
            .padding(22)
          }
          .frame(width: 190, height: 190)
        } else {
          DopeControlRow(snapshot: entry.snapshot)
        }
      }
      .padding(14)
    }
    .foregroundStyle(.white)
    .widgetURL(widgetURL("now-playing"))
  }
}

struct DopeQueueView: View {
  let entry: DopeWidgetEntry

  var body: some View {
    Link(destination: widgetURL("queue")) {
      ZStack {
        DopeBackground(snapshot: entry.snapshot)
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Text("Queue")
              .font(.title3.weight(.black))
            Spacer()
            Text(queueText(entry.snapshot))
              .font(.caption.weight(.bold))
              .foregroundStyle(.secondary)
          }
          HStack(spacing: 10) {
            DopeArtwork(snapshot: entry.snapshot, size: 64)
            VStack(alignment: .leading, spacing: 3) {
              Text("Now Playing")
                .font(.caption2.weight(.black))
                .foregroundStyle(.secondary)
              Text(entry.snapshot.trackTitle)
                .font(.headline.weight(.black))
                .lineLimit(1)
              Text(entry.snapshot.artistName ?? "Unknown Artist")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
          Divider().overlay(.white.opacity(0.2))
          ForEach(Array(entry.snapshot.queuePreview.enumerated()), id: \.offset) { index, item in
            HStack {
              Text("\(index + 1)")
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
              VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                  .font(.caption.weight(.bold))
                  .lineLimit(1)
                Text(item.artist ?? sourceTitle(item.sourceType))
                  .font(.caption2.weight(.semibold))
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
              Spacer()
              if item.isExplicit {
                Text("E")
                  .font(.caption2.weight(.black))
                  .padding(.horizontal, 4)
                  .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
              }
              Text(sourceTitle(item.sourceType))
                .font(.caption2.weight(.black))
                .foregroundStyle(.secondary)
            }
          }
          if entry.snapshot.queuePreview.isEmpty {
            Text("No upcoming songs")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
          }
        }
        .padding(14)
      }
    }
    .widgetURL(widgetURL("queue"))
  }
}

struct DopeEqView: View {
  @Environment(\.widgetFamily) private var family
  let entry: DopeWidgetEntry

  var body: some View {
    Link(destination: widgetURL("eq")) {
      ZStack {
        DopeBackground(snapshot: entry.snapshot)
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Text("EQ")
              .font(.title3.weight(.black))
            Spacer()
            DopeSourceBadge(snapshot: entry.snapshot)
          }
          Text(entry.snapshot.eqName)
            .font(family == .systemSmall ? .headline.weight(.black) : .title2.weight(.black))
            .lineLimit(1)
          Text(eqStatus(entry.snapshot))
            .font(.caption.weight(.bold))
            .foregroundStyle(entry.snapshot.eqSupported ? .green : .orange)
            .lineLimit(2)
          if family != .systemSmall {
            HStack(spacing: 4) {
              ForEach(0..<10, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                  .fill(eqBarColor(index))
                  .frame(width: 8, height: CGFloat([16, 22, 28, 18, 12, 20, 26, 30, 24, 18][index]))
              }
            }
            Spacer(minLength: 0)
            Text("Tap to tune custom EQ")
              .font(.caption2.weight(.bold))
              .foregroundStyle(.secondary)
          }
        }
        .padding(14)
      }
    }
    .widgetURL(widgetURL("eq"))
  }
}

struct DopeBackground: View {
  let snapshot: DopeWidgetSnapshot

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [Color(red: 0.05, green: 0.06, blue: 0.08), Color(red: 0.33, green: 0.02, blue: 0.02)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      if snapshot.sourceType == "appleMusic" {
        Color.pink.opacity(0.16)
      } else if snapshot.sourceType == "navidrome" {
        Color.cyan.opacity(0.14)
      } else if snapshot.sourceType == "jellyfin" {
        Color.purple.opacity(0.16)
      }
    }
    .containerBackground(for: .widget) {
      Color.black
    }
  }
}

struct DopeArtwork: View {
  let snapshot: DopeWidgetSnapshot
  let size: CGFloat

  var body: some View {
    Group {
      if let image = artworkImage(snapshot.artworkFileName) {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        ZStack {
          RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.55))
          Text("♪")
            .font(.system(size: size * 0.45, weight: .black))
            .foregroundStyle(.cyan)
        }
      }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12), lineWidth: 1))
  }
}

struct DopeSourceBadge: View {
  let snapshot: DopeWidgetSnapshot

  var body: some View {
    Text(sourceTitle(snapshot.sourceType))
      .font(.caption2.weight(.black))
      .foregroundStyle(sourceColor(snapshot.sourceType))
      .padding(.horizontal, 7)
      .padding(.vertical, 4)
      .background(sourceColor(snapshot.sourceType).opacity(0.16), in: Capsule())
  }
}

struct DopeControlRow: View {
  let snapshot: DopeWidgetSnapshot

  var body: some View {
    HStack(spacing: 14) {
      Link("◀◀", destination: widgetURL("action/previous"))
      Link(snapshot.isPlaying ? "Ⅱ" : "▶", destination: widgetURL("action/play-pause"))
      Link("▶▶", destination: widgetURL("action/next"))
      Spacer()
      Text(queueText(snapshot))
        .font(.caption2.weight(.black))
        .foregroundStyle(.secondary)
    }
    .font(.headline.weight(.black))
  }
}

private func widgetURL(_ target: String) -> URL {
  URL(string: "dope://\(target)") ?? URL(string: "dope://now-playing")!
}

private func artworkImage(_ fileName: String?) -> UIImage? {
  guard let fileName,
        let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
  else { return nil }
  return UIImage(contentsOfFile: directory.appendingPathComponent(fileName).path)
}

private func sourceTitle(_ source: String) -> String {
  switch source {
  case "appleMusic": return "APPLE MUSIC"
  case "navidrome": return "NAVIDROME"
  case "jellyfin": return "JELLYFIN"
  case "remote": return "REMOTE"
  case "mp3": return "MP3"
  default: return "døPe"
  }
}

private func sourceColor(_ source: String) -> Color {
  switch source {
  case "appleMusic": return .pink
  case "navidrome": return .cyan
  case "jellyfin": return .purple
  case "remote": return .blue
  case "mp3": return .green
  default: return .white
  }
}

private func queueText(_ snapshot: DopeWidgetSnapshot) -> String {
  guard snapshot.queueCount > 0 else { return "No Queue" }
  return "\(snapshot.queueIndex)/\(snapshot.queueCount)"
}

private func eqStatus(_ snapshot: DopeWidgetSnapshot) -> String {
  if snapshot.sourceType == "appleMusic" { return "Apple Music bypasses EQ" }
  if snapshot.eqSupported { return "EQ active for this source" }
  return "Open døPe to choose music"
}

private func eqBarColor(_ index: Int) -> Color {
  if index <= 2 { return .blue }
  if index <= 6 { return .orange }
  return .teal
}
