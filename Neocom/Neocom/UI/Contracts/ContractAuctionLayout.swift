import BusinessKit
import SwiftUI

/// The auction layout: the high bid against the starting price and the buyout, the bids
/// highest first, and what is for sale.
struct ContractAuctionLayout: View {
    let detail: ContractDetail

    private var sortedBids: [ContractBid]? { detail.bids?.value?.bids.highestFirst }

    var body: some View {
        let c = detail.contract
        let bids = sortedBids
        let finished = c.status.tone == .finished
        let highBid = bids?.first?.amount
        let left = detail.timeLeftFigure
        Section {
            HUDPanel {
                detail.headerBar
                ContractTitleBlock(title: detail.context.title(of: c), party: party(bids))
                priceBlock(highBid: highBid, finished: finished)
                HUDPanelRule()
                contractStrip([
                    (Text("Bids"), bids.map { "\($0.count)" } ?? "—", .hudInk),
                    (Text("Volume"), c.volume.map { ContractText.volume($0) } ?? "—", .hudInk),
                    (Text(detail.isActive ? "Ends In" : "Ended"),
                     detail.isActive ? left.text : EVETime.monthDayTime(c.closedDate),
                     detail.isActive ? left.color : .hudInk),
                ])
            }
            .hudBareRow()
        }

        bidsSection(bids, finished: finished)
        ContractItemsSection(detail: detail, title: Text("For Sale"), included: nil, volume: nil)
        ContractLocationSection(detail: detail, title: "Location", locationID: c.startLocationID)
        detail.parties(last: .init(label: "Won By", value: finished ? detail.acceptor : "—"))
        ContractFactsSection(title: "Contract", facts: [
            .init(label: "Starting Price", value: c.price.map { ContractText.isk($0) } ?? "—"),
            .init(label: "Buyout", value: c.buyout.map { ContractText.isk($0) } ?? "—"),
            .init(label: "Volume", value: c.volume.map { ContractText.volume($0) } ?? "—"),
            .init(label: "Issued", value: detail.date(c.dateIssued)),
            .init(label: "Expires", value: detail.date(c.dateExpired)),
            .init(label: "Accepted", value: detail.date(c.dateAccepted)),
            .init(label: "Completed", value: detail.date(c.dateCompleted)),
            detail.contractID,
        ])
        Section {
            HUDFootnote(finished
                ? Text("The highest bid won when the auction ended. ISK is in the seller's wallet; the buyer collects the item at the station.")
                : Text("A bid at the buyout price ends the auction at once. Otherwise the highest bid wins when it expires."))
                .hudBareRow()
        }
    }

    private func party(_ bids: [ContractBid]?) -> String {
        let c = detail.contract
        var text = detail.isMine ? String(localized: "Issued by you") : String(localized: "From \(detail.name(c.issuerID))")
        if let bids {
            text += " · " + String(localized: "\(bids.count) bids")
        }
        return text
    }

    /// The high bid, large, and where it sits between the starting price and the buyout.
    private func priceBlock(highBid: Double?, finished: Bool) -> some View {
        let c = detail.contract
        let label = finished ? String(localized: "Sold for")
            : highBid == nil ? String(localized: "Starting bid") : String(localized: "High bid")
        let figure = highBid ?? c.price ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: label.uppercased())
                    .font(.hudMicro)
                    .tracking(1.5)
                    .foregroundStyle(Color.hudInkMuted)
                Spacer(minLength: 8)
                Text(verbatim: ISK.priceFigure(figure))
                    .font(HUDFont.mono(24, weight: .semibold, relativeTo: .title2))
                    .foregroundStyle(Color.hudAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(verbatim: "ISK")
                    .font(.hudReadout)
                    .foregroundStyle(Color.hudInkMuted)
            }
            if let progress = c.auctionProgress(highBid: highBid) {
                HUDJobProgressBar(fraction: progress, height: 4)
            }
            HStack {
                if let start = c.price {
                    Text("Start \(ISK.compact(start))")
                }
                Spacer()
                if let buyout = c.buyout {
                    Text("Buyout \(ISK.compact(buyout))")
                }
            }
            .textCase(.uppercase)
            .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
            .foregroundStyle(Color.hudInkMuted)
        }
        .padding(.horizontal, HUDMetrics.gutter)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private func bidsSection(_ bids: [ContractBid]?, finished: Bool) -> some View {
        if let bids {
            if bids.isEmpty {
                Section {
                    Text("No bids yet.")
                        .font(.hudCaption)
                        .foregroundStyle(Color.hudInkMuted)
                        .hudBareRow()
                } header: {
                    HUDSectionHeader(Text("Bids · 0")).hudListHeader()
                }
            } else {
                let topID = bids.first?.id
                HUDListSection(bids, row: { bid in
                    ContractBidRow(bid: bid, detail: detail,
                                   tag: bid.id == topID ? tag(finished: finished) : nil)
                }, header: {
                    HUDSectionHeader(Text("Bids · \(bids.count)")) {
                        Text("Highest first")
                    }
                })
            }
        } else if let snapshot = detail.bids {
            Section {
                if case let .failed(error) = snapshot.state {
                    HUDEmptyPanel(systemImage: "exclamationmark.triangle", title: Text("Bids Unavailable"),
                                  message: Text(error.localizedDescription))
                        .hudBareRow()
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .hudBareRow()
                }
            } header: {
                HUDSectionHeader(Text("Bids")).hudListHeader()
            }
        }
    }

    /// The label of the leading bid: it won an ended auction, it leads a running one.
    private func tag(finished: Bool) -> (text: String, color: Color)? {
        if finished { return (String(localized: "Won"), .hudOk) }
        return detail.isActive ? (String(localized: "High bid"), .hudAccent) : nil
    }
}

private struct ContractBidRow: View {
    static let rowStyle = HUDRowStyle(minHeight: 56)

    let bid: ContractBid
    let detail: ContractDetail
    let tag: (text: String, color: Color)?

    var body: some View {
        HStack(spacing: 12) {
            HUDImagePlate(url: EVEImage.portrait(characterID: bid.bidderID, size: 64), size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: detail.name(bid.bidderID))
                    .font(HUDFont.display(15, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(tag == nil ? Color.hudInkBodyMuted : Color.hudInk)
                    .lineLimit(1)
                Text(verbatim: String(localized: "\(EVETime.dateTime(bid.date)) · BID \(bid.id)"))
                    .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(Color.hudInkMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 3) {
                Text(verbatim: ISK.priceFigure(bid.amount))
                    .font(HUDFont.mono(14, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(tag?.color ?? Color.hudInk)
                    .lineLimit(1)
                if let tag {
                    Text(verbatim: tag.text.uppercased())
                        .font(.hudMicro)
                        .tracking(1)
                        .foregroundStyle(tag.color)
                }
            }
            .fixedSize()
        }
        .hudRow(Self.rowStyle)
    }
}
