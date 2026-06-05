import AVFoundation
import Flutter
import MusicKit
import SwiftUI
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    do {
      try AVAudioSession.sharedInstance().setCategory(
        .playback,
        mode: .default,
        options: [.allowAirPlay, .allowBluetoothA2DP]
      )
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      NSLog("mo1 audio session setup failed: \(error.localizedDescription)")
    }

    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      AppleMusicLookupChannel.register(with: controller.binaryMessenger)
      MO1LiveActivityController.register(with: controller.binaryMessenger)
      if let registrar = registrar(forPlugin: "ClassiPodNativeClickWheel") {
        registrar.register(
          NativeClickWheelViewFactory(),
          withId: "classipod/native_click_wheel"
        )
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

private enum AppleMusicLookupChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "mo1/apple_music",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "searchSongs" else {
        result(FlutterMethodNotImplemented)
        return
      }

      guard #available(iOS 15.0, *) else {
        result([])
        return
      }

      guard let arguments = call.arguments as? [String: Any],
            let query = arguments["query"] as? String else {
        result(FlutterError(
          code: "APPLE_MUSIC_BAD_ARGUMENTS",
          message: "Missing Apple Music search query.",
          details: nil
        ))
        return
      }

      let limit = arguments["limit"] as? Int ?? 10
      Task {
        do {
          let matches = try await searchSongs(
            query: query,
            limit: max(1, min(limit, 25))
          )
          await MainActor.run {
            result(matches)
          }
        } catch {
          await MainActor.run {
            result(FlutterError(
              code: "APPLE_MUSIC_SEARCH_FAILED",
              message: error.localizedDescription,
              details: nil
            ))
          }
        }
      }
    }
  }

  @available(iOS 15.0, *)
  private static func searchSongs(
    query: String,
    limit: Int
  ) async throws -> [[String: Any]] {
    var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
    request.limit = limit
    let response = try await request.response()
    let formatter = ISO8601DateFormatter()

    return response.songs.prefix(limit).map { song in
      var item: [String: Any] = [
        "id": song.id.rawValue,
        "title": song.title,
        "artist": song.artistName
      ]

      if let albumTitle = song.albumTitle, !albumTitle.isEmpty {
        item["album"] = albumTitle
      }
      if let artworkUrl = song.artwork?.url(width: 1200, height: 1200) {
        item["artworkUrl"] = artworkUrl.absoluteString
      }
      if !song.genreNames.isEmpty {
        item["genres"] = song.genreNames
      }
      if let releaseDate = song.releaseDate {
        item["releaseDate"] = formatter.string(from: releaseDate)
      }
      if let trackNumber = song.trackNumber {
        item["trackNumber"] = trackNumber
      }
      if let discNumber = song.discNumber {
        item["discNumber"] = discNumber
      }
      if let duration = song.duration {
        item["durationMs"] = Int(duration * 1000)
      }
      if let isrc = song.isrc, !isrc.isEmpty {
        item["isrc"] = isrc
      }

      return item
    }
  }
}

private final class NativeClickWheelViewFactory: NSObject, FlutterPlatformViewFactory {
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    NativeClickWheelPlatformView(frame: frame, arguments: args)
  }
}

private final class NativeClickWheelPlatformView: NSObject, FlutterPlatformView {
  private let containerView: UIView
  private let hostingController: UIHostingController<NativeClickWheelRootView>

  init(frame: CGRect, arguments args: Any?) {
    let config = NativeClickWheelConfig(arguments: args as? [String: Any])
    containerView = UIView(frame: frame)
    containerView.backgroundColor = .clear
    containerView.isOpaque = false
    containerView.isUserInteractionEnabled = false

    hostingController = UIHostingController(rootView: NativeClickWheelRootView(config: config))
    hostingController.view.backgroundColor = .clear
    hostingController.view.isOpaque = false
    hostingController.view.isUserInteractionEnabled = false
    hostingController.view.translatesAutoresizingMaskIntoConstraints = false

    super.init()

    containerView.addSubview(hostingController.view)
    NSLayoutConstraint.activate([
      hostingController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
      hostingController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
      hostingController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
      hostingController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
    ])
  }

  func view() -> UIView {
    containerView
  }
}

private struct NativeClickWheelConfig {
  let labelColor: Color
  let iconColor: Color
  let centerStartColor: Color
  let centerEndColor: Color
  let isDark: Bool
  let centerSizeRatio: CGFloat
  let menuText: String

