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
  let themePrimaryColor: Int?
  let themeSecondaryColor: Int?
  let frameGradientStart: Int?
  let frameGradientEnd: Int?
  let controlBackgroundColor: Int?
  let controlBorderColor: Int?
  let innerButtonGradientStart: Int?
  let innerButtonGradientEnd: Int?
  let buttonAccentColor: Int?
  let buttonIconColor: Int?
  let themeIsDark: Bool?

  var theme: WidgetTheme { WidgetTheme(snapshot: self) ?? .fallback }

  static let empty = DopeWidgetSnapshot(
    schemaVersion: 3,
    trackTitle: "Open ClassiPod",
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
    deepLink: "dope://now-playing",
    queuePreview: [],
    themePrimaryColor: nil,
    themeSecondaryColor: nil,
    frameGradientStart: nil,
    frameGradientEnd: nil,
    controlBackgroundColor: nil,
    controlBorderColor: nil,
    innerButtonGradientStart: nil,
    innerButtonGradientEnd: nil,
    buttonAccentColor: nil,
    buttonIconColor: nil,
    themeIsDark: nil
  )
}

/// Device colors from the widget snapshot. The shell and click wheel follow
/// the user's theme. The menu LCD stays the classic white screen, light
/// title bar, and glossy blue selection shown in the app.
struct WidgetTheme: Hashable {
  let primary: Color
  let secondary: Color
  let frameStart: Color
  let frameEnd: Color
  let controlBackground: Color
  let controlBorder: Color
  let innerButtonStart: Color
  let innerButtonEnd: Color
  let buttonAccent: Color
  let buttonIcon: Color
  let isDark: Bool

  /// Charcoal device from `DeviceColor.black`, matching the app screenshots
  /// until a snapshot arrives.
  static let fallback = WidgetTheme(
    primary: Color(argb: 0xFF939295),
    secondary: Color(argb: 0xFF262527),
    frameStart: Color(argb: 0xFF939295),
    frameEnd: Color(argb: 0xFF262527),
    controlBackground: Color(argb: 0xFF212122),
    controlBorder: Color(argb: 0xFF000000),
    innerButtonStart: Color(argb: 0xFF282829),
    innerButtonEnd: Color(argb: 0xFF676467),
    buttonAccent: .white,
    buttonIcon: .white,
    isDark: true
  )

  /// Classic menu colors from `AppPalette`, independent of the shell.
  static let menuBlueTop = Color(argb: 0xFFADDBF7)
  static let menuBlue = Color(argb: 0xFF70A9DB)
  static let menuBlueBottom = Color(argb: 0xFF5382C9)
  static let menuBlueEdge = Color(argb: 0xFF2F4A81)
  static let titleBarTop = Color(argb: 0xFFFCFCFC)
  static let titleBarBottom = Color(argb: 0xFFB7B9BA)
  static let titleBarLine = Color(argb: 0xFF71797B)

  init?(snapshot: DopeWidgetSnapshot) {
    guard
      let frameStart = snapshot.frameGradientStart,
      let frameEnd = snapshot.frameGradientEnd,
      let controlBackground = snapshot.controlBackgroundColor,
      let controlBorder = snapshot.controlBorderColor,
      let innerStart = snapshot.innerButtonGradientStart,
      let innerEnd = snapshot.innerButtonGradientEnd,
      let accent = snapshot.buttonAccentColor,
      let icon = snapshot.buttonIconColor
    else {
      return nil
    }
    let frameStartColor = Color(argb: frameStart)
    let frameEndColor = Color(argb: frameEnd)
    self.frameStart = frameStartColor
    self.frameEnd = frameEndColor
    self.primary = Color(argb: snapshot.themePrimaryColor ?? frameStart)
    self.secondary = Color(argb: snapshot.themeSecondaryColor ?? frameEnd)
    self.controlBackground = Color(argb: controlBackground)
    self.controlBorder = Color(argb: controlBorder)
    self.innerButtonStart = Color(argb: innerStart)
    self.innerButtonEnd = Color(argb: innerEnd)
    self.buttonAccent = Color(argb: accent)
    self.buttonIcon = Color(argb: icon)
    if let isDark = snapshot.themeIsDark {
      self.isDark = isDark
    } else {
      let start = relativeLuminance(of: frameStart)
      let end = relativeLuminance(of: frameEnd)
      self.isDark = ((start + end) / 2) < 0.52
    }
  }

