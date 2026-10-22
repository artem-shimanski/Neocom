import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI
import TrainingKit

/// A ship's mastery table and certificate list, drawn from one query
/// (`CertificateBrowser.masteries(of:)`). Mastery has data for 409 ships only; the view draws
/// nothing when the query is empty.
struct MasterySection: View {
    let typeID: TypeID

    @Environment(\.trainingContext) private var trainingContext
    @Environment(AccountStore.self) private var accounts

    @LiteQuery private var masteries: [TypeMasteryRow]

    init(typeID: TypeID) {
        self.typeID = typeID
        _masteries = LiteQuery(CertificateBrowser.masteries(of: typeID))
    }

    var body: some View {
        if !masteries.isEmpty {
            // Nothing to time or plan without a pilot.
            if let context = trainingContext, context.pilot != nil {
                HUDListSection("Mastery") {
                    ForEach(CertificateTier.allCases, id: \.self) { tier in
                        let ids = certificates(at: tier.rawValue)
                        let queue = context.queue(forCertificates: ids, tier: tier)
                        MasteryTierRow(
                            tier: tier,
                            status: context.masteryStatus(ofCertificates: ids, tier: tier) ?? .absent,
                            time: (queue?.isEmpty ?? true) ? nil : queue?.totalTime
                        ) {
                            if let queue {
                                accounts.currentPlan?.add(context.unplanned(in: queue))
                            }
                        }
                    }
                }
            }

            // Drawn without a pilot: the certificate list is a fact about the ship; the badge stays empty.
            HUDListSection(Text("Certificates · \(shipCertificates.count)")) {
                ForEach(shipCertificates, id: \.certificateID) { certificate in
                    MasteryCertificateRow(certificateID: certificate.certificateID,
                                          name: certificate.name)
                }
            }
        }
    }

    /// The certificates of one mastery level.
    private func certificates(at level: Int) -> [CertificateID] {
        masteries.filter { $0.level == level }.map(\.certificateID)
    }

    /// The ship's full certificate list, distinct by id over the whole query rather than the top
    /// level's rows.
    private var shipCertificates: [TypeMasteryRow] {
        var seen = Set<CertificateID>()
        return masteries.filter { seen.insert($0.certificateID).inserted }
    }
}

/// One of the ship's certificates: the grade reached, the plan marker, and a tap that leads to
/// the certificate. The same row as in the Certificates section.
private struct MasteryCertificateRow: View {
    let certificateID: CertificateID
    let name: String

    @Environment(\.trainingContext) private var trainingContext

    var body: some View {
        NavigationLink(value: DatabaseRoute.certificate(certificateID)) {
            HStack(spacing: 12) {
                CertificateTierBadge(tier: achieved)
                Text(name)
                    .font(.hudBody)
                Spacer(minLength: 4)
                CertificatePlanMarker(achieved: achieved, planned: planned)
                HUDChevron()
            }
            .hudRow()
        }
        .hudRowButton()
    }

    private var achieved: CertificateTier? {
        trainingContext?.achievedTier(ofCertificate: certificateID)
    }

    private var planned: CertificateTier? {
        trainingContext?.plannedTier(ofCertificate: certificateID)
    }
}

/// One mastery level: its name, the time left to reach it, the plan state, and a tap that plans
/// what is missing across every certificate of the level. A view of its own so the haptic fires
/// once.
private struct MasteryTierRow: View {
    let tier: CertificateTier
    let status: TrainingContext.PlanStatus
    /// `nil` once there is nothing left to train for this level.
    let time: TimeInterval?
    let action: () -> Void

    @State private var tapped = false

    var body: some View {
        Button {
            tapped.toggle()
            action()
        } label: {
            HStack(spacing: 10) {
                Text("Mastery \(Text(verbatim: SkillLevel.roman(tier.displayNumber)).font(HUDFont.mono(15, weight: .regular, relativeTo: .body)).foregroundStyle(Color.hudInkMuted))")
                    .font(.hudBody)
                Spacer()
                if let time {
                    Text(TrainingTime.string(time))
                        .font(.hudCaption)
                        .foregroundStyle(Color.hudInkMuted)
                }
                PlanRowAccessory(status: status)
            }
            .hudRow()
        }
        .hudRowButton()
        // Already at this level, or planned to it in full.
        .disabled(status == .trained || status == .planned)
        .sensoryFeedback(.success, trigger: tapped)
    }
}
