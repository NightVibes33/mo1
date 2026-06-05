import ActivityKit
import Flutter
import Foundation

enum MO1LiveActivityController {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "mo1/live_activity",
      binaryMessenger: messenger
    )

    channel.setMethodCallHandler { call, result in
      guard #available(iOS 16.1, *) else {
        result(call.method == "isAvailable" ? false : nil)
        return
      }

      let coordinator = MO1LiveActivityCoordinator.shared
      switch call.method {
      case "isAvailable":
        result(coordinator.isAvailable)
      case "update":
        guard let arguments = call.arguments as? [String: Any] else {
          result(FlutterError(
            code: "LIVE_ACTIVITY_BAD_ARGUMENTS",
            message: "Missing Live Activity payload.",
            details: nil
          ))
          return
        }

        Task {
          do {
            try await coordinator.update(arguments: arguments)
            await MainActor.run { result(nil) }
          } catch {
            await MainActor.run {
              result(FlutterError(
                code: "LIVE_ACTIVITY_UPDATE_FAILED",
                message: error.localizedDescription,
                details: nil
              ))
            }
          }
        }
      case "end":
        Task {
          await coordinator.end()
          await MainActor.run { result(nil) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

@available(iOS 16.1, *)
private final class MO1LiveActivityCoordinator {
  static let shared = MO1LiveActivityCoordinator()

  private var activity: Activity<MO1LiveActivityAttributes>?
  private var lastState = MO1LiveActivityAttributes.ContentState(
    title: "mo1",
    artist: "Local MP3",
    album: "Now Playing",
    isPlaying: false,
    progress: 0,
    elapsed: 0,
    duration: 0
  )

  var isAvailable: Bool {
    ActivityAuthorizationInfo().areActivitiesEnabled
  }

  private init() {}

  func update(arguments: [String: Any]) async throws {
    guard isAvailable else {
      return
    }

    let state = state(from: arguments)
    lastState = state

    if let activity {
      if #available(iOS 16.2, *) {
        let content = ActivityContent(
          state: state,
          staleDate: Date().addingTimeInterval(120)
        )
        await activity.update(content)
      } else {
        await activity.update(using: state)
      }
      return
    }

    let attributes = MO1LiveActivityAttributes(id: "mo1-now-playing")
    if #available(iOS 16.2, *) {
      let content = ActivityContent(
        state: state,
        staleDate: Date().addingTimeInterval(120)
      )
      activity = try Activity<MO1LiveActivityAttributes>.request(
        attributes: attributes,
        content: content,
        pushType: nil
      )
    } else {
      activity = try Activity<MO1LiveActivityAttributes>.request(
        attributes: attributes,
        contentState: state,
        pushType: nil
      )
    }
  }

  func end() async {
    guard let activity else {
      return
    }

    if #available(iOS 16.2, *) {
      await activity.end(
        ActivityContent(state: lastState, staleDate: nil),
        dismissalPolicy: .immediate
      )
    } else {
      await activity.end(using: lastState, dismissalPolicy: .immediate)
    }
    self.activity = nil
  }

  private func state(from arguments: [String: Any])
    -> MO1LiveActivityAttributes.ContentState
  {
    let duration = intValue(arguments["duration"])
    let elapsed = min(max(0, intValue(arguments["elapsed"])), max(0, duration))
    let suppliedProgress = doubleValue(arguments["progress"])
    let computedProgress = duration > 0
      ? Double(elapsed) / Double(duration)
      : suppliedProgress

    return MO1LiveActivityAttributes.ContentState(
      title: sanitizedString(arguments["title"], fallback: "Unknown Song"),
      artist: sanitizedString(arguments["artist"], fallback: "Unknown Artist"),
      album: sanitizedString(arguments["album"], fallback: "Unknown Album"),
      isPlaying: arguments["isPlaying"] as? Bool ?? false,
      progress: min(max(computedProgress, 0), 1),
      elapsed: elapsed,
      duration: max(0, duration)
    )
  }

  private func sanitizedString(_ value: Any?, fallback: String) -> String {
    guard let string = value as? String else {
      return fallback
    }

    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || trimmed.lowercased().hasPrefix("unknown ") {
      return fallback
    }
    return trimmed
  }

  private func intValue(_ value: Any?) -> Int {
    if let value = value as? Int {
      return value
    }
    if let value = value as? Double {
      return Int(value)
    }
    if let value = value as? NSNumber {
      return value.intValue
    }
    return 0
  }

  private func doubleValue(_ value: Any?) -> Double {
    if let value = value as? Double {
      return value
    }
    if let value = value as? Int {
      return Double(value)
    }
    if let value = value as? NSNumber {
      return value.doubleValue
    }
    return 0
  }
}