  init(
    primary: Color,
    secondary: Color,
    frameStart: Color,
    frameEnd: Color,
    controlBackground: Color,
    controlBorder: Color,
    innerButtonStart: Color,
    innerButtonEnd: Color,
    buttonAccent: Color,
    buttonIcon: Color,
    isDark: Bool
  ) {
    self.primary = primary
    self.secondary = secondary
    self.frameStart = frameStart
    self.frameEnd = frameEnd
    self.controlBackground = controlBackground
    self.controlBorder = controlBorder
    self.innerButtonStart = innerButtonStart
    self.innerButtonEnd = innerButtonEnd
    self.buttonAccent = buttonAccent
    self.buttonIcon = buttonIcon
    self.isDark = isDark
  }

  var frameGradient: LinearGradient {
    LinearGradient(colors: [frameStart, frameEnd], startPoint: .top, endPoint: .bottom)
  }

  var innerButtonGradient: LinearGradient {
    LinearGradient(
      colors: [innerButtonStart, innerButtonEnd],
      startPoint: .top,
      endPoint: .bottom
    )
  }

  var titleBarGradient: LinearGradient {
    LinearGradient(
      colors: [Self.titleBarTop, Self.titleBarBottom],
      startPoint: .top,
      endPoint: .bottom
    )
  }

  var selectionGradient: LinearGradient {
    LinearGradient(
      colors: [Self.menuBlueTop, Self.menuBlue, Self.menuBlueBottom, Self.menuBlueEdge],
      startPoint: .top,
      endPoint: .bottom
    )
  }

  /// The menu LCD in the screenshots stays white on every device color.
  var screenBackground: Color { .white }
  var primaryText: Color { .black }
  var secondaryText: Color { Color.black.opacity(0.55) }
  var titleText: Color { Color(argb: 0xFF1C1C1E) }
  var selectionText: Color { .white }
  var hairline: Color { Color.black.opacity(0.08) }
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
    .configurationDisplayName("ClassiPod Now Playing")
    .description("Show your current ClassiPod song, source, and quick controls.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    .contentMarginsDisabled()
  }
}

struct DopeMiniIpodWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: DopeWidgetKind.miniIpod, provider: DopeTimelineProvider()) { entry in
      DopeMiniIpodView(entry: entry)
    }
    .configurationDisplayName("ClassiPod Mini iPod")
    .description("A mini iPod-style companion for ClassiPod.")
    .supportedFamilies([.systemMedium, .systemLarge])
    .contentMarginsDisabled()
  }
}

struct DopeQueueWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: DopeWidgetKind.queue, provider: DopeTimelineProvider()) { entry in
      DopeQueueView(entry: entry)
    }
    .configurationDisplayName("ClassiPod Queue")
    .description("Preview what is playing next in ClassiPod.")
    .supportedFamilies([.systemLarge])
    .contentMarginsDisabled()
  }
}

struct DopeEqWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: DopeWidgetKind.eq, provider: DopeTimelineProvider()) { entry in
      DopeEqView(entry: entry)
    }
    .configurationDisplayName("ClassiPod EQ")
    .description("Show EQ and source support for the current ClassiPod song.")
    .supportedFamilies([.systemSmall, .systemMedium])
    .contentMarginsDisabled()
  }
}

struct DopeNowPlayingView: View {
  @Environment(\.widgetFamily) private var family
  let entry: DopeWidgetEntry

  private var theme: WidgetTheme { entry.snapshot.theme }

  var body: some View {
    Group {
      if family == .systemSmall {
        smallLayout
      } else {
        wideLayout
      }
    }
    .containerBackground(for: .widget) { theme.frameGradient }
    .widgetURL(dopeWidgetURL("now-playing"))
  }

