//
//  CharacterSnapshotTests.swift
//  TrainingKit
//

import Testing
import Foundation
import SDEKit
@testable import TrainingKit

@Suite("CharacterSnapshot")
struct CharacterSnapshotTests {
    @Test("round-trips through JSONEncoder/JSONDecoder unchanged")
    func roundTrip() throws {
        let snapshot = CharacterSnapshot(
            attributes: CharacterAttributes(charisma: 17, intelligence: 21, memory: 20,
                                            perception: 19, willpower: 23),
            implants: [TypeID(rawValue: 100), TypeID(rawValue: 101)],
            skills: [
                .init(skillID: TypeID(rawValue: 1), trainedLevel: 5, activeLevel: 4,
                      skillPoints: 256_000),
                .init(skillID: TypeID(rawValue: 2), trainedLevel: 3, activeLevel: 3,
                      skillPoints: 8_000),
            ],
            queue: [
                .init(skillID: TypeID(rawValue: 3), finishedLevel: 4, position: 0,
                      startDate: Date(timeIntervalSince1970: 1_700_000_000),
                      finishDate: Date(timeIntervalSince1970: 1_700_100_000),
                      levelStartSkillPoints: 1_000, levelEndSkillPoints: 256_000),
                // A later entry can have no dates or SP bounds yet.
                .init(skillID: TypeID(rawValue: 4), finishedLevel: 1, position: 1),
            ],
            totalSkillPoints: 12_345_678,
            unallocatedSkillPoints: 500
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(CharacterSnapshot.self, from: data)

        #expect(decoded == snapshot)
    }
}
