import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

@main
struct MO1LiveActivityBundle: WidgetBundle {
  var body: some Widget {
    MO1LiveActivityWidget()
  }
}

struct MO1LiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: MO1LiveActivityAttributes.self) { context in
      MO1LockScreenLiveActivityView(state: context.state)
        .activityBackgroundTint(.black.opacity(0.82))
        .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          VStack(alignment: .leading, spacing: 2) {
            Text(context.state.isPlaying ? "Playing" : "Paused")
              .font(.caption2.weight(.bold))
              .foregroundStyle(.mint)
            Text("mo1")
              .font(.headline.weight(.black))
              .foregroundStyle(.white)
          }
        }

        DynamicIslandExpandedRegion(.trailing) {
          Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
            .font(.title2.weight(.black))
            .foregroundStyle(.mint)
            .frame(width: 44, height: 44)
            .background(.white.opacity(0.12), in: Circle())
        }

        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 6) {
            Text(context.state.title)
              .font(.headline.weight(.black))
              .lineLimit(1)
            Text(context.state.artist)
              .font(.caption.weight(.semibold))
              .foregroundStyle(.white.opacity(0.72))
              .lineLimit(1)
            ProgressView(value: context.state.progress)
              .tint(.mint)
          }
          .foregroundStyle(.white)
        }
      } compactLeading: {
        Text("mo1")
          .font(.caption2.weight(.black))
          .foregroundStyle(.white)
      } compactTrailing: {
        Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
          .foregroundStyle(.mint)
      } minimal: {
        Image(systemName: "music.note")
          .foregroundStyle(.mint)
      }
      .keylineTint(.mint)
    }
  }
}

private struct MO1LockScreenLiveActivityView: View {
  let state: MO1LiveActivityAttributes.ContentState

  var body: some View {
    HStack(spacing: 14) {
      ZStack {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(
            LinearGradient(
              colors: [.white.opacity(0.24), .white.opacity(0.06)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
        Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
          .font(.title.weight(.black))
          .foregroundStyle(.mint)
      }
      .frame(width: 62, height: 62)

      VStack(alignment: .leading, spacing: 5) {
        Text(state.title)
          .font(.headline.weight(.black))
          .foregroundStyle(.white)
          .lineLimit(1)
        Text(state.artist)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.white.opacity(0.74))
          .lineLimit(1)
        ProgressView(value: state.progress)
          .tint(.mint)
        HStack {
          Text(timeString(state.elapsed))
          Spacer()
          Text(timeString(max(state.duration - state.elapsed, 0)))
        }
        .font(.caption2.monospacedDigit().weight(.bold))
        .foregroundStyle(.white.opacity(0.64))
      }
    }
    .padding(16)
    .background(
      LinearGradient(
        colors: [
          Color(red: 0.05, green: 0.08, blue: 0.10),
          Color(red: 0.02, green: 0.02, blue: 0.03)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    )
  }

  private func timeString(_ seconds: Int) -> String {
    let safeSeconds = max(seconds, 0)
    return "\(safeSeconds / 60):\(String(format: "%02d", safeSeconds % 60))"
  }
}