  private var smallLayout: some View {
    ZStack(alignment: .bottomLeading) {
      DopeArtworkFill(snapshot: entry.snapshot, theme: theme)
      LinearGradient(
        colors: [.clear, theme.frameEnd.opacity(0.2), Color.black.opacity(0.78)],
        startPoint: .top,
        endPoint: .bottom
      )
      VStack(alignment: .leading, spacing: 5) {
        HStack {
          DopeWordmark(compact: true, theme: theme, onArtwork: true)
          Spacer()
          DopePlayingPulse(isPlaying: entry.snapshot.isPlaying, color: .white)
        }
        Spacer()
        Text(entry.snapshot.trackTitle)
          .font(.system(size: 16, weight: .semibold))
          .lineLimit(2)
        HStack(spacing: 5) {
          Text(entry.snapshot.artistName ?? "Unknown Artist")
            .lineLimit(1)
          if entry.snapshot.isExplicit { DopeExplicitMark(theme: theme, onDark: true) }
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.white.opacity(0.82))
      }
      .foregroundStyle(.white)
      .padding(13)
    }
  }

  private var wideLayout: some View {
    ZStack {
      theme.frameGradient
      VStack(spacing: 10) {
        VStack(spacing: 0) {
          ThemedTitleBar(title: "Now Playing", isPlaying: entry.snapshot.isPlaying)
          HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
              HStack(spacing: 4) {
                Text(entry.snapshot.trackTitle)
                  .font(.system(size: 13, weight: .bold))
                  .lineLimit(1)
                Spacer(minLength: 2)
                ClassicChevron()
              }
              .foregroundStyle(.white)
              .padding(.horizontal, 6)
              .frame(height: 26)
              .background(ThemedSelectionBackground())
              Text(entry.snapshot.artistName ?? "Unknown Artist")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.black)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.top, 4)
              if entry.snapshot.isExplicit {
                DopeExplicitMark(theme: theme, onDark: false)
                  .padding(.horizontal, 6)
                  .padding(.top, 3)
              }
              Spacer(minLength: 0)
            }
            DopeArtwork(
              snapshot: entry.snapshot,
              theme: theme,
              size: family == .systemLarge ? 88 : 72
            )
            .padding(4)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
          .background(.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.72), lineWidth: 2))
        DopeProgressBar(snapshot: entry.snapshot, theme: theme)
        DopeControlRow(snapshot: entry.snapshot, theme: theme)
        if family == .systemLarge {
          DopeCompactQueue(snapshot: entry.snapshot, theme: theme)
        }
      }
      .padding(12)
    }
  }
}

struct DopeMiniIpodView: View {
  @Environment(\.widgetFamily) private var family
  let entry: DopeWidgetEntry

  private var theme: WidgetTheme { entry.snapshot.theme }

  var body: some View {
    ZStack {
      theme.frameGradient
      if family == .systemLarge {
        VStack(spacing: 14) {
          deviceScreen
          DopeClickWheel(snapshot: entry.snapshot, theme: theme, diameter: 168)
        }
        .padding(16)
      } else {
        HStack(spacing: 14) {
          deviceScreen
          DopeClickWheel(snapshot: entry.snapshot, theme: theme, diameter: 124)
        }
        .padding(14)
      }
    }
    .containerBackground(for: .widget) { theme.frameGradient }
    .widgetURL(dopeWidgetURL("now-playing"))
  }

