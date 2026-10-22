import SDEKit
import SwiftUI
import TrainingKit

/// Everything a screen needs to show training times.
///
/// `catalog` and `pilot` are separate: skill requirements are shown without a character, only
/// the times need a pilot.
struct TrainingContext: Sendable {
    /// Where a skill level stands between the character and the plan.
    enum PlanStatus: Hashable {
        /// Already trained.
        case trained
        /// The plan covers this level.
        case planned
        /// The plan stops short of this level, at `through`.
        case partiallyPlanned(through: Int)
        /// Neither trained nor planned.
        case absent
    }

    /// Present once the SDE is open.
    let catalog: SkillCatalog
    let certificates: CertificateCatalog
    /// `nil` when no character is selected or the sheet has not loaded yet.
    let pilot: Pilot?
    let characterID: Int64?
    /// The type ids of the implants the character wears. Empty without a character or before
    /// their sheet has loaded; `pilot` tells which.
    ///
    /// `Pilot` keeps only the sum of the bonuses, so the list comes from the sheet's snapshot.
    let characterImplants: [TypeID]
    /// The highest level of each skill the character's plan reaches. Empty without a character.
    ///
    /// Derived from `TrainingPlanStore.entries`; the plan holds an unbroken run of levels per
    /// skill, so the maximum is enough.
    let plannedLevels: [TypeID: Int]

    /// The queue for a set of requirements, or `nil` without a pilot.
    func queue(forRequirements requirements: [SkillCatalog.Requirement]) -> TrainingQueue? {
        guard let pilot else { return nil }
        var queue = TrainingQueue(pilot: pilot, catalog: catalog)
        queue.add(requirements: requirements)
        return queue
    }

    /// The queue for a single skill trained up to `level`, or `nil` without a pilot.
    func queue(forSkill skill: TypeID, level: Int) -> TrainingQueue? {
        guard let pilot else { return nil }
        var queue = TrainingQueue(pilot: pilot, catalog: catalog)
        queue.add(skill: skill, level: level)
        return queue
    }

    /// Where one skill level stands, or `nil` without a character (no plan markers are drawn then).
    func planStatus(ofSkill skill: TypeID, level: Int) -> PlanStatus? {
        guard let pilot else { return nil }

        let trained = pilot.trainedLevel(of: skill)
        if trained >= level { return .trained }

        let planned = plannedLevels[skill] ?? 0
        if planned >= level { return .planned }
        if planned > trained { return .partiallyPlanned(through: planned) }
        return .absent
    }

    // MARK: - Certificates

    /// The grade the character has reached, `nil` without a pilot or below `basic`.
    func achievedTier(ofCertificate id: CertificateID) -> CertificateTier? {
        guard let pilot else { return nil }
        return certificates.tier(of: id) { pilot.trainedLevel(of: $0) }
    }

    /// The grade the character would reach once the plan is trained; the lookup takes the maximum of
    /// trained and planned levels.
    func plannedTier(ofCertificate id: CertificateID) -> CertificateTier? {
        guard let pilot else { return nil }
        return certificates.tier(of: id) { max(pilot.trainedLevel(of: $0), plannedLevels[$0] ?? 0) }
    }

    /// Where one grade stands between the character and the plan, `nil` without a pilot.
    ///
    /// The number in `partiallyPlanned(through:)` is a display number: a skill's level or a
    /// certificate's grade, both written I…V.
    func tierStatus(ofCertificate id: CertificateID, tier: CertificateTier) -> PlanStatus? {
        guard pilot != nil else { return nil }
        return tierStatus(achieved: achievedTier(ofCertificate: id),
                          planned: plannedTier(ofCertificate: id),
                          tier: tier)
    }

    /// The queue that gets one grade of one certificate trained, `nil` without a pilot.
    func queue(forCertificate id: CertificateID, tier: CertificateTier) -> TrainingQueue? {
        queue(forRequirements: certificates.requirements(of: id, tier: tier))
    }

    /// The queue for a mastery level: several certificates at one grade.
    func queue(forCertificates ids: [CertificateID], tier: CertificateTier) -> TrainingQueue? {
        queue(forRequirements: certificates.requirements(of: ids, tier: tier))
    }

    /// Where a mastery level stands, `nil` without a pilot.
    func masteryStatus(ofCertificates ids: [CertificateID], tier: CertificateTier) -> PlanStatus? {
        guard let pilot else { return nil }
        let achieved = certificates.tier(of: ids) { pilot.trainedLevel(of: $0) }
        let planned = certificates.tier(of: ids) {
            max(pilot.trainedLevel(of: $0), plannedLevels[$0] ?? 0)
        }
        return tierStatus(achieved: achieved, planned: planned, tier: tier)
    }

    /// The requirements of `queue` the plan does not cover yet.
    func unplanned(in queue: TrainingQueue) -> [SkillCatalog.Requirement] {
        queue.items.compactMap { item in
            switch planStatus(ofSkill: item.skillID, level: item.targetLevel) {
            case .planned, .trained, .none:
                return nil
            case .absent, .partiallyPlanned:
                return SkillCatalog.Requirement(skillID: item.skillID, level: item.targetLevel)
            }
        }
    }

    /// Compares an achieved and a planned grade against a target; no grade ranks as `-1`, below `basic`.
    private func tierStatus(achieved: CertificateTier?,
                            planned: CertificateTier?,
                            tier: CertificateTier) -> PlanStatus {
        let achievedRank = achieved?.rawValue ?? -1
        if achievedRank >= tier.rawValue { return .trained }
        if let planned {
            if planned.rawValue >= tier.rawValue { return .planned }
            if planned.rawValue > achievedRank { return .partiallyPlanned(through: planned.displayNumber) }
        }
        return .absent
    }
}

extension EnvironmentValues {
    @Entry var trainingContext: TrainingContext?
}
