import BusinessKit
import SwiftUI

/// What the corporation's members paid in taxes, from the Master Wallet's journal, and who
/// withdrew ISK from it.
struct CorporationMemberTaxesView: View {
    /// The Master Wallet.
    let model: WalletModel

    var body: some View {
        WalletScreen(model: model) { now in
            CorporationMemberTaxesList(model: model, now: now)
        }
        .navigationTitle("Member Taxes")
        .navigationBarTitleDisplayMode(.inline)
        .corporationSubtitle(.corporation)
    }
}

private struct CorporationMemberTaxesList: View {
    let model: WalletModel
    let now: Date

    @State private var period: WalletPeriod = .month

    var body: some View {
        let taxes = model.memberTaxes(now: now, period: period)
        let top = taxes.members.first?.total ?? 0
        HUDList {
            Section {
                Picker("Period", selection: $period) {
                    Text("7 Days").tag(WalletPeriod.week)
                    Text("30 Days").tag(WalletPeriod.month)
                }
                .pickerStyle(.segmented)
                .hudBareRow()
            }

            Section {
                HUDPanel {
                    HUDStatStrip(items: [
                        .init(id: 0, label: Text("Tax Paid"), value: Text(verbatim: WalletText.signed(taxes.total)),
                              color: WalletText.color(taxes.total)),
                        .init(id: 1, label: Text("Members"), value: Text(verbatim: "\(taxes.members.count)")),
                        .init(id: 2, label: Text("Withdrawn"), value: Text(verbatim: WalletText.signed(-taxes.withdrawn))),
                    ])
                }
                .hudBareRow()
            }

            if taxes.members.isEmpty {
                Section {
                    HUDEmptyPanel(title: Text("No Taxes"),
                                  message: Text("No member paid bounty or mission tax into the Master Wallet in this period."))
                        .hudBareRow()
                }
            } else {
                HUDListSection(taxes.members, row: { member in
                    MemberTaxRow(model: model, member: member, top: top, now: now)
                }, header: {
                    HUDSectionHeader(Text("Tax by Member"))
                })
            }

            if taxes.withdrawals.isEmpty {
                HUDListSection(Text("Withdrawals")) {
                    Text("No withdrawals in this period")
                        .font(.hudCaption)
                        .foregroundStyle(Color.hudInkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .hudRow()
                }
            } else {
                HUDListSection(taxes.withdrawals, row: { withdrawal in
                    WithdrawalRow(model: model, withdrawal: withdrawal)
                }, header: {
                    HUDSectionHeader(Text("Withdrawals")) {
                        Text(verbatim: WalletText.signed(-taxes.withdrawn))
                    }
                })
            }

            Section {
                HUDFootnote("Taxes are the corporation’s share of members’ bounties and mission rewards, as booked in the Master Wallet journal. Members who paid nothing in the period are not listed.")
                    .hudBareRow()
            }
        }
    }
}

private struct MemberTaxRow: View {
    let model: WalletModel
    let member: WalletMemberTax
    let top: Double
    let now: Date

    var body: some View {
        let name = model.name(member.memberID) ?? "#\(member.memberID)"
        HStack(alignment: .top, spacing: 12) {
            HUDInitialsAvatar(name: name, size: 36, url: EVEImage.portrait(characterID: member.memberID, size: 64))
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: name)
                        .font(.hudBody)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(verbatim: ISK.compact(member.total))
                        .font(HUDFont.mono(14, weight: .semibold, relativeTo: .subheadline))
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                HUDOrderFillBar(fraction: top > 0 ? member.total / top : 0,
                                caption: Text(verbatim: member.share.formatted(.percent.precision(.fractionLength(0)))))
                Text(verbatim: detail)
                    .font(.hudMicro)
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hudInkMuted)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .hudRow(HUDRowStyle(minHeight: 72, verticalPadding: 11))
    }

    /// `6 days active · missions & other 1.2M · last 3h 20m ago`.
    private var detail: String {
        var parts = [String(localized: "\(member.daysActive) days active")]
        if member.other > 0 {
            parts.append(String(localized: "Missions & other \(ISK.compact(member.other))"))
        }
        parts.append(String(localized: "Last \(EVETime.relative(member.lastDate, now: now))"))
        return parts.joined(separator: " · ")
    }
}

private struct WithdrawalRow: View {
    let model: WalletModel
    let withdrawal: WalletWithdrawal

    var body: some View {
        let name = withdrawal.whoID.map { model.name($0) ?? "#\($0)" } ?? "—"
        HStack(spacing: 12) {
            HUDInitialsAvatar(name: name, size: 36,
                              url: withdrawal.whoID.map { EVEImage.portrait(characterID: $0, size: 64) })
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: name)
                    .font(.hudBody)
                    .lineLimit(1)
                Text(verbatim: detail)
                    .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(Color.hudInkMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(verbatim: WalletText.signed(-withdrawal.amount))
                .font(HUDFont.mono(14, weight: .semibold, relativeTo: .subheadline))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .hudRow(.subtitled)
    }

    /// `“SRP October” · 2026.10.04 20:15`.
    private var detail: String {
        var parts: [String] = []
        if let reason = withdrawal.reason { parts.append("“\(reason)”") }
        parts.append(EVETime.dateTime(withdrawal.date))
        return parts.joined(separator: " · ")
    }
}