  init(arguments: [String: Any]?) {
    labelColor = Color(argb: arguments?.argbValue("labelColor") ?? 0xFFFFFFFF)
    iconColor = Color(argb: arguments?.argbValue("iconColor") ?? 0xFFFFFFFF)
    centerStartColor = Color(argb: arguments?.argbValue("centerStartColor") ?? 0xFFFFFFFF)
    centerEndColor = Color(argb: arguments?.argbValue("centerEndColor") ?? 0xFFFFFFFF)
    isDark = arguments?["isDark"] as? Bool ?? false
    centerSizeRatio = arguments?.doubleValue("centerSizeRatio").map(CGFloat.init) ?? 0.36
    menuText = arguments?["menuText"] as? String ?? "MENU"
  }
}

private struct NativeClickWheelRootView: View {
  let config: NativeClickWheelConfig

  var body: some View {
    GeometryReader { proxy in
      let size = min(proxy.size.width, proxy.size.height)
      ZStack {
        if #available(iOS 26.0, *) {
          NativeClickWheelGlassView(config: config, size: size)
        } else {
          NativeClickWheelFallbackView(config: config, size: size)
        }
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
  }
}

@available(iOS 26.0, *)
private struct NativeClickWheelGlassView: View {
  let config: NativeClickWheelConfig
  let size: CGFloat

  var body: some View {
    let edge = max(size, 1)
    let centerSize = edge * config.centerSizeRatio

    GlassEffectContainer(spacing: edge * 0.045) {
      ZStack {
        Circle()
          .fill(Color.white.opacity(config.isDark ? 0.045 : 0.08))
          .overlay(
            Circle()
              .stroke(Color.white.opacity(config.isDark ? 0.78 : 0.9), lineWidth: 1.25)
          )
          .overlay(
            Circle()
              .stroke(
                LinearGradient(
                  colors: [
                    Color.white.opacity(0.95),
                    Color.white.opacity(0.15),
                    Color.black.opacity(config.isDark ? 0.16 : 0.05)
                  ],
                  startPoint: .topLeading,
                  endPoint: .bottomTrailing
                ),
                lineWidth: 1
              )
              .padding(edge * 0.025)
          )
          .overlay(
            Circle()
              .stroke(Color.white.opacity(config.isDark ? 0.12 : 0.2), lineWidth: 0.7)
              .padding(edge * 0.14)
          )
          .overlay(
            Circle()
              .stroke(Color.white.opacity(config.isDark ? 0.08 : 0.14), lineWidth: 0.7)
              .padding(edge * 0.25)
          )
          .overlay(
            RadialGradient(
              colors: [
                Color.white.opacity(config.isDark ? 0.16 : 0.32),
                Color.white.opacity(0.04),
                Color.black.opacity(config.isDark ? 0.12 : 0.045)
              ],
              center: .topLeading,
              startRadius: edge * 0.02,
              endRadius: edge * 0.76
            )
            .clipShape(Circle())
          )
          .glassEffect(.regular.tint(Color.white.opacity(config.isDark ? 0.05 : 0.12)), in: .circle)
          .shadow(color: Color.black.opacity(config.isDark ? 0.28 : 0.16), radius: edge * 0.055, y: edge * 0.032)

        NativeWheelLabels(config: config, size: edge)

        NativeCenterButton(config: config, centerSize: centerSize)
      }
      .frame(width: edge, height: edge)
    }
  }
}

private struct NativeClickWheelFallbackView: View {
  let config: NativeClickWheelConfig
  let size: CGFloat

  var body: some View {
    let edge = max(size, 1)
    let centerSize = edge * config.centerSizeRatio

    ZStack {
      Circle()
        .fill(.ultraThinMaterial)
        .overlay(Circle().fill(Color.white.opacity(config.isDark ? 0.04 : 0.13)))
        .overlay(Circle().stroke(Color.white.opacity(0.82), lineWidth: 1.1))
        .overlay(
          Circle()
            .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
            .padding(edge * 0.14)
        )
        .shadow(color: Color.black.opacity(config.isDark ? 0.28 : 0.15), radius: edge * 0.055, y: edge * 0.032)

      NativeWheelLabels(config: config, size: edge)
      NativeCenterButton(config: config, centerSize: centerSize)
    }
    .frame(width: edge, height: edge)
  }
}

private struct NativeCenterButton: View {
  let config: NativeClickWheelConfig
  let centerSize: CGFloat