  private var deviceScreen: some View {
    Link(destination: dopeWidgetURL("now-playing")) {
      VStack(spacing: 0) {
        ThemedTitleBar(title: "Music", isPlaying: entry.snapshot.isPlaying)
        HStack(spacing: 0) {
          VStack(spacing: 0) {
            HStack(spacing: 4) {
              Text(entry.snapshot.trackTitle)
                .font(.system(size: family == .systemLarge ? 13 : 11, weight: .bold))
                .lineLimit(1)
              Spacer(minLength: 2)
              ClassicChevron()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(height: family == .systemLarge ? 26 : 22)
            .background(ThemedSelectionBackground())
            Text(entry.snapshot.artistName ?? "Unknown Artist")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(.black)
              .lineLimit(1)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 6)
              .padding(.top, 4)
            Spacer(minLength: 0)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          DopeArtwork(
            snapshot: entry.snapshot,
            theme: theme,
            size: family == .systemLarge ? 92 : 64
          )
          .padding(4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white)
      }
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .stroke(Color.black.opacity(0.72), lineWidth: 2)
      )
    }
  }
}

struct DopeQueueView: View {
  let entry: DopeWidgetEntry

  private var theme: WidgetTheme { entry.snapshot.theme }

  var body: some View {
    VStack(spacing: 0) {
      ThemedTitleBar(title: "Queue", isPlaying: entry.snapshot.isPlaying)
      Link(destination: dopeWidgetURL("now-playing")) {
        HStack(spacing: 8) {
          Text(entry.snapshot.trackTitle)
            .font(.system(size: 15, weight: .bold))
            .lineLimit(1)
          Spacer(minLength: 4)
          ClassicChevron()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(ThemedSelectionBackground())
      }

      VStack(spacing: 0) {
        if entry.snapshot.queuePreview.isEmpty {
          Spacer()
          Text("Queue empty")
            .font(.caption.weight(.medium))
            .foregroundStyle(theme.secondaryText)
          Spacer()
        } else {
          ForEach(Array(entry.snapshot.queuePreview.prefix(3).enumerated()), id: \.offset) { index, item in
            DopeQueueRow(item: item, theme: theme, selected: false)
            if index < min(entry.snapshot.queuePreview.count, 3) - 1 {
              Rectangle().fill(theme.hairline).frame(height: 1)
            }
          }
          Spacer(minLength: 0)
        }
      }
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(theme.screenBackground)
    }
    .background(.white)
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.72), lineWidth: 2))
    .padding(10)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(theme.frameGradient)
    .containerBackground(for: .widget) { theme.frameGradient }
    .widgetURL(dopeWidgetURL("queue"))
  }
}

struct DopeEqView: View {
  @Environment(\.widgetFamily) private var family
  let entry: DopeWidgetEntry

  private var theme: WidgetTheme { entry.snapshot.theme }

  var body: some View {
    ZStack {
      theme.frameGradient
      VStack(spacing: 0) {
        ThemedTitleBar(title: "EQ", isPlaying: entry.snapshot.isPlaying)
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
          Text(entry.snapshot.eqName)
            .font(.system(size: family == .systemSmall ? 15 : 17, weight: .bold))
            .foregroundStyle(.black)
            .lineLimit(1)
          DopeEqGraph(snapshot: entry.snapshot, theme: theme, compact: family == .systemSmall)
          Text(eqStatus(entry.snapshot))
            .font(.caption2.weight(.medium))
            .foregroundStyle(Color.black.opacity(0.55))
            .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white)
      }
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.72), lineWidth: 2))
      .padding(10)
    }
    .containerBackground(for: .widget) { theme.frameGradient }
    .widgetURL(dopeWidgetURL("eq"))
  }
}

struct ThemedTitleBar: View {
  let title: String
  let isPlaying: Bool

  var body: some View {
    HStack(spacing: 6) {
      Text(title)
        .font(.system(size: 13, weight: .bold))
        .lineLimit(1)
      Spacer(minLength: 4)
      Image(systemName: isPlaying ? "pause.fill" : "play.fill")
        .font(.system(size: 8, weight: .bold))
        .foregroundStyle(WidgetTheme.menuBlueBottom)
      ClassicBatteryMark()
    }
    .foregroundStyle(Color(argb: 0xFF1C1C1E))
    .padding(.horizontal, 8)
    .frame(maxWidth: .infinity)
    .frame(height: 22)
    .background(
      LinearGradient(
        colors: [WidgetTheme.titleBarTop, WidgetTheme.titleBarBottom],
        startPoint: .top,
        endPoint: .bottom
      )
    )
    .overlay(alignment: .bottom) {
      Rectangle().fill(WidgetTheme.titleBarLine).frame(height: 0.5)
    }
  }
}

