import BusinessKit
import SwiftUI

/// The courier layout: the reward and the collateral, the route from pick-up to delivery with
/// its jump count, the package, and the deadline that runs from acceptance.
struct ContractCourierLayout: View {
    let detail: ContractDetail

    var body: some View {
        let c = detail.contract
        let figure = timeFigure
        Section {
            HUDPanel(tone: failed ? .danger : detail.cardTone) {
                detail.headerBar
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Reward")
                            .font(.hudMicro)
                            .tracking(1.5)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.hudInkMuted)
                        Spacer(minLength: 8)
                        Text(verbatim: ISK.priceFigure(c.reward ?? 0))
                            .font(HUDFont.mono(24, weight: .semibold, relativeTo: .title2))
                            .foregroundStyle(Color.hudAccent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(verbatim: "ISK")
                            .font(.hudReadout)
                            .foregroundStyle(Color.hudInkMuted)
                    }
                    Text(verbatim: party.uppercased())
                        .font(.hudCaption)
                        .foregroundStyle(Color.hudInkMuted)
                }
                .padding(.horizontal, HUDMetrics.gutter)
                .padding(.top, 14)
                .padding(.bottom, 12)
                HUDPanelRule()
                contractStrip([
                    (Text("Collateral"), c.collateral.map(ISK.compact) ?? "—", .hudInk),
                    (Text("Volume"), c.volume.map { ContractText.volume($0) } ?? "—", .hudInk),
                    (Text(verbatim: figure.label.uppercased()), figure.text, figure.color),
                ])
                if let note {
                    detail.note(note.text, color: note.color)
                }
            }
            .hudBareRow()
        }

        routeSection
        ContractItemsSection(detail: detail, title: Text("Package"), included: nil,
                             volume: c.volume, showsVolume: true)
        detail.parties(last: .init(label: "Courier", value: detail.acceptor))
        ContractFactsSection(title: "Contract", facts: [
            .init(label: "Reward", value: c.reward.map { ContractText.isk($0) } ?? "—", color: .hudAccent),
            .init(label: "Collateral", value: c.collateral.map { ContractText.isk($0) } ?? "—"),
            .init(label: "Volume", value: c.volume.map { ContractText.volume($0) } ?? "—"),
            .init(label: "Days to Complete", value: c.daysToComplete.map(String.init) ?? "—"),
            .init(label: "Issued", value: detail.date(c.dateIssued)),
            .init(label: "Accept By", value: detail.date(c.dateExpired)),
            .init(label: "Accepted", value: detail.date(c.dateAccepted)),
            .init(label: "Deadline", value: detail.date(c.deadline),
                  color: failed || c.isOverdue(at: detail.now) ? .hudDanger
                      : (detail.isActive && detail.isDueSoon ? .hudWarn : .hudInk)),
            .init(label: failed ? "Failed" : "Completed", value: detail.date(c.dateCompleted),
                  color: failed ? .hudDanger : .hudInk),
            detail.contractID,
        ])
        Section {
            HUDFootnote("The deadline runs from acceptance: days to complete after the contract was accepted. Complete the delivery in the EVE client at the destination.")
                .hudBareRow()
        }
    }

    private var failed: Bool { detail.contract.courierFailed }

    /// The carrier is the pilot when they accepted it.
    private var carriedByMe: Bool { detail.contract.acceptorID == detail.me }

    private var party: String {
        let c = detail.contract
        if detail.isMine {
            return c.acceptorID == 0
                ? String(localized: "Issued by you")
                : String(localized: "Issued by you · carried by \(detail.name(c.acceptorID))")
        }
        let issuer = detail.name(c.issuerID)
        return carriedByMe ? String(localized: "From \(issuer) · you carry") : String(localized: "From \(issuer)")
    }

    /// The third cell: the time to deliver, or to accept; the deadline that was missed; the day
    /// it ended.
    private var timeFigure: (label: String, text: String, color: Color) {
        let c = detail.contract
        if failed { return (String(localized: "Deadline was"), c.deadline.map(EVETime.monthDay) ?? "—", .hudDanger) }
        guard detail.isActive else { return (String(localized: "Closed"), EVETime.date(c.closedDate), .hudInk) }
        let left = detail.timeLeftFigure
        return (c.status == .inProgress ? String(localized: "Deliver in") : String(localized: "Expires in"), left.text, left.color)
    }

    /// What to know about the delivery, in the colour of its urgency.
    private var note: (text: String, color: Color)? {
        let c = detail.contract
        let destination = detail.context.locationName(c.endLocationID)
        let collateral = c.collateral.map { ContractText.isk($0) } ?? "0 ISK"
        let deadline = c.deadline.map(EVETime.dateTime) ?? "—"
        let issuer = detail.name(c.issuerID)
        let courier = c.acceptorID == 0 ? String(localized: "The courier") : detail.name(c.acceptorID)
        if failed {
            return detail.isMine
                ? (String(localized: "\(courier) did not deliver by \(deadline). The \(collateral) collateral was paid to you; the package stays with the courier."), .hudDanger)
                : (String(localized: "The package was not delivered by \(deadline). The \(collateral) collateral went to \(issuer)."), .hudDanger)
        }
        if c.isOverdue(at: detail.now) {
            return carriedByMe
                ? (String(localized: "The deadline passed on \(deadline). Deliver to \(destination) at once: until it is settled in game, \(issuer) can fail the contract and keep your \(collateral) collateral."), .hudDanger)
                : (String(localized: "\(courier) missed the \(deadline) deadline. Until it is settled in game the contract stays in progress; failing it pays the \(collateral) collateral to the issuer."), .hudDanger)
        }
        let color: Color = detail.isDueSoon ? .hudWarn : .hudInkMuted
        switch c.status {
        case .inProgress where carriedByMe:
            return (String(localized: "Deliver to \(destination) before \(deadline). If you miss it, your \(collateral) collateral goes to \(issuer)."), color)
        case .inProgress:
            return (String(localized: "\(courier) must deliver to \(destination) before \(deadline), or the \(collateral) collateral comes to you."), color)
        case .outstanding where !c.isExpired(at: detail.now) && !detail.isMine:
            return (String(localized: "Accept it in the EVE client before \(EVETime.dateTime(c.dateExpired)); you put up \(collateral) as collateral."), color)
        default:
            return nil
        }
    }

    // MARK: Route

    private var routeSection: some View {
        let c = detail.contract
        let context = detail.context
        let start = context.systemID(of: c.startLocationID)
        let end = context.systemID(of: c.endLocationID)
        let jumps: Int? = start.flatMap { start in end.flatMap { detail.market.jumps(from: start, to: $0) } }
        let unreachable = start.flatMap { start in end.map { detail.market.isUnreachable(from: start, to: $0) } } ?? false
        return HUDListSection(content: {
            VStack(alignment: .leading, spacing: 0) {
                stop(label: "Pick up", locationID: c.startLocationID, isEnd: false)
                rail(Text(verbatim: via(jumps: jumps, unreachable: unreachable)))
                stop(label: "Deliver to", locationID: c.endLocationID, isEnd: true)
            }
            .padding(.horizontal, HUDMetrics.gutter)
            .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 14))
        }, header: {
            HUDSectionHeader(Text("Route")) {
                if let jumps {
                    Text("\(jumps) Jumps")
                }
            }
        })
    }

    private func via(jumps: Int?, unreachable: Bool) -> String {
        if unreachable { return String(localized: "No gate route").uppercased() }
        guard let jumps else { return "…" }
        return jumps == 0 ? String(localized: "Same system").uppercased() : String(localized: "\(jumps) J", comment: "Jumps, abbreviated")
    }

    /// One end of the route: the marker on the rail, the station and its system.
    private func stop(label: LocalizedStringKey, locationID: Int64?, isEnd: Bool) -> some View {
        let context = detail.context
        return HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .top) {
                if !isEnd {
                    Rectangle().fill(Color.hudLineLeader).frame(width: 2).padding(.top, 14)
                }
                Circle()
                    .strokeBorder(Color.hudAccent, lineWidth: isEnd ? 5 : 2)
                    .frame(width: 10, height: 10)
                    .padding(.top, 4)
            }
            .frame(width: 14)
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.hudMicro)
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hudInkMuted)
                Text(verbatim: context.locationName(locationID))
                    .font(.hudBody)
                    .fixedSize(horizontal: false, vertical: true)
                if let line = contractSystemLine(context.system(of: locationID)) {
                    line
                        .font(.hudCaption)
                        .foregroundStyle(Color.hudInkMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, isEnd ? 0 : 14)
        }
    }

    /// The stretch between the two stops, with the jumps written on it.
    private func rail(_ text: Text) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle().fill(Color.hudLineLeader).frame(width: 2)
                .frame(width: 14)
            text
                .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                .tracking(1)
                .foregroundStyle(Color.hudInkBodyMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 14)
        }
    }
}
