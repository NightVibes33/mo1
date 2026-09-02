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
  let positionSeconds: Int?
  let durationSeconds: Int?
  let queueIndex: Int
  let queueCount: Int
  let eqName: String
  let eqSupported: Bool
  let eqBandGainsDb: [Double]?
  let eqPreampDb: Double?
  let artworkFileName: String?
  let lastUpdatedEpochMs: Int64
  let deepLink: String
  let queuePreview: [QueueItem]

  static let empty = DopeWidgetSnapshot(
    schemaVersion: 1,
    trackTitle: "Open doPi",
    artistName: "Choose music to start",
    albumName: "",
    sourceType: "none",
    isExplicit: false,
    isPlaying: false,
    positionSeconds: nil,
    durationSeconds: nil,
    queueIndex: 0,
    queueCount: 0,
    eqName: "Off",
    eqSupported: false,
    eqBandGainsDb: nil,
    eqPreampDb: nil,
    artworkFileName: nil,
    lastUpdatedEpochMs: 0,
    deepLink: "dopi://now-playing",
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
    .configurationDisplayName("doPi Now Playing")
    .description("Show your current doPi song, source, and quick controls.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    .contentMarginsDisabled()
  }
}

struct DopeMiniIpodWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: DopeWidgetKind.miniIpod, provider: DopeTimelineProvider()) { entry in
      DopeMiniIpodView(entry: entry)
    }
    .configurationDisplayName("doPi Mini iPod")
    .description("A mini iPod-style companion for doPi.")
    .supportedFamilies([.systemMedium, .systemLarge])
    .contentMarginsDisabled()
  }
}

struct DopeQueueWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: DopeWidgetKind.queue, provider: DopeTimelineProvider()) { entry in
      DopeQueueView(entry: entry)
    }
    .configurationDisplayName("doPi Queue")
    .description("Preview what is playing next in doPi.")
    .supportedFamilies([.systemLarge])
    .contentMarginsDisabled()
  }
}

struct DopeEqWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: DopeWidgetKind.eq, provider: DopeTimelineProvider()) { entry in
      DopeEqView(entry: entry)
    }
    .configurationDisplayName("doPi EQ")
    .description("Show EQ and source support for the current doPi song.")
    .supportedFamilies([.systemSmall, .systemMedium])
    .contentMarginsDisabled()
  }
}

struct DopeNowPlayingView: View {
  @Environment(\.widgetFamily) private var family
  let entry: DopeWidgetEntry

  var body: some View {
    Group {
      if family == .systemSmall {
        smallLayout
      } else {
        wideLayout
      }
    }
    .containerBackground(for: .widget) { Color.black }
    .widgetURL(dopeWidgetURL("now-playing"))
  }

  private var smallLayout: some View {
    ZStack(alignment: .bottomLeading) {
      DopeArtworkFill(snapshot: entry.snapshot)
      LinearGradient(
        colors: [.black.opacity(0.05), .black.opacity(0.88)],
        startPoint: .top,
        endPoint: .bottom
      )
      VStack(alignment: .leading, spacing: 5) {
        HStack {
          DopeWordmark(compact: true)
          Spacer()
          DopePlayingPulse(isPlaying: entry.snapshot.isPlaying)
        }
        Spacer()
        Text(entry.snapshot.trackTitle)
          .font(.system(size: 16, weight: .black, design: .rounded))
          .lineLimit(2)
        HStack(spacing: 5) {
          Text(entry.snapshot.artistName ?? "Unknown Artist")
            .lineLimit(1)
          if entry.snapshot.isExplicit { DopeExplicitMark() }
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(.white.opacity(0.72))
      }
      .padding(13)
    }
  }

  private var wideLayout: some View {
    ZStack {
      DopeBackground(snapshot: entry.snapshot)
      VStack(spacing: family == .systemLarge ? 14 : 10) {
        HStack(spacing: 13) {
          DopeArtwork(snapshot: entry.snapshot, size: family == .systemLarge ? 106 : 92)
          VStack(alignment: .leading, spacing: 5) {
            HStack {
              DopeWordmark(compact: false)
              Spacer()
              DopePlayingPulse(isPlaying: entry.snapshot.isPlaying)
            }
            Spacer(minLength: 0)
            Text(entry.snapshot.trackTitle)
              .font(.system(size: family == .systemLarge ? 21 : 18, weight: .black, design: .rounded))
              .lineLimit(2)
            HStack(spacing: 6) {
              Text(entry.snapshot.artistName ?? "Unknown Artist").lineLimit(1)
              if entry.snapshot.isExplicit { DopeExplicitMark() }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.62))
            DopeSourceBadge(snapshot: entry.snapshot)
          }
        }
        DopeProgressBar(snapshot: entry.snapshot)
        DopeControlRow(snapshot: entry.snapshot)
        if family == .systemLarge {
          DopeCompactQueue(snapshot: entry.snapshot)
        }
      }
      .padding(15)
    }
  }
}

