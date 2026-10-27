import Foundation

/// Training durations, formatted the one way the app formats them.
///
/// Shared with the widget extension: `TrainingQueueView`, the skill screens and the widget all
/// read the same "2d 14h".
nonisolated enum TrainingTime {
    static func string(_ time: TimeInterval) -> String {
        // Two units is as much precision as an estimate deserves: "2d 14h", never "2d 14h 3m 7s".
        Duration.seconds(time).formatted(
            .units(allowed: [.days, .hours, .minutes, .seconds], width: .narrow, maximumUnitCount: 2)
        )
    }
}