struct ClassicBatteryMark: View {
  var body: some View {
    HStack(spacing: 1) {
      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: 1.5)
          .stroke(Color(argb: 0xFF3A3A3C), lineWidth: 0.7)
        RoundedRectangle(cornerRadius: 0.6)
          .fill(Color(argb: 0xFF7DA954))
          .padding(1.2)
      }
      .frame(width: 16, height: 8)
      RoundedRectangle(cornerRadius: 0.4)
        .fill(Color(argb: 0xFF3A3A3C))
        .frame(width: 1.4, height: 3)
    }
  }
}

struct ClassicChevron: View {
  var body: some View {
    ZStack {
      Circle().fill(WidgetTheme.menuBlueBottom)
      Image(systemName: "chevron.right")
        .font(.system(size: 8, weight: .bold))
        .foregroundStyle(.white)
    }
    .frame(width: 15, height: 15)
  }
}

struct ThemedSelectionBackground: View {
  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          WidgetTheme.menuBlueTop,
          WidgetTheme.menuBlue,
          WidgetTheme.menuBlueBottom,
          WidgetTheme.menuBlueEdge,
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      LinearGradient(
        colors: [Color.white.opacity(0.55), Color.white.opacity(0)],
        startPoint: .top,
        endPoint: .center
      )
    }
  }
}

struct DopeCompactQueue: View {
  let snapshot: DopeWidgetSnapshot
  let theme: WidgetTheme

  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(snapshot.queuePreview.prefix(2).enumerated()), id: \.offset) { index, item in
        DopeQueueRow(item: item, theme: theme, selected: false)
        if index == 0 { Rectangle().fill(theme.hairline).frame(height: 1) }
      }
    }
    .padding(.horizontal, 8)
    .background(theme.screenBackground, in: RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.controlBorder.opacity(0.7), lineWidth: 1))
  }
}

struct DopeQueueRow: View {
  let item: DopeWidgetSnapshot.QueueItem
  let theme: WidgetTheme
  let selected: Bool

  var body: some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 1) {
        Text(item.title)
          .font(.system(size: 14, weight: .bold))
          .lineLimit(1)
        Text(item.artist ?? sourceTitle(item.sourceType))
          .font(.caption2.weight(.medium))
          .foregroundStyle(selected ? theme.selectionText.opacity(0.8) : theme.secondaryText)
          .lineLimit(1)
      }
      Spacer(minLength: 4)
      if item.isExplicit { DopeExplicitMark(theme: theme, onDark: selected) }
    }
    .foregroundStyle(selected ? theme.selectionText : .black)
    .frame(minHeight: 32)
    .background {
      if selected {
        ThemedSelectionBackground()
      }
    }
  }
}

struct DopeClickWheel: View {
  let snapshot: DopeWidgetSnapshot
  let theme: WidgetTheme
  let diameter: CGFloat