struct DopeMiniIpodView: View {
  @Environment(\.widgetFamily) private var family
  let entry: DopeWidgetEntry

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [Color(red: 0.88, green: 0.89, blue: 0.91), Color(red: 0.30, green: 0.31, blue: 0.34)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      if family == .systemLarge {
        VStack(spacing: 14) {
          deviceScreen
          DopeClickWheel(snapshot: entry.snapshot, diameter: 185)
        }
        .padding(16)
      } else {
        HStack(spacing: 16) {
          deviceScreen
          DopeClickWheel(snapshot: entry.snapshot, diameter: 130)
        }
        .padding(15)
      }
    }
    .overlay(
      RoundedRectangle(cornerRadius: 22)
        .stroke(.white.opacity(0.36), lineWidth: 1)
    )
    .containerBackground(for: .widget) { Color.gray }
    .widgetURL(dopeWidgetURL("now-playing"))
  }

  private var deviceScreen: some View {
    Link(destination: dopeWidgetURL("now-playing")) {
      ZStack {
        Color(red: 0.035, green: 0.04, blue: 0.045)
        VStack(spacing: 0) {
          HStack {
            Text("dÃ¸Pe")
              .font(.caption.weight(.black))
            Spacer()
            DopePlayingPulse(isPlaying: entry.snapshot.isPlaying)
          }
          .padding(.horizontal, 9)
          .frame(height: 25)
          .background(Color(red: 0.58, green: 0.02, blue: 0.02))
          HStack(spacing: 9) {
            DopeArtwork(snapshot: entry.snapshot, size: family == .systemLarge ? 94 : 66)
            VStack(alignment: .leading, spacing: 4) {
              Text(entry.snapshot.trackTitle)
                .font(.system(size: family == .systemLarge ? 18 : 14, weight: .black, design: .rounded))
                .lineLimit(2)
              Text(entry.snapshot.artistName ?? "Unknown Artist")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(2)
              Spacer(minLength: 0)
              Text(queueText(entry.snapshot))
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(.white.opacity(0.45))
            }
          }
          .padding(9)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay(RoundedRectangle(cornerRadius: 8).stroke(.black.opacity(0.7), lineWidth: 3))
    }
  }
}

struct DopeQueueView: View {
  let entry: DopeWidgetEntry

  var body: some View {
    ZStack {
      Color(red: 0.025, green: 0.028, blue: 0.032)
      VStack(spacing: 0) {
        HStack {
          Text("MUSIC")
            .font(.caption.weight(.black))
            .tracking(1.4)
          Spacer()
          Text(queueText(entry.snapshot))
            .font(.caption2.monospacedDigit().weight(.bold))
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(Color(red: 0.55, green: 0.01, blue: 0.01))

        Link(destination: dopeWidgetURL("now-playing")) {
          HStack(spacing: 11) {
            DopeArtwork(snapshot: entry.snapshot, size: 62)
            VStack(alignment: .leading, spacing: 3) {
              Text("NOW PLAYING")
                .font(.caption2.weight(.black))
                .foregroundStyle(.black.opacity(0.55))
              Text(entry.snapshot.trackTitle)
                .font(.headline.weight(.black))
                .lineLimit(1)
              Text(entry.snapshot.artistName ?? "Unknown Artist")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
              .font(.headline.weight(.black))
          }
          .foregroundStyle(.black)
          .padding(.horizontal, 13)
          .frame(height: 86)
          .background(
            LinearGradient(colors: [Color(red: 0.35, green: 0.82, blue: 0.95), Color(red: 0.74, green: 0.94, blue: 0.98)], startPoint: .leading, endPoint: .trailing)
          )
        }

        VStack(spacing: 0) {
          if entry.snapshot.queuePreview.isEmpty {
            Spacer()
            Text("QUEUE EMPTY")
              .font(.caption.weight(.black))
              .tracking(1.2)
              .foregroundStyle(.white.opacity(0.35))
            Spacer()
          } else {
            ForEach(Array(entry.snapshot.queuePreview.prefix(3).enumerated()), id: \.offset) { index, item in
              DopeQueueRow(index: index + 1, item: item)
              if index < min(entry.snapshot.queuePreview.count, 3) - 1 {
                Divider().overlay(.white.opacity(0.08))
              }
            }
            Spacer(minLength: 0)
          }
        }
        .padding(.horizontal, 13)
        .padding(.top, 5)
      }
    }
    .foregroundStyle(.white)
    .containerBackground(for: .widget) { Color.black }
    .widgetURL(dopeWidgetURL("queue"))
  }
}

struct DopeEqView: View {
  @Environment(\.widgetFamily) private var family
  let entry: DopeWidgetEntry

  var body: some View {
    ZStack {
      Color(red: 0.025, green: 0.028, blue: 0.032)
      VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 10) {
        HStack {
          VStack(alignment: .leading, spacing: 1) {
            Text("EQUALIZER")
              .font(.caption2.weight(.black))
              .tracking(1.25)
              .foregroundStyle(.white.opacity(0.42))
            Text(entry.snapshot.eqName)
              .font(.system(size: family == .systemSmall ? 17 : 20, weight: .black, design: .rounded))
              .lineLimit(1)
          }
          Spacer()
          DopeSourceBadge(snapshot: entry.snapshot)
        }
        DopeEqGraph(snapshot: entry.snapshot, compact: family == .systemSmall)
        HStack {
          Circle()
            .fill(entry.snapshot.eqSupported ? Color.green : Color.orange)
            .frame(width: 7, height: 7)
          Text(eqStatus(entry.snapshot).uppercased())
            .font(.system(size: 9, weight: .black, design: .rounded))
            .lineLimit(1)
          Spacer()
          if family != .systemSmall {
            Text("PREAMP \(gainText(entry.snapshot.eqPreampDb ?? 0))")
              .font(.system(size: 9, weight: .bold, design: .monospaced))
              .foregroundStyle(.white.opacity(0.42))
          }
        }
      }
      .padding(14)
    }
    .containerBackground(for: .widget) { Color.black }
    .widgetURL(dopeWidgetURL("eq"))
  }
}

struct DopeCompactQueue: View {
  let snapshot: DopeWidgetSnapshot

  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(snapshot.queuePreview.prefix(2).enumerated()), id: \.offset) { index, item in
        DopeQueueRow(index: index + 1, item: item)
        if index == 0 { Divider().overlay(.white.opacity(0.08)) }
      }
    }
    .padding(.horizontal, 10)
    .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 12))
  }
}

