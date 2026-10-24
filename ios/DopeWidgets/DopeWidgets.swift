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

/// Device colors from the widget snapshot. Missing theme data uses the
/// app's default silver device, not a decorative palette.
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

  static let fallback = WidgetTheme(
    primary: Color(argb: 0xFFF2F2F2),
    secondary: Color(argb: 0xFFADADAD),
    frameStart: Color(argb: 0xFFF2F2F2),
    frameEnd: Color(argb: 0xFFADADAD),
    controlBackground: Color(argb: 0xFFFFFFFF),
    controlBorder: Color(argb: 0xFFAEADAD),
    innerButtonStart: Color(argb: 0xFFB1B1B0),
    innerButtonEnd: Color(argb: 0xFFE1E1E1),
    buttonAccent: Color(argb: 0xFF8793A0),
    buttonIcon: Color(argb: 0xFF8793A0),
    isDark: false
  )

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
      colors: [frameStart, blend(frameStart, frameEnd, 0.55)],
      startPoint: .top,
      endPoint: .bottom
    )
  }

  var selectionGradient: LinearGradient {
    LinearGradient(
      colors: [selectionTop, selectionBottom],
      startPoint: .top,
      endPoint: .bottom
    )
  }

  var selectionTop: Color { blend(buttonAccent, .white, 0.38) }
  var selectionBottom: Color { blend(frameEnd, buttonAccent, 0.42) }

  /// LCD behind menus. Dark devices use the app's dark screen, not the shell.
  var screenBackground: Color {
    isDark ? Color(argb: 0xFF121212) : .white
  }

  var primaryText: Color {
    isDark ? Color(argb: 0xFFE6E7EA) : .black
  }

  var secondaryText: Color {
    isDark ? Color.white.opacity(0.62) : Color.black.opacity(0.55)
  }

  var titleText: Color { isDark ? .white : Color(argb: 0xFF111418) }

  var selectionText: Color {
    relativeLuminance(of: selectionBottom) > 0.62 ? .black : .white
  }

  var hairline: Color {
    isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
  }
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
      VStack(spacing: family == .systemLarge ? 12 : 10) {
        HStack(spacing: 12) {
          DopeArtwork(snapshot: entry.snapshot, theme: theme, size: family == .systemLarge ? 96 : 84)
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              DopeWordmark(compact: false, theme: theme, onArtwork: false)
              Spacer()
              DopePlayingPulse(isPlaying: entry.snapshot.isPlaying, color: theme.buttonAccent)
            }
            Spacer(minLength: 0)
            Text(entry.snapshot.trackTitle)
              .font(.system(size: family == .systemLarge ? 20 : 17, weight: .semibold))
              .foregroundStyle(theme.isDark ? Color.white : theme.primaryText)
              .lineLimit(2)
            HStack(spacing: 6) {
              Text(entry.snapshot.artistName ?? "Unknown Artist").lineLimit(1)
              if entry.snapshot.isExplicit { DopeExplicitMark(theme: theme, onDark: theme.isDark) }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(theme.isDark ? Color.white.opacity(0.72) : theme.secondaryText)
            DopeSourceBadge(snapshot: entry.snapshot, theme: theme)
          }
        }
        DopeProgressBar(snapshot: entry.snapshot, theme: theme)
        DopeControlRow(snapshot: entry.snapshot, theme: theme)
        if family == .systemLarge {
          DopeCompactQueue(snapshot: entry.snapshot, theme: theme)
        }
      }
      .padding(14)
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
        ThemedTitleBar(title: "ClassiPod", theme: theme) {
          DopePlayingPulse(isPlaying: entry.snapshot.isPlaying, color: theme.titleText)
        }
        HStack(spacing: 8) {
          DopeArtwork(snapshot: entry.snapshot, theme: theme, size: family == .systemLarge ? 86 : 58)
          VStack(alignment: .leading, spacing: 3) {
            Text(entry.snapshot.trackTitle)
              .font(.system(size: family == .systemLarge ? 16 : 13, weight: .semibold))
              .foregroundStyle(theme.primaryText)
              .lineLimit(2)
            Text(entry.snapshot.artistName ?? "Unknown Artist")
              .font(.caption2.weight(.medium))
              .foregroundStyle(theme.secondaryText)
              .lineLimit(2)
            Spacer(minLength: 0)
            Text(queueText(entry.snapshot))
              .font(.caption2.monospacedDigit().weight(.medium))
              .foregroundStyle(theme.secondaryText)
          }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.screenBackground)
      }
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .stroke(theme.controlBorder.opacity(0.9), lineWidth: 2)
      )
    }
  }
}

struct DopeQueueView: View {
  let entry: DopeWidgetEntry

  private var theme: WidgetTheme { entry.snapshot.theme }