  var body: some View {
    let glyph = Font.system(size: diameter * 0.09, weight: .light)
    ZStack {
      Circle()
        .fill(theme.controlBackground)
        .shadow(color: .black.opacity(theme.isDark ? 0.38 : 0.16), radius: 4, y: 2)
      Circle()
        .strokeBorder(Color.white.opacity(theme.isDark ? 0.16 : 0.45), lineWidth: 1)
      Circle().strokeBorder(theme.controlBorder.opacity(0.85), lineWidth: 1)

      Link(destination: dopeWidgetURL("queue")) {
        Text("MENU")
          .font(.system(size: diameter * 0.068, weight: .semibold))
          .tracking(0.8)
      }
      .foregroundStyle(theme.buttonIcon)
      .offset(y: -diameter * 0.33)

      Link(destination: dopeWidgetURL("action/previous")) {
        Image(systemName: "backward.end")
          .font(glyph)
      }
      .foregroundStyle(theme.buttonIcon)
      .offset(x: -diameter * 0.34)

      Link(destination: dopeWidgetURL("action/next")) {
        Image(systemName: "forward.end")
          .font(glyph)
      }
      .foregroundStyle(theme.buttonIcon)
      .offset(x: diameter * 0.34)

      Link(destination: dopeWidgetURL("action/play-pause")) {
        Image(systemName: snapshot.isPlaying ? "pause" : "play")
          .font(glyph)
      }
      .foregroundStyle(theme.buttonIcon)
      .offset(y: diameter * 0.34)

      Link(destination: dopeWidgetURL("now-playing")) {
        ZStack {
          Circle()
            .fill(theme.innerButtonEnd)
            .frame(width: diameter * 0.46, height: diameter * 0.46)
          Circle()
            .fill(theme.innerButtonStart)
            .overlay(Circle().stroke(Color.white.opacity(theme.isDark ? 0.28 : 0.55), lineWidth: 1))
            .frame(width: diameter * 0.34, height: diameter * 0.34)
        }
      }
    }
    .frame(width: diameter, height: diameter)
  }
}

struct DopeEqGraph: View {
  let snapshot: DopeWidgetSnapshot
  let theme: WidgetTheme
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
            .fill(theme.hairline.opacity(row == 2 ? 1 : 0.55))
            .frame(height: 1)
            .offset(y: (CGFloat(row) - 2) * geometry.size.height / 4)
        }
        HStack(alignment: .center, spacing: compact ? 3 : 5) {
          ForEach(Array(gains.enumerated()), id: \.offset) { _, gain in
            VStack(spacing: 0) {
              Spacer(minLength: 0)
              RoundedRectangle(cornerRadius: 1.5)
                .fill(
                  LinearGradient(
                    colors: [WidgetTheme.menuBlue, WidgetTheme.menuBlueBottom],
                    startPoint: .bottom,
                    endPoint: .top
                  )
                )
                .frame(height: max(3, CGFloat(abs(gain)) / 12 * geometry.size.height * 0.43))
                .offset(
                  y: gain >= 0
                    ? -CGFloat(abs(gain)) / 12 * geometry.size.height * 0.215
                    : CGFloat(abs(gain)) / 12 * geometry.size.height * 0.215
                )
              Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
          }
        }
      }
    }
    .frame(height: compact ? 54 : 72)
    .padding(.horizontal, 8)
    .background(theme.screenBackground, in: RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.controlBorder.opacity(0.8), lineWidth: 1))
  }
}

struct DopeWordmark: View {
  let compact: Bool
  let theme: WidgetTheme
  let onArtwork: Bool

  var body: some View {
    Text("ClassiPod")
      .font(.system(size: compact ? 12 : 13, weight: .semibold))
      .foregroundStyle(onArtwork ? Color.white : (theme.isDark ? Color.white : theme.primaryText))
      .lineLimit(1)
  }
}

struct DopePlayingPulse: View {
  let isPlaying: Bool
  let color: Color

  var body: some View {
    HStack(alignment: .bottom, spacing: 2) {
      ForEach([7.0, 12.0, 9.0], id: \.self) { height in
        Capsule()
          .fill(isPlaying ? color : color.opacity(0.35))
          .frame(width: 2, height: height)
      }
    }
    .frame(width: 14, height: 14)
  }
}

struct DopeExplicitMark: View {
  let theme: WidgetTheme
  let onDark: Bool

  var body: some View {
    Text("E")
      .font(.system(size: 8, weight: .bold))
      .foregroundStyle(onDark ? Color.white.opacity(0.9) : theme.primaryText)
      .padding(.horizontal, 3)
      .padding(.vertical, 1)
      .background(
        (onDark ? Color.white.opacity(0.18) : theme.controlBorder.opacity(0.35)),
        in: RoundedRectangle(cornerRadius: 2)
      )
  }
}

struct DopeArtworkFill: View {
  let snapshot: DopeWidgetSnapshot
  let theme: WidgetTheme