struct DopeQueueRow: View {
  let index: Int
  let item: DopeWidgetSnapshot.QueueItem

  var body: some View {
    HStack(spacing: 9) {
      Text(String(format: "%02d", index))
        .font(.caption2.monospacedDigit().weight(.black))
        .foregroundStyle(.white.opacity(0.28))
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 5) {
          Text(item.title).font(.caption.weight(.bold)).lineLimit(1)
          if item.isExplicit { DopeExplicitMark() }
        }
        Text(item.artist ?? sourceTitle(item.sourceType))
          .font(.caption2.weight(.medium))
          .foregroundStyle(.white.opacity(0.42))
          .lineLimit(1)
      }
      Spacer()
      SourceLogoMark(sourceType: item.sourceType)
        .frame(width: 15, height: 15)
        .foregroundStyle(sourceColor(item.sourceType))
    }
    .frame(minHeight: 47)
  }
}

struct DopeClickWheel: View {
  let snapshot: DopeWidgetSnapshot
  let diameter: CGFloat

  var body: some View {
    ZStack {
      Circle()
        .fill(Color(red: 0.055, green: 0.055, blue: 0.06))
        .shadow(color: .black.opacity(0.55), radius: 6, y: 4)
      Circle().stroke(.white.opacity(0.09), lineWidth: 1)
      Link(destination: dopeWidgetURL("queue")) {
        Text("MENU")
          .font(.system(size: diameter * 0.075, weight: .black, design: .rounded))
      }
      .offset(y: -diameter * 0.34)
      Link(destination: dopeWidgetURL("action/previous")) {
        Image(systemName: "backward.end.fill")
      }
      .offset(x: -diameter * 0.34)
      Link(destination: dopeWidgetURL("action/next")) {
        Image(systemName: "forward.end.fill")
      }
      .offset(x: diameter * 0.34)
      Link(destination: dopeWidgetURL("action/play-pause")) {
        Image(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill")
      }
      .offset(y: diameter * 0.34)
      Link(destination: dopeWidgetURL("now-playing")) {
        Circle()
          .fill(
            RadialGradient(colors: [Color(red: 0.55, green: 0.02, blue: 0.02), Color(red: 0.18, green: 0.01, blue: 0.01)], center: .topLeading, startRadius: 2, endRadius: diameter * 0.25)
          )
          .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
          .frame(width: diameter * 0.42, height: diameter * 0.42)
      }
    }
    .font(.system(size: diameter * 0.11, weight: .black))
    .foregroundStyle(.white)
    .frame(width: diameter, height: diameter)
  }
}

struct DopeEqGraph: View {
  let snapshot: DopeWidgetSnapshot
  let compact: Bool

