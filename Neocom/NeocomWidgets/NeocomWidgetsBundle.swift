import SwiftUI
import TrainingTimeline
import WidgetKit

@main
struct NeocomWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SkillQueueWidget()
        PilotsWidget()
    }
}

/// One pilot's queue on the Home Screen and the Lock Screen. A tap opens the app (it has no
/// links into its screens to send the tap further).
struct SkillQueueWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.skillQueue, intent: SkillQueueIntent.self,
                               provider: SkillQueueProvider()) { entry in
            SkillQueueWidgetView(entry: entry)
        }
        .configurationDisplayName("Skill Queue")
        .description("The skill in training and when the queue runs out.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

/// Up to three pilots in one medium widget.
struct PilotsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.pilots, intent: PilotsIntent.self,
                               provider: PilotsProvider()) { entry in
            PilotsWidgetView(entry: entry)
        }
        .configurationDisplayName("Pilots")
        .description("Up to three pilots and when their queues run out.")
        .supportedFamilies([.systemMedium])
    }
}