  var body: some View {
    Group {
      if let image = artworkImage(snapshot.artworkFileName) {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        ZStack {
          theme.frameGradient
          Image(systemName: "music.note")
            .font(.system(size: 42, weight: .light))
            .foregroundStyle(theme.buttonIcon.opacity(0.85))
        }
      }
    }
    .clipped()
  }
}

struct DopeArtwork: View {
  let snapshot: DopeWidgetSnapshot
  let theme: WidgetTheme
  let size: CGFloat

  var body: some View {
    Group {
      if let image = artworkImage(snapshot.artworkFileName) {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        ZStack {
          RoundedRectangle(cornerRadius: 4).fill(theme.isDark ? theme.frameEnd : theme.controlBackground)
          Image(systemName: "music.note")
            .font(.system(size: size * 0.38, weight: .light))
            .foregroundStyle(theme.buttonAccent)
        }
      }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: 4))
    .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.controlBorder.opacity(0.8), lineWidth: 1))
  }
}

struct DopeSourceBadge: View {
  let snapshot: DopeWidgetSnapshot
  let theme: WidgetTheme

  var body: some View {
    HStack(spacing: 4) {
      SourceLogoMark(sourceType: snapshot.sourceType)
        .frame(width: 12, height: 12)
      Text(sourceTitle(snapshot.sourceType))
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
    }
    .foregroundStyle(theme.buttonAccent)
    .padding(.horizontal, 7)
    .padding(.vertical, 3)
    .background(theme.controlBackground.opacity(theme.isDark ? 0.35 : 0.72), in: Capsule())
    .overlay(Capsule().stroke(theme.controlBorder, lineWidth: 1))
  }
}

struct SourceLogoMark: View {
  let sourceType: String

  var body: some View {
    ZStack {
      switch sourceType {
      case "appleMusic":
        Image(systemName: "music.note.list")
          .font(.system(size: 10, weight: .semibold))
      case "navidrome":
        NavidromeWidgetMark()
      case "jellyfin":
        JellyfinWidgetMark()
      case "remote":
        Image(systemName: "globe")
          .font(.system(size: 10, weight: .semibold))
      case "mp3":
        Image(systemName: "doc.text")
          .font(.system(size: 10, weight: .semibold))
      default:
        Image(systemName: "music.note")
          .font(.system(size: 10, weight: .semibold))
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
      context.stroke(path, with: .foreground, lineWidth: 1.2)
    }
  }
}

struct JellyfinWidgetMark: View {
  var body: some View {
    TriangleShape()
      .stroke(style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
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
  let theme: WidgetTheme

  var body: some View {
    let duration = max(snapshot.durationSeconds ?? 0, 0)
    let position = min(max(snapshot.positionSeconds ?? 0, 0), max(duration, 1))
    let progress = duration > 0 ? CGFloat(position) / CGFloat(duration) : 0
    VStack(alignment: .leading, spacing: 3) {
      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          Capsule().fill(theme.controlBorder.opacity(0.55))
          Capsule()
            .fill(theme.buttonAccent)
            .frame(width: max(geometry.size.width * progress, duration > 0 ? 4 : 0))
        }
      }
      .frame(height: 4)
      if duration > 0 {
        HStack {
          Text(timeText(position))
          Spacer()
          Text(timeText(duration))
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(theme.isDark ? Color.white.opacity(0.7) : theme.secondaryText)
      }
    }
  }
}

struct DopeControlRow: View {
  let snapshot: DopeWidgetSnapshot
  let theme: WidgetTheme

