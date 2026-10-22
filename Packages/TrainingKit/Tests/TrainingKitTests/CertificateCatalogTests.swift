//
//  CertificateCatalogTests.swift
//  TrainingKit
//

import Testing
import SDEKit
@testable import TrainingKit

@Suite("CertificateCatalog")
struct CertificateCatalogTests {
    // One certificate on two skills: levels by grade (basic...elite).
    private static let skillA = TypeID(rawValue: 1)
    private static let skillB = TypeID(rawValue: 2)
    private static let groupID = GroupID(rawValue: 1)

    private static let certificateID = CertificateID(rawValue: 1)
    private static let certificate = Certificate(
        id: certificateID,
        groupID: groupID,
        skills: [
            .init(skillID: skillA, levels: [1, 2, 3, 4, 5]),
            .init(skillID: skillB, levels: [0, 0, 1, 3, 5]),
        ]
    )

    // A second certificate sharing `skillA`, at different levels, for the collapsing test.
    private static let otherCertificateID = CertificateID(rawValue: 2)
    private static let otherCertificate = Certificate(
        id: otherCertificateID,
        groupID: groupID,
        skills: [
            .init(skillID: skillA, levels: [5, 5, 5, 5, 5]),
        ]
    )

    // A certificate with no skills at all: nothing to ask for, so every grade is met.
    private static let emptyCertificateID = CertificateID(rawValue: 3)
    private static let emptyCertificate = Certificate(id: emptyCertificateID, groupID: groupID,
                                                     skills: [])

    private static let unknownCertificateID = CertificateID(rawValue: 999)

    private static let catalog = CertificateCatalog(certificates: [
        certificateID: certificate,
        otherCertificateID: otherCertificate,
        emptyCertificateID: emptyCertificate,
    ])

    private static func trainedLevel(_ levels: [TypeID: Int]) -> (TypeID) -> Int {
        { levels[$0] ?? 0 }
    }

    // MARK: - tier(of id:)

    @Test("nothing trained reaches no grade")
    func nothingTrained() {
        let tier = Self.catalog.tier(of: Self.certificateID, trainedLevel: Self.trainedLevel([:]))
        #expect(tier == nil)
    }

    @Test("first skill at 1, second at 0 reaches basic")
    func reachesBasic() {
        let tier = Self.catalog.tier(of: Self.certificateID, trainedLevel: Self.trainedLevel([
            Self.skillA: 1, Self.skillB: 0,
        ]))
        #expect(tier == .basic)
    }

    @Test("first skill at 3, second at 1 reaches improved")
    func reachesImproved() {
        let tier = Self.catalog.tier(of: Self.certificateID, trainedLevel: Self.trainedLevel([
            Self.skillA: 3, Self.skillB: 1,
        ]))
        #expect(tier == .improved)
    }

    @Test("both skills at 5 reaches elite")
    func reachesElite() {
        let tier = Self.catalog.tier(of: Self.certificateID, trainedLevel: Self.trainedLevel([
            Self.skillA: 5, Self.skillB: 5,
        ]))
        #expect(tier == .elite)
    }

    @Test("first skill at 5, second at 3 reaches advanced, not elite")
    func stopsAtAdvancedWhenSecondSkillLags() {
        let tier = Self.catalog.tier(of: Self.certificateID, trainedLevel: Self.trainedLevel([
            Self.skillA: 5, Self.skillB: 3,
        ]))
        #expect(tier == .advanced)
    }

    // MARK: - requirements(of id:tier:)

    @Test("requirements at basic omit the skill not asked for at that grade")
    func requirementsAtBasic() {
        let requirements = Self.catalog.requirements(of: Self.certificateID, tier: .basic)
        #expect(requirements == [.init(skillID: Self.skillA, level: 1)])
    }

    @Test("requirements at elite list both skills")
    func requirementsAtElite() {
        let requirements = Self.catalog.requirements(of: Self.certificateID, tier: .elite)
        #expect(requirements == [
            .init(skillID: Self.skillA, level: 5),
            .init(skillID: Self.skillB, level: 5),
        ])
    }

    // MARK: - requirements(of ids:tier:)

    @Test("requirements of a set collapse a shared skill to its highest level")
    func requirementsOfSetCollapseSharedSkill() {
        let requirements = Self.catalog.requirements(
            of: [Self.certificateID, Self.otherCertificateID],
            tier: .basic
        )
        // certificateID asks skillA at 1, otherCertificateID asks it at 5: one entry at 5.
        #expect(requirements == [.init(skillID: Self.skillA, level: 5)])
    }

    // MARK: - tier(of ids:)

    @Test("tier of a set is the grade the weakest certificate reaches")
    func tierOfSetIsTheWeakestCertificate() {
        // `otherCertificate` asks skillA at 5 on every grade, so it is elite already;
        // `certificate` is held to basic by skillB. A mastery level is the whole set or
        // nothing, so the answer is the lower of the two.
        let tier = Self.catalog.tier(of: [Self.certificateID, Self.otherCertificateID],
                                     trainedLevel: Self.trainedLevel([
                                         Self.skillA: 5, Self.skillB: 1,
                                     ]))
        #expect(tier == .improved)
    }

    @Test("tier of an empty set is nil, not elite")
    func tierOfEmptySetIsNil() {
        let tier = Self.catalog.tier(of: [] as [CertificateID],
                                     trainedLevel: Self.trainedLevel([:]))
        #expect(tier == nil)
    }

    // MARK: - Edge cases

    @Test("a certificate with no skills is satisfied at every grade")
    func emptySkillsCertificateReachesElite() {
        let tier = Self.catalog.tier(of: Self.emptyCertificateID,
                                     trainedLevel: Self.trainedLevel([:]))
        #expect(tier == .elite)
    }

    @Test("an unknown certificate has no requirements and no grade")
    func unknownCertificate() {
        let requirements = Self.catalog.requirements(of: Self.unknownCertificateID, tier: .basic)
        let tier = Self.catalog.tier(of: Self.unknownCertificateID,
                                     trainedLevel: Self.trainedLevel([:]))
        #expect(requirements == [])
        #expect(tier == nil)
    }
}