  private var gains: [Double] {
    let values = snapshot.eqBandGainsDb ?? []
    return values.count == 10 ? values : Array(repeating: 0, count: 10)
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        ForEach(0..<5, id: \.self) { row in
          Rectangle()
            .fill(.white.opacity(row == 2 ? 0.14 : 0.055))
            .frame(height: 1)
            .offset(y: (CGFloat(row) - 2) * geometry.size.height / 4)
        }
        HStack(alignment: .center, spacing: compact ? 3 : 5) {
          ForEach(Array(gains.enumerated()), id: \.offset) { index, gain in
            VStack(spacing: 2) {
              Spacer(minLength: 0)
              RoundedRectangle(cornerRadius: 2)
                .fill(eqBandGradient(index))
                .frame(height: max(3, CGFloat(abs(gain)) / 12 * geometry.size.height * 0.43))
                .offset(y: gain >= 0 ? -CGFloat(abs(gain)) / 12 * geometry.size.height * 0.215 : CGFloat(abs(gain)) / 12 * geometry.size.height * 0.215)
              Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
          }
        }
      }
    }
    .frame(height: compact ? 58 : 76)
    .padding(.horizontal, 8)
    .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 10))
    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.08), lineWidth: 1))
  }
}

struct DopeWordmark: View {
  let compact: Bool

  var body: some View {
    HStack(spacing: 5) {
      Circle()
        .fill(Color(red: 0.72, green: 0.02, blue: 0.02))
        .frame(width: compact ? 16 : 19, height: compact ? 16 : 19)
        .overlay(Image(systemName: "music.note").font(.system(size: compact ? 8 : 10, weight: .black)))
      Text("dÃ¸Pe")
        .font(.system(size: compact ? 12 : 14, weight: .black, design: .rounded))
    }
  }
}

struct DopePlayingPulse: View {
  let isPlaying: Bool

  var body: some View {
    HStack(alignment: .bottom, spacing: 2) {
      ForEach([7.0, 13.0, 9.0], id: \.self) { height in
        Capsule()
          .fill(isPlaying ? Color.white : Color.white.opacity(0.28))
          .frame(width: 2.5, height: height)
      }
    }
    .frame(width: 14, height: 14)
  }
}

struct DopeExplicitMark: View {
  var body: some View {
    Text("E")
      .font(.system(size: 8, weight: .black, design: .rounded))
      .padding(.horizontal, 3)
      .padding(.vertical, 1)
      .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 2))
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

struct DopeArtworkFill: View {
  let snapshot: DopeWidgetSnapshot

  var body: some View {
    Group {
      if let image = artworkImage(snapshot.artworkFileName) {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        ZStack {
          LinearGradient(
            colors: [Color(red: 0.44, green: 0.01, blue: 0.01), .black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
          Image(systemName: "music.note")
            .font(.system(size: 52, weight: .black))
            .foregroundStyle(.white.opacity(0.5))
        }
      }
    }
    .clipped()
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
    HStack(spacing: 5) {
      SourceLogoMark(sourceType: snapshot.sourceType)
        .frame(width: 15, height: 15)
      Text(sourceTitle(snapshot.sourceType))
        .font(.caption2.weight(.black))
        .lineLimit(1)
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 7)
    .padding(.vertical, 4)
    .background(sourceGradient(snapshot.sourceType), in: Capsule())
    .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
  }
}

struct SourceLogoMark: View {
  let sourceType: String

  var body: some View {
    ZStack {
      switch sourceType {
      case "appleMusic":
        Image(systemName: "music.note.list")
          .font(.system(size: 11, weight: .black))
      case "navidrome":
        NavidromeWidgetMark()
      case "jellyfin":
        JellyfinWidgetMark()
      case "remote":
        Image(systemName: "globe")
          .font(.system(size: 11, weight: .black))
      case "mp3":
        Image(systemName: "doc.text.fill")
          .font(.system(size: 11, weight: .black))
      default:
        Text("d")
          .font(.system(size: 11, weight: .black))
      }
    }
  }
}

struct NavidromeWidgetMark: View {
  var body: some View {
    Canvas { context, size in
      var path = Path()
      let centerY = size.height / 2
      for index in 0..<3 {
        let x = 1 + CGFloat(index) * size.width / 3.5
        path.move(to: CGPoint(x: x, y: centerY))
        path.addQuadCurve(
          to: CGPoint(x: x + 4, y: centerY),
          control: CGPoint(x: x + 2, y: 1)
        )
        path.addQuadCurve(
          to: CGPoint(x: x + 8, y: centerY),
          control: CGPoint(x: x + 6, y: size.height - 1)
        )
      }
      context.stroke(path, with: .color(.white), lineWidth: 1.5)
    }
  }
}

struct JellyfinWidgetMark: View {
  var body: some View {
    ZStack {
      TriangleShape()
        .fill(.white.opacity(0.96))
      TriangleShape()
        .fill(.black.opacity(0.24))
        .scaleEffect(0.45)
        .offset(y: 2)
    }
  }
}

struct TriangleShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.midX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}


struct DopeProgressBar: View {
  let snapshot: DopeWidgetSnapshot

