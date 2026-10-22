import SwiftUI
import TrainingKit

extension CertificateTier {
    /// "Basic", "Standard", "Improved", "Advanced", "Elite": the grades as the game names them.
    var title: LocalizedStringKey {
        switch self {
        case .basic: "Basic"
        case .standard: "Standard"
        case .improved: "Improved"
        case .advanced: "Advanced"
        case .elite: "Elite"
        }
    }

}

/// The grade a pilot has reached, as one small badge: the Roman numeral in an `accent` capsule,
/// filled for elite.
///
/// `nil` means not even `basic` and is drawn as a faint capsule with a dash, so the column stays
/// populated. One colour for every grade: colour means state, and the numeral spells the grade.
struct CertificateTierBadge: View {
    let tier: CertificateTier?

    var body: some View {
        let isElite = tier == .elite
        Text(tier.map { SkillLevel.roman($0.displayNumber) } ?? "—")
            .font(HUDFont.mono(11, weight: .semibold, relativeTo: .caption))
            .padding(.horizontal, 6)
            .frame(minWidth: 30, minHeight: 22)
            .foregroundStyle(isElite ? Color.hudBg : tier == nil ? Color.hudInkFaint : Color.hudAccent)
            .background(Capsule().fill(isElite ? Color.hudAccent : .clear))
            .overlay {
                Capsule().strokeBorder(tier == nil ? Color.hudLineLeader : Color.hudAccent, lineWidth: 1)
            }
            .accessibilityLabel(
                tier.map { Text("Grade \(SkillLevel.roman($0.displayNumber))") } ?? Text("Not achieved")
            )
    }
}

/// The plan marker for a certificate as a whole: drawn only when the plan takes the certificate
/// past the grade already achieved.
///
/// `.trained` or `.planned` would read as "already achieved", which `CertificateTierBadge` already
/// states, so only the one case the badge cannot state remains. One view, since the rule is fiddly
/// enough that copies would drift.
struct CertificatePlanMarker: View {
    let achieved: CertificateTier?
    let planned: CertificateTier?

    var body: some View {
        if let planned, planned.rawValue > (achieved?.rawValue ?? -1) {
            PlanStatusMarker(status: .partiallyPlanned(through: planned.displayNumber))
        }
    }
}