  var body: some View {
    HStack(spacing: 18) {
      Link(destination: dopeWidgetURL("action/previous")) {
        Image(systemName: "backward.end")
      }
      Link(destination: dopeWidgetURL("action/play-pause")) {
        Image(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(theme.isDark ? theme.frameEnd : theme.screenBackground)
          .frame(width: 28, height: 28)
          .background(theme.buttonAccent, in: Circle())
      }
      Link(destination: dopeWidgetURL("action/next")) {
        Image(systemName: "forward.end")
      }
      Spacer()
      Text(queueText(snapshot))
        .font(.caption2.monospacedDigit().weight(.medium))
        .foregroundStyle(theme.isDark ? Color.white.opacity(0.65) : theme.secondaryText)
    }
    .font(.system(size: 16, weight: .light))
    .foregroundStyle(theme.buttonIcon)
  }
}

private func dopeWidgetURL(_ target: String) -> URL {
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
  case "appleMusic": return "Apple Music"
  case "navidrome": return "Navidrome"
  case "jellyfin": return "Jellyfin"
  case "remote": return "Remote"
  case "mp3": return "MP3"
  default: return "ClassiPod"
  }
}

private func timeText(_ seconds: Int) -> String {
  let safeSeconds = max(seconds, 0)
  return String(format: "%d:%02d", safeSeconds / 60, safeSeconds % 60)
}

private func queueText(_ snapshot: DopeWidgetSnapshot) -> String {
  guard snapshot.queueCount > 0 else { return "No queue" }
  return "\(snapshot.queueIndex)/\(snapshot.queueCount)"
}

private func eqStatus(_ snapshot: DopeWidgetSnapshot) -> String {
  if snapshot.sourceType == "appleMusic" { return "Apple Music bypasses EQ" }
  if snapshot.eqSupported { return "EQ active for this source" }
  return "Open ClassiPod to choose music"
}

private func gainText(_ gain: Double) -> String {
  String(format: "%+.1f dB", gain)
}

private extension Color {
  init(argb: Int) {
    let bits = UInt32(truncatingIfNeeded: argb)
    let alpha = Double((bits >> 24) & 0xFF) / 255
    let red = Double((bits >> 16) & 0xFF) / 255
    let green = Double((bits >> 8) & 0xFF) / 255
    let blue = Double(bits & 0xFF) / 255
    self.init(red: red, green: green, blue: blue, opacity: alpha == 0 ? 1 : alpha)
  }
}

private func relativeLuminance(of argb: Int) -> Double {
  let bits = UInt32(truncatingIfNeeded: argb)
  func channel(_ value: Double) -> Double {
    value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
  }
  let red = channel(Double((bits >> 16) & 0xFF) / 255)
  let green = channel(Double((bits >> 8) & 0xFF) / 255)
  let blue = channel(Double(bits & 0xFF) / 255)
  return 0.2126 * red + 0.7152 * green + 0.0722 * blue
}

private func relativeLuminance(of color: Color) -> Double {
  var red: CGFloat = 0
  var green: CGFloat = 0
  var blue: CGFloat = 0
  var alpha: CGFloat = 0
  UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
  func channel(_ value: CGFloat) -> Double {
    let unit = Double(value)
    return unit <= 0.04045 ? unit / 12.92 : pow((unit + 0.055) / 1.055, 2.4)
  }
  return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
}

private func blend(_ base: Color, _ other: Color, _ amount: Double) -> Color {
  let clamped = min(max(amount, 0), 1)
  var baseRed: CGFloat = 0
  var baseGreen: CGFloat = 0
  var baseBlue: CGFloat = 0
  var baseAlpha: CGFloat = 0
  var otherRed: CGFloat = 0
  var otherGreen: CGFloat = 0
  var otherBlue: CGFloat = 0
  var otherAlpha: CGFloat = 0
  UIColor(base).getRed(&baseRed, green: &baseGreen, blue: &baseBlue, alpha: &baseAlpha)
  UIColor(other).getRed(&otherRed, green: &otherGreen, blue: &otherBlue, alpha: &otherAlpha)
  return Color(
    red: Double(baseRed + (otherRed - baseRed) * clamped),
    green: Double(baseGreen + (otherGreen - baseGreen) * clamped),
    blue: Double(baseBlue + (otherBlue - baseBlue) * clamped),
    opacity: Double(baseAlpha + (otherAlpha - baseAlpha) * clamped)
  )
}
