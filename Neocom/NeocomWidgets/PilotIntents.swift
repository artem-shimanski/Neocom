import AppIntents
import TrainingTimeline
import WidgetKit

/// A signed-in pilot, as the widget's configuration lists them: the pilots of the snapshot the
/// app last wrote, nothing else — the extension has no account store of its own.
nonisolated struct PilotEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Pilot"
    static let defaultQuery = PilotQuery()

    /// The character id.
    let id: Int
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(_ pilot: WidgetSnapshot.Pilot) {
        id = Int(pilot.id)
        name = pilot.name
    }
}

nonisolated struct PilotQuery: EntityQuery {
    func entities(for identifiers: [Int]) async throws -> [PilotEntity] {
        guard let snapshot = WidgetStore.read() else { return [] }
        return identifiers.compactMap { snapshot[Int64($0)].map(PilotEntity.init) }
    }

    func suggestedEntities() async throws -> [PilotEntity] {
        WidgetStore.read()?.pilots.map(PilotEntity.init) ?? []
    }

    /// Unset is a choice of its own: the active pilot, whoever that is at the time.
    func defaultResult() async -> PilotEntity? { nil }
}

/// One pilot's queue. Left unset, the widget follows the pilot active in the app; a stack of
/// these, one per pilot, is how the pilots are switched by a swipe.
nonisolated struct SkillQueueIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Skill Queue"
    static let description = IntentDescription("The skill in training and when the queue runs out.")

    @Parameter(title: "Pilot")
    var pilot: PilotEntity?

    init() {}

    init(pilot: PilotEntity?) {
        self.pilot = pilot
    }
}

/// Several pilots in one widget. Left unset: the active pilot first, the others in the app's
/// order.
nonisolated struct PilotsIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Pilots"
    static let description = IntentDescription("Up to three pilots and when their queues run out.")

    @Parameter(title: "Pilots", size: 3)
    var pilots: [PilotEntity]?

    init() {}
}
