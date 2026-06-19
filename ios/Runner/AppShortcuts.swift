import AppIntents

@available(iOS 16.0, *)
struct DopiAppShortcutsProvider: AppShortcutsProvider {
  @AppShortcutsBuilder
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: PlayCurrentTrackIntent(),
      phrases: ["Play music in \(.applicationName)", "Resume playback in \(.applicationName)"],
      shortTitle: "Play",
      systemImageName: "play.fill"
    )
    AppShortcut(
      intent: PausePlaybackIntent(),
      phrases: ["Pause music in \(.applicationName)"],
      shortTitle: "Pause",
      systemImageName: "pause.fill"
    )
    AppShortcut(
      intent: NextTrackIntent(),
      phrases: ["Next track in \(.applicationName)"],
      shortTitle: "Next",
      systemImageName: "forward.fill"
    )
    AppShortcut(
      intent: PreviousTrackIntent(),
      phrases: ["Previous track in \(.applicationName)"],
      shortTitle: "Previous",
      systemImageName: "backward.fill"
    )
  }
}
