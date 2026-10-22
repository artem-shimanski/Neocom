//
//  CertificateCatalog.swift
//  TrainingKit
//

import SDEKit

/// A certificate: its skills and the level each grade asks for.
public struct Certificate: Sendable, Hashable, Identifiable {
    /// One skill of the certificate, with its level on each of the five grades.
    public struct SkillLevels: Sendable, Hashable {
        public var skillID: TypeID
        /// Indexed by `CertificateTier.rawValue`. Zero means the grade does not ask for the skill.
        public var levels: [Int]

        public init(skillID: TypeID, levels: [Int]) {
            self.skillID = skillID
            self.levels = levels
        }

        public func level(at tier: CertificateTier) -> Int {
            levels.indices.contains(tier.rawValue) ? levels[tier.rawValue] : 0
        }
    }

    public var id: CertificateID
    /// The skill group the certificate is filed under.
    public var groupID: GroupID
    public var skills: [SkillLevels]

    public init(id: CertificateID, groupID: GroupID, skills: [SkillLevels]) {
        self.id = id
        self.groupID = groupID
        self.skills = skills
    }
}

/// In-memory reference of certificates.
public struct CertificateCatalog: Sendable {
    public let certificates: [CertificateID: Certificate]

    public init(certificates: [CertificateID: Certificate]) {
        self.certificates = certificates
    }

    public subscript(_ id: CertificateID) -> Certificate? { certificates[id] }

    /// Whether every skill of the certificate reaches the level the grade asks for. An unknown
    /// certificate never satisfies a grade; an empty requirement set always does.
    private func satisfies(_ id: CertificateID,
                           tier: CertificateTier,
                           trainedLevel: (TypeID) -> Int) -> Bool {
        guard let certificate = certificates[id] else { return false }
        return certificate.skills.allSatisfy { trainedLevel($0.skillID) >= $0.level(at: tier) }
    }
}

extension CertificateCatalog {
    /// What one grade of one certificate asks for; skills at level zero are omitted.
    public func requirements(of id: CertificateID,
                             tier: CertificateTier) -> [SkillCatalog.Requirement] {
        guard let certificate = certificates[id] else { return [] }
        return certificate.skills.compactMap { skill in
            let level = skill.level(at: tier)
            guard level > 0 else { return nil }
            return SkillCatalog.Requirement(skillID: skill.skillID, level: level)
        }
    }

    /// The same for a set of certificates, such as one mastery level of a ship; duplicate
    /// skills are collapsed to the highest level asked for.
    public func requirements(of ids: [CertificateID],
                             tier: CertificateTier) -> [SkillCatalog.Requirement] {
        var order: [TypeID] = []
        var levels: [TypeID: Int] = [:]

        for id in ids {
            for requirement in requirements(of: id, tier: tier) {
                if levels[requirement.skillID] == nil {
                    order.append(requirement.skillID)
                }
                levels[requirement.skillID] = max(levels[requirement.skillID] ?? 0,
                                                  requirement.level)
            }
        }

        return order.map { SkillCatalog.Requirement(skillID: $0, level: levels[$0] ?? 0) }
    }

    /// The highest grade every skill of the certificate already reaches, `nil` when not
    /// even `basic` is met.
    ///
    /// `trainedLevel` returns the level the caller counts for a skill, e.g.
    /// `Pilot.trainedLevel(of:)`.
    public func tier(of id: CertificateID,
                     trainedLevel: (TypeID) -> Int) -> CertificateTier? {
        for tier in CertificateTier.allCases.reversed() {
            if satisfies(id, tier: tier, trainedLevel: trainedLevel) {
                return tier
            }
        }
        return nil
    }

    /// The highest grade every certificate in the set reaches, i.e. a ship's mastery level.
    public func tier(of ids: [CertificateID],
                     trainedLevel: (TypeID) -> Int) -> CertificateTier? {
        guard !ids.isEmpty else { return nil }
        for tier in CertificateTier.allCases.reversed() {
            if ids.allSatisfy({ satisfies($0, tier: tier, trainedLevel: trainedLevel) }) {
                return tier
            }
        }
        return nil
    }
}
