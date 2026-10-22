//
//  WidgetSnapshot.swift
//  TrainingTimeline
//

import Foundation

/// Everything the widgets show, as the app last wrote it into the App Group.
///
/// The widget has no ESI and no SDE, so every name is resolved here and every moment is an
/// absolute date. A file of another `version`, or one that does not decode, is treated as absent.
public struct WidgetSnapshot: Codable, Sendable, Hashable {
    /// Bumped on any change of the format; an older or newer file is discarded.
    public static let currentVersion = 1

    public var version: Int
    /// The pilot selected in the app: what a widget nobody configured shows.
    public var activePilotID: Int64?
    /// Every signed-in pilot, in the app's order.
    public var pilots: [Pilot]

    public init(activePilotID: Int64?, pilots: [Pilot]) {
        version = Self.currentVersion
        self.activePilotID = activePilotID
        self.pilots = pilots
    }

    public subscript(pilotID: Int64) -> Pilot? {
        pilots.first { $0.id == pilotID }
    }

    // MARK: - Pilot

    public struct Pilot: Codable, Sendable, Hashable, Identifiable {
        /// The character id.
        public var id: Int64
        public var name: String
        /// File name of the portrait next to the snapshot; `nil` while the app has none.
        public var portraitFile: String?
        /// The skill queue as last fetched; `nil` while the app has fetched nothing for the
        /// pilot yet.
        public var training: Training?
        /// The first levels of the local training plan still to train, in plan order.
        public var plan: [PlanEntry]

        public init(id: Int64, name: String, portraitFile: String? = nil,
                    training: Training? = nil, plan: [PlanEntry] = []) {
            self.id = id
            self.name = name
            self.portraitFile = portraitFile
            self.training = training
            self.plan = plan
        }

        /// Up to two letters: the first of the first and of the last word.
        public var initials: String {
            let words = name.split(whereSeparator: \.isWhitespace)
            let letters = [words.first, words.count > 1 ? words.last : nil].compactMap { $0?.first }
            return String(letters).uppercased()
        }
    }

    // MARK: - Training

    public struct Training: Codable, Sendable, Hashable {
        /// When ESI handed this queue over — the age the widget reports.
        public var fetchedAt: Date
        /// The queue in ESI order, including entries that had already finished when fetched:
        /// the widget rolls through them as time passes.
        public var queue: [QueueEntry]
        /// When training stopped, for a queue that came back empty: the last finish the app
        /// saw before. `nil` when it never saw one.
        public var idleSince: Date?

        public init(fetchedAt: Date, queue: [QueueEntry], idleSince: Date? = nil) {
            self.fetchedAt = fetchedAt
            self.queue = queue
            self.idleSince = idleSince
        }
    }

    /// One level of one skill in the in-game queue.
    public struct QueueEntry: Codable, Sendable, Hashable {
        public var skillID: Int64
        public var name: String
        /// The level this entry trains to.
        public var level: Int
        /// Both `nil` when the queue is paused.
        public var startDate: Date?
        public var finishDate: Date?
        /// The points at the bottom and the top of `level`.
        public var levelStartSkillPoints: Int
        public var levelEndSkillPoints: Int
        /// The points the skill has at `startDate` — above `levelStartSkillPoints` for a level
        /// trained part of the way before. For a paused entry, what it holds now.
        public var trainingStartSkillPoints: Int
        /// Training time of what is left of the level: `finishDate - startDate` when dated, the
        /// app's estimate from the pilot's attributes when paused. `nil` when unknown.
        public var duration: TimeInterval?

        public init(skillID: Int64, name: String, level: Int,
                    startDate: Date?, finishDate: Date?,
                    levelStartSkillPoints: Int, levelEndSkillPoints: Int,
                    trainingStartSkillPoints: Int, duration: TimeInterval?) {
            self.skillID = skillID
            self.name = name
            self.level = level
            self.startDate = startDate
            self.finishDate = finishDate
            self.levelStartSkillPoints = levelStartSkillPoints
            self.levelEndSkillPoints = levelEndSkillPoints
            self.trainingStartSkillPoints = trainingStartSkillPoints
            self.duration = duration
        }
    }

    /// One level of the local training plan.
    public struct PlanEntry: Codable, Sendable, Hashable {
        public var skillID: Int64
        public var name: String
        public var level: Int
        /// Training time of the level for this pilot; `nil` when unknown.
        public var duration: TimeInterval?

        public init(skillID: Int64, name: String, level: Int, duration: TimeInterval?) {
            self.skillID = skillID
            self.name = name
            self.level = level
            self.duration = duration
        }
    }

    // MARK: - File

    private struct Header: Decodable {
        var version: Int
    }

    /// The snapshot in `data`, or `nil` for anything but a file of `currentVersion`.
    public static func decode(_ data: Data) -> WidgetSnapshot? {
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: data),
              header.version == currentVersion
        else { return nil }
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    public func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(self)
    }
}
