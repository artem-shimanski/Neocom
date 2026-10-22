import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI
import TrainingKit

/// The Certificates section: every certificate, grouped by the skill group it is filed under, with
/// the grade the pilot has reached.
///
/// Wrapped in `SDESectionView`: certificate and group names live in the SDE.
struct CertificatesView: View {
    var body: some View {
        SDESectionView { _ in
            CertificatesList()
        }
        .hudScreen()
        .navigationTitle("Certificates")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The list itself, once the database is open.
private struct CertificatesList: View {
    @Environment(AccountStore.self) private var accounts

    @LiteQuery private var rows: [CertificateListRow]

    init() {
        _rows = LiteQuery(CertificateBrowser.certificates())
    }

    var body: some View {
        Group {
            if rows.isEmpty {
                ContentUnavailableView(
                    "No Certificates",
                    systemImage: "rosette",
                    description: Text("The database does not list any certificates.")
                )
            } else {
                HUDList {
                    ForEach(CertificateGroupSection.sections(from: rows)) { section in
                        HUDListSection(section.rows, row: { row in
                            CertificateListRowView(row: row)
                        }, header: {
                            HUDSectionHeader(verbatim: section.name)
                        })
                    }
                }
            }
        }
        .refreshableCommand {
            await accounts.currentSheet?.refresh()
        }
        .task(id: accounts.currentAccountID) {
            await accounts.currentSheet?.ensureFresh()
        }
    }
}

/// Certificates under the skill group CCP files them under.
private struct CertificateGroupSection: Identifiable {
    var id: GroupID
    var name: String
    var rows: [CertificateListRow]

    /// Groups rows that already arrive ordered by group and then by name, keeping that order.
    static func sections(from rows: [CertificateListRow]) -> [CertificateGroupSection] {
        var order: [GroupID] = []
        var byGroup: [GroupID: [CertificateListRow]] = [:]
        for row in rows {
            if byGroup[row.groupID] == nil { order.append(row.groupID) }
            byGroup[row.groupID, default: []].append(row)
        }
        return order.map { id in
            CertificateGroupSection(id: id, name: byGroup[id]?.first?.groupName ?? "", rows: byGroup[id] ?? [])
        }
    }
}

/// One certificate: the grade achieved on the left, the plan marker on the right when the plan
/// takes the certificate past that grade.
private struct CertificateListRowView: View {
    let row: CertificateListRow

    @Environment(\.trainingContext) private var trainingContext

    var body: some View {
        NavigationLink(value: DatabaseRoute.certificate(row.id)) {
            HStack(spacing: 12) {
                CertificateTierBadge(tier: achieved)
                Text(row.name)
                    .font(.hudBody)
                Spacer(minLength: 4)
                CertificatePlanMarker(achieved: achieved, planned: planned)
                HUDChevron()
            }
            .hudRow(HUDRowStyle(minHeight: 50))
        }
        .hudRowButton(HUDRowStyle(minHeight: 50))
    }

    private var achieved: CertificateTier? {
        trainingContext?.achievedTier(ofCertificate: row.id)
    }

    private var planned: CertificateTier? {
        trainingContext?.plannedTier(ofCertificate: row.id)
    }
}

#Preview {
    NavigationStack {
        CertificatesView()
    }
    .environment(AccountStore())
    .environment(SDEStore())
}