  var body: some View {
    let circle = Circle()
    let gradient = LinearGradient(
      colors: [config.centerStartColor, config.centerEndColor],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )

    circle
      .fill(gradient)
      .overlay(
        circle.stroke(Color.white.opacity(0.62), lineWidth: 1)
      )
      .overlay(
        RadialGradient(
          colors: [Color.white.opacity(0.36), Color.white.opacity(0.0)],
          center: .topLeading,
          startRadius: 0,
          endRadius: centerSize * 0.9
        )
        .clipShape(circle)
      )
      .frame(width: centerSize, height: centerSize)
      .modifier(NativeCenterGlassModifier(tint: config.centerEndColor))
      .shadow(color: Color.black.opacity(config.isDark ? 0.24 : 0.16), radius: centerSize * 0.24, y: centerSize * 0.1)
  }
}

private struct NativeCenterGlassModifier: ViewModifier {
  let tint: Color

  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      content.glassEffect(.regular.tint(tint.opacity(0.18)).interactive(), in: .circle)
    } else {
      content
    }
  }
}

private struct NativeWheelLabels: View {
  let config: NativeClickWheelConfig
  let size: CGFloat

  var body: some View {
    ZStack {
      Text(config.menuText)
        .font(.system(size: size * 0.1, weight: .bold, design: .rounded))
        .foregroundStyle(config.labelColor)
        .position(x: size * 0.5, y: size * 0.12)

      NativePreviousIcon(color: config.iconColor)
        .frame(width: size * 0.092, height: size * 0.055)
        .position(x: size * 0.16, y: size * 0.51)

      NativeNextIcon(color: config.iconColor)
        .frame(width: size * 0.092, height: size * 0.055)
        .position(x: size * 0.84, y: size * 0.51)

      NativePlayPauseIcon(color: config.iconColor)
        .frame(width: size * 0.13, height: size * 0.068)
        .position(x: size * 0.5, y: size * 0.87)
    }
    .frame(width: size, height: size)
  }
}

private struct NativePreviousIcon: View {
  let color: Color

  var body: some View {
    GeometryReader { proxy in
      let w = proxy.size.width
      let h = proxy.size.height
      HStack(spacing: w * 0.03) {
        Rectangle()
          .fill(color)
          .frame(width: max(w * 0.04, 1), height: h * 0.82)
        NativeTriangle(direction: .left)
          .fill(color)
        NativeTriangle(direction: .left)
          .fill(color)
      }
    }
  }
}

private struct NativeNextIcon: View {
  let color: Color

  var body: some View {
    GeometryReader { proxy in
      let w = proxy.size.width
      let h = proxy.size.height
      HStack(spacing: w * 0.03) {
        NativeTriangle(direction: .right)
          .fill(color)
        NativeTriangle(direction: .right)
          .fill(color)
        Rectangle()
          .fill(color)
          .frame(width: max(w * 0.04, 1), height: h * 0.82)
      }
    }
  }
}

private struct NativePlayPauseIcon: View {
  let color: Color

  var body: some View {
    GeometryReader { proxy in
      let w = proxy.size.width
      let h = proxy.size.height
      HStack(spacing: w * 0.11) {
        NativeTriangle(direction: .right)
          .fill(color)
          .frame(width: w * 0.42, height: h)
        Rectangle()
          .fill(color)
          .frame(width: max(w * 0.08, 1), height: h)
        Rectangle()
          .fill(color)
          .frame(width: max(w * 0.08, 1), height: h)
      }
    }
  }
}

private enum NativeTriangleDirection {
  case left
  case right
}

private struct NativeTriangle: Shape {
  let direction: NativeTriangleDirection

  func path(in rect: CGRect) -> Path {
    var path = Path()
    switch direction {
    case .left:
      path.move(to: CGPoint(x: rect.minX, y: rect.midY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    case .right:
      path.move(to: CGPoint(x: rect.maxX, y: rect.midY))
      path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    }
    path.closeSubpath()
    return path
  }
}

private extension Dictionary where Key == String, Value == Any {
  func argbValue(_ key: String) -> Int? {
    if let value = self[key] as? Int {
      return value
    }
    if let value = self[key] as? Int64 {
      return Int(value)
    }
    if let value = self[key] as? NSNumber {
      return value.intValue
    }
    return nil
  }

  func doubleValue(_ key: String) -> Double? {
    if let value = self[key] as? Double {
      return value
    }
    if let value = self[key] as? NSNumber {
      return value.doubleValue
    }
    return nil
  }
}

private extension Color {
  init(argb: Int) {
    let alpha = Double((argb >> 24) & 0xFF) / 255.0
    let red = Double((argb >> 16) & 0xFF) / 255.0
    let green = Double((argb >> 8) & 0xFF) / 255.0
    let blue = Double(argb & 0xFF) / 255.0
    self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
  }
}