  var body: some View {
    VStack(spacing: 0) {
      ThemedTitleBar(title: "Queue", theme: theme) {
        Text(queueText(entry.snapshot))
          .font(.caption2.monospacedDigit().weight(.semibold))
      }
      Link(destination: dopeWidgetURL("now-playing")) {
        HStack(spacing: 10) {
          DopeArtwork(snapshot: entry.snapshot, theme: theme, size: 52)
          VStack(alignment: .leading, spacing: 2) {
            Text("Now Playing")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(theme.selectionText.opacity(0.8))
            Text(entry.snapshot.trackTitle)
              .font(.headline.weight(.semibold))
              .lineLimit(1)
            Text(entry.snapshot.artistName ?? "Unknown Artist")
              .font(.caption.weight(.medium))
              .lineLimit(1)
          }
          Spacer(minLength: 4)
          Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
        }
        .foregroundStyle(theme.selectionText)
        .padding(.horizontal, 12)
        .frame(height: 76)
        .background(ThemedSelectionBackground(theme: theme))
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
            DopeQueueRow(index: index + 1, item: item, theme: theme, selected: false)
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
    .containerBackground(for: .widget) { theme.screenBackground }
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
      VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 10) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 1) {
            Text("Equalizer")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(theme.isDark ? Color.white.opacity(0.7) : theme.secondaryText)
            Text(entry.snapshot.eqName)
              .font(.system(size: family == .systemSmall ? 16 : 18, weight: .semibold))
              .foregroundStyle(theme.isDark ? Color.white : theme.primaryText)
              .lineLimit(1)
          }
          Spacer()
          DopeSourceBadge(snapshot: entry.snapshot, theme: theme)
        }
        DopeEqGraph(snapshot: entry.snapshot, theme: theme, compact: family == .systemSmall)
        HStack {
          Circle()
            .fill(entry.snapshot.eqSupported ? theme.buttonAccent : theme.controlBorder)
            .frame(width: 7, height: 7)
          Text(eqStatus(entry.snapshot))
            .font(.caption2.weight(.medium))
            .lineLimit(1)
          Spacer()
          if family != .systemSmall {
            Text("Preamp \(gainText(entry.snapshot.eqPreampDb ?? 0))")
              .font(.caption2.monospacedDigit())
          }
        }
        .foregroundStyle(theme.isDark ? Color.white.opacity(0.78) : theme.secondaryText)
      }
      .padding(12)
    }
    .containerBackground(for: .widget) { theme.frameGradient }
    .widgetURL(dopeWidgetURL("eq"))
  }
}

struct ThemedTitleBar<Trailing: View>: View {
  let title: String
  let theme: WidgetTheme
  @ViewBuilder var trailing: () -> Trailing

  var body: some View {
    HStack(spacing: 8) {
      Text(title)
        .font(.system(size: 13, weight: .bold))
        .lineLimit(1)
      Spacer(minLength: 4)
      trailing()
    }
    .foregroundStyle(theme.titleText)
    .padding(.horizontal, 10)
    .frame(maxWidth: .infinity)
    .frame(height: 28)
    .background(theme.titleBarGradient)
    .overlay(alignment: .bottom) {
      Rectangle().fill(theme.controlBorder.opacity(0.65)).frame(height: 1)
    }
  }
}

struct ThemedSelectionBackground: View {
  let theme: WidgetTheme

  var body: some View {
    ZStack {
      theme.selectionGradient
      LinearGradient(
        colors: [Color.white.opacity(0.42), Color.white.opacity(0)],
        startPoint: .top,
        endPoint: .center
      )
    }
    .overlay(alignment: .top) {
      Rectangle().fill(Color.white.opacity(0.55)).frame(height: 1)
    }
    .overlay(alignment: .bottom) {
      Rectangle().fill(theme.frameEnd.opacity(0.85)).frame(height: 1)
    }
  }
}

struct DopeCompactQueue: View {
  let snapshot: DopeWidgetSnapshot
  let theme: WidgetTheme

  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(snapshot.queuePreview.prefix(2).enumerated()), id: \.offset) { index, item in
        DopeQueueRow(index: index + 1, item: item, theme: theme, selected: false)
        if index == 0 { Rectangle().fill(theme.hairline).frame(height: 1) }
      }
    }
    .padding(.horizontal, 8)
    .background(theme.screenBackground, in: RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.controlBorder.opacity(0.7), lineWidth: 1))
  }
}

struct DopeQueueRow: View {
  let index: Int
  let item: DopeWidgetSnapshot.QueueItem
  let theme: WidgetTheme
  let selected: Bool

  var body: some View {
    HStack(spacing: 8) {
      Text(String(format: "%02d", index))
        .font(.caption2.monospacedDigit().weight(.medium))
        .foregroundStyle(selected ? theme.selectionText.opacity(0.75) : theme.secondaryText)
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 5) {
          Text(item.title)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
          if item.isExplicit { DopeExplicitMark(theme: theme, onDark: selected || theme.isDark) }
        }
        Text(item.artist ?? sourceTitle(item.sourceType))
          .font(.caption2.weight(.medium))
          .foregroundStyle(selected ? theme.selectionText.opacity(0.75) : theme.secondaryText)
          .lineLimit(1)
      }
      Spacer(minLength: 4)
      SourceLogoMark(sourceType: item.sourceType)
        .frame(width: 14, height: 14)
        .foregroundStyle(selected ? theme.selectionText : theme.buttonAccent)
    }
    .foregroundStyle(selected ? theme.selectionText : theme.primaryText)
    .frame(minHeight: 40)
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
        .strokeBorder(Color.black.opacity(theme.isDark ? 0.28 : 0.12), lineWidth: diameter * 0.035)
      Circle().strokeBorder(theme.controlBorder, lineWidth: 1)

      Link(destination: dopeWidgetURL("queue")) {
        Text("MENU")
          .font(.system(size: diameter * 0.07, weight: .semibold))
          .tracking(0.6)
      }
      .foregroundStyle(theme.buttonAccent)
      .offset(y: -diameter * 0.34)

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
        Circle()
          .fill(theme.innerButtonGradient)
          .overlay(Circle().stroke(theme.controlBorder, lineWidth: 1))
          .shadow(color: .black.opacity(0.16), radius: 1.5, y: 1)
          .frame(width: diameter * 0.38, height: diameter * 0.38)
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
                    colors: [theme.buttonAccent.opacity(0.45), theme.buttonAccent],
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
