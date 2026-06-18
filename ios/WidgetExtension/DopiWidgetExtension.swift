import WidgetKit
import SwiftUI

@main
struct DopiWidgetExtension: WidgetBundle {
  var body: some Widget {
    DopiWidget()
  }
}

struct DopiWidget: Widget {
  let kind: String = "DopiWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: DopiWidgetProvider()) { entry in
      DopiWidgetView(entry: entry)
    }
    .configurationDisplayName("døPi")
    .description("Current track and library status.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
