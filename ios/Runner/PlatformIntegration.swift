import Foundation
import AppIntents
import WidgetKit
import CarPlay

final class PlatformIntegrationCoordinator {
  static let shared = PlatformIntegrationCoordinator()

  private init() {}

  func refreshAll() {
    WidgetCenter.shared.reloadAllTimelines()
  }
}

// MARK: - Siri / App Intents

@available(iOS 16.0, *)
struct PlayCurrentTrackIntent: AppIntent {
  static var title: LocalizedStringResource = "Play Current Track"
  static var description = IntentDescription("Plays the current track from døPi.")

  func perform() async throws -> some IntentResult {
    PlatformIntegrationCoordinator.shared.refreshAll()
    return .result()
  }
}

@available(iOS 16.0, *)
struct PausePlaybackIntent: AppIntent {
  static var title: LocalizedStringResource = "Pause Playback"

  func perform() async throws -> some IntentResult {
    PlatformIntegrationCoordinator.shared.refreshAll()
    return .result()
  }
}

@available(iOS 16.0, *)
struct NextTrackIntent: AppIntent {
  static var title: LocalizedStringResource = "Next Track"

  func perform() async throws -> some IntentResult {
    PlatformIntegrationCoordinator.shared.refreshAll()
    return .result()
  }
}

@available(iOS 16.0, *)
struct PreviousTrackIntent: AppIntent {
  static var title: LocalizedStringResource = "Previous Track"

  func perform() async throws -> some IntentResult {
    PlatformIntegrationCoordinator.shared.refreshAll()
    return .result()
  }
}

// MARK: - CarPlay placeholders

final class DopiCarPlayRootTemplateProvider: NSObject {
  func makeTemplate() -> CPTemplate {
    let title = NSLocalizedString("døPi", comment: "CarPlay title")
    let item = CPListItem(text: title, detailText: "Library")
    item.handler = { _, completion in
      completion()
    }
    let section = CPListSection(items: [item])
    return CPListTemplate(title: title, sections: [section])
  }
}