  var body: some View {
    let duration = max(snapshot.durationSeconds ?? 0, 0)
    let position = min(max(snapshot.positionSeconds ?? 0, 0), max(duration, 1))
    let progress = duration > 0 ? CGFloat(position) / CGFloat(duration) : 0
    VStack(alignment: .leading, spacing: 3) {
      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          Capsule().fill(.white.opacity(0.16))
          Capsule()
            .fill(.white.opacity(snapshot.isPlaying ? 0.9 : 0.45))
            .frame(width: max(geometry.size.width * progress, duration > 0 ? 4 : 0))
        }
      }
      .frame(height: 5)
      if duration > 0 {
        HStack {
          Text(timeText(position))
          Spacer()
          Text(timeText(duration))
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(.secondary)
      }
    }
  }
}

struct DopeControlRow: View {
  let snapshot: DopeWidgetSnapshot

  var body: some View {
    HStack(spacing: 18) {
      Link(destination: dopeWidgetURL("action/previous")) {
        Image(systemName: "backward.end.fill")
      }
      Link(destination: dopeWidgetURL("action/play-pause")) {
        Image(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill")
          .frame(width: 28, height: 28)
          .background(.white, in: Circle())
          .foregroundStyle(.black)
      }
      Link(destination: dopeWidgetURL("action/next")) {
        Image(systemName: "forward.end.fill")
      }
      Spacer()
      Text(queueText(snapshot))
        .font(.caption2.monospacedDigit().weight(.black))
        .foregroundStyle(.white.opacity(0.42))
    }
    .font(.headline.weight(.black))
    .foregroundStyle(.white)
  }
}

private func dopeWidgetURL(_ target: String) -> URL {
  URL(string: "dopi://\(target)") ?? URL(string: "dopi://now-playing")!
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
  default: return "doPi"
  }
}

private func sourceGradient(_ source: String) -> LinearGradient {
  switch source {
  case "appleMusic":
    return LinearGradient(colors: [.pink, .purple, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
  case "navidrome":
    return LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
  case "jellyfin":
    return LinearGradient(colors: [.purple, .indigo, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
  case "remote":
    return LinearGradient(colors: [.green, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
  case "mp3":
    return LinearGradient(colors: [.gray, .black.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
  default:
    return LinearGradient(colors: [.gray, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
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


private func timeText(_ seconds: Int) -> String {
  let safeSeconds = max(seconds, 0)
  return String(format: "%d:%02d", safeSeconds / 60, safeSeconds % 60)
}

private func queueText(_ snapshot: DopeWidgetSnapshot) -> String {
  guard snapshot.queueCount > 0 else { return "No Queue" }
  return "\(snapshot.queueIndex)/\(snapshot.queueCount)"
}

private func eqStatus(_ snapshot: DopeWidgetSnapshot) -> String {
  if snapshot.sourceType == "appleMusic" { return "Apple Music bypasses EQ" }
  if snapshot.eqSupported { return "EQ active for this source" }
  return "Open doPi to choose music"
}

private func gainText(_ gain: Double) -> String {
  String(format: "%+.1f dB", gain)
}

private func eqBandGradient(_ index: Int) -> LinearGradient {
  let color: Color
  if index <= 2 {
    color = Color(red: 0.18, green: 0.68, blue: 1.0)
  } else if index <= 6 {
    color = Color(red: 1.0, green: 0.48, blue: 0.16)
  } else {
    color = Color(red: 0.18, green: 0.88, blue: 0.72)
  }
  return LinearGradient(
    colors: [color.opacity(0.45), color],
    startPoint: .bottom,
    endPoint: .top
  )
}
