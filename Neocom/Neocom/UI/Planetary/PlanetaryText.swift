import SwiftUI

// How the Planetary Interaction screens put the report into words: names of kinds, figures,
// and one phrasing per issue, shared by the list, the colony, the chain and the
// notifications.

/// Figures of the section.
enum PlanetaryFormat {
    /// `1 571/h`, `1.9/h`: a tenth below ten, whole above.
    static func rate(_ perHour: Double) -> String {
        String(localized: "\(number(perHour))/h", comment: "Rate per hour")
    }

    /// `1 571`, `9.5`, `0.4`.
    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(abs(value) < 10 && value != value.rounded() ? 1 : 0)))
    }

    static func quantity(_ value: Int) -> String {
        value.formatted(.number)
    }

    /// `+120`, `0`.
    static func gain(_ value: Int) -> String {
        value.formatted(.number.sign(strategy: .always(includingZero: false)))
    }

    /// `P0` … `P4`.
    static func tier(_ tier: Int) -> String {
        "P\(tier)"
    }

    /// `1 205`, the m³ figure of a storage row.
    static func volume(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }
}

extension PlanetKind {
    var title: String {
        switch self {
        case .barren: String(localized: "Barren")
        case .gas: String(localized: "Gas")
        case .ice: String(localized: "Ice")
        case .lava: String(localized: "Lava")
        case .oceanic: String(localized: "Oceanic")
        case .plasma: String(localized: "Plasma")
        case .storm: String(localized: "Storm")
        case .temperate: String(localized: "Temperate")
        case .unknown: String(localized: "Planet")
        }
    }
}

extension FacilityKind {
    /// What the game calls it, without the planet type: `Storage Facility`.
    var title: String {
        switch self {
        case .commandCenter: String(localized: "Command Center")
        case .extractor: String(localized: "Extractor")
        case .basicIndustry: String(localized: "Basic Industry")
        case .advancedIndustry: String(localized: "Advanced Industry")
        case .highTechIndustry: String(localized: "High-Tech Industry")
        case .storage: String(localized: "Storage Facility")
        case .launchpad: String(localized: "Launchpad")
        }
    }

    /// For a tile tag or a subtitle: `BASIC`, `ECU`.
    var shortTitle: String {
        switch self {
        case .commandCenter: String(localized: "Command Center")
        case .extractor: String(localized: "ECU")
        case .basicIndustry: String(localized: "planetary.facility.basic", defaultValue: "Basic", comment: "Short tag of a Basic Industry Facility (neuter: производство)")
        case .advancedIndustry: String(localized: "planetary.facility.advanced", defaultValue: "Advanced", comment: "Short tag of an Advanced Industry Facility (neuter: производство)")
        case .highTechIndustry: String(localized: "High-Tech")
        case .storage: String(localized: "Storage")
        case .launchpad: String(localized: "Launchpad")
        }
    }
}

extension ColonyStatus {
    var chip: HUDStatusChip {
        switch self {
        case .running: HUDStatusChip(text: Text("Running"), color: .hudOk, mark: .dot)
        case .filling: HUDStatusChip(text: Text("Filling"), color: .hudWarn, mark: .dot)
        case .stopped: HUDStatusChip(text: Text("Stopped"), color: .hudWarn, mark: .symbol("pause.fill"))
        }
    }
}

extension PlanetInfo {
    var displayName: String {
        name ?? String(localized: "Planet \(planetID)")
    }

    /// `OSOGGUR 0.5`, the security in its colour; `nil` until the SDE has named the system.
    var systemText: Text? {
        guard let solarSystemName else { return nil }
        var text = Text(verbatim: solarSystemName.uppercased())
        if let securityStatus {
            let security = Text(verbatim: SecurityStatus.string(securityStatus))
                .foregroundStyle(SecurityStatus.color(securityStatus))
            text = Text("\(text)\(Text(verbatim: " "))\(security)")
        }
        return text
    }
}

// MARK: - Issues

/// One issue in words, in every form the screens need.
struct ColonyIssueText {
    /// The list's headline label, caps: `LAUNCHPAD FULL`.
    var label: String
    /// `Launchpad full`.
    var title: String
    /// The sentence under the title.
    var detail: String
    /// What to do about it, for the list's warn note. `nil` for the informational ones.
    var advice: String?
    /// `in 14h 00m`, `to end`, `idle`.
    var when: String
    /// The absolute moment under a relative `when`: `10.20 08:20`.
    var whenDetail: String?
    var isWarning: Bool
    /// Where a tap on it goes.
    var route: PlanetaryRoute?
}

extension ColonyDetail {
    /// `Launchpad`, or `Storage Facility G3-M5R` where the colony has more than one of a kind.
    func facilityName(_ pinID: Int64) -> String {
        guard let facility = facility(pinID: pinID) else { return String(localized: "Facility") }
        let sameKind = facilities.filter { $0.kind == facility.kind }.count
        return sameKind > 1 ? "\(facility.kind.title) \(facility.name)" : facility.kind.title
    }

    /// `Biocells factory`, or the facility's name for anything that is not a factory.
    func producerName(_ pinID: Int64) -> String {
        guard let facility = facility(pinID: pinID) else { return facilityName(pinID) }
        if case let .factory(factory) = facility.role, let output = factory.output {
            return String(localized: "\(output.commodity.name) factory")
        }
        return facilityName(pinID)
    }

    var extractorProgramCount: Int {
        facilities.filter {
            if case let .extractor(extractor) = $0.role { extractor.program != nil } else { false }
        }.count
    }

    func describe(_ issue: ColonyIssue, now: Date) -> ColonyIssueText {
        let planetID = id
        func relative(_ date: Date) -> String { EVETime.relative(date, now: now) }
        func moment(_ date: Date) -> String { EVETime.monthDayTime(date) }

        switch issue {
        case let .extractorsFinish(at, count):
            let total = max(count, extractorProgramCount)
            let detail = if total == 1 {
                String(localized: "The program ends. Restart it in game before then.")
            } else if count == total {
                String(localized: "All \(total) programs end together. Restart them in game before then.")
            } else {
                String(localized: "\(count) of \(total) programs end first. Restart them in game before then.")
            }
            return ColonyIssueText(label: String(localized: "Extractors finish"), title: String(localized: "Extractors finish"),
                                   detail: detail, advice: nil, when: relative(at), whenDetail: moment(at),
                                   isWarning: false, route: nil)

        case let .extractorsStopped(since):
            let detail = since.map {
                String(localized: "Programs ended \(EVETime.dateTime($0)). Factories run on what is stored until it runs out.")
            } ?? String(localized: "No extractor program is running.")
            let advice = since.map { String(localized: "Programs ended \(EVETime.dateTime($0)). Restart the extractors in game.") }
                ?? String(localized: "Restart the extractors in game.")
            return ColonyIssueText(label: String(localized: "Extractors stopped"), title: String(localized: "Extractors stopped"),
                                   detail: detail, advice: advice, when: since.map(relative) ?? String(localized: "now"),
                                   whenDetail: since.map(moment), isWarning: true, route: nil)

        case let .storageFull(pinID, at):
            let name = facilityName(pinID)
            let detail = at <= now
                ? String(localized: "Full since \(EVETime.dateTime(at)): new output has nowhere to go and is lost.")
                : String(localized: "After \(EVETime.dateTime(at)) new output has nowhere to go and is lost.")
            return ColonyIssueText(label: String(localized: "\(name) full"), title: String(localized: "\(name) full"),
                                   detail: detail, advice: detail + " " + String(localized: "Empty the \(name) in game."),
                                   when: relative(at), whenDetail: moment(at), isWarning: true,
                                   route: .facility(planetID: planetID, pinID: pinID))

        case let .outputWasted(pinID, commodity, at, quantity):
            let source = producerName(pinID)
            let detail = String(localized: "The \(source) has nowhere to put it from \(EVETime.dateTime(at)) on.")
            return ColonyIssueText(label: String(localized: "\(commodity.name) lost"),
                                   title: String(localized: "\(PlanetaryFormat.quantity(quantity)) \(commodity.name) lost"),
                                   detail: detail, advice: detail + " " + String(localized: "Make room for it in game."),
                                   when: relative(at), whenDetail: moment(at), isWarning: true,
                                   route: .facility(planetID: planetID, pinID: pinID))

        case let .outputLimited(_, product, waitingFor, limit, share):
            var detail = String(localized: "The \(product.name) factory waits \(FitStatFormat.percent(share)) of the remaining time.")
            if limit != waitingFor {
                detail += " " + String(localized: "\(limit.name) are the limit.")
            }
            return ColonyIssueText(label: String(localized: "Waits for \(waitingFor.name)"),
                                   title: String(localized: "\(product.name) wait for \(waitingFor.name)"),
                                   detail: detail, advice: nil, when: String(localized: "to end"), whenDetail: nil,
                                   isWarning: false, route: .chain(planetID: planetID))

        case let .stockRunsOut(pinID, commodity, at):
            let name = facilityName(pinID)
            let detail = String(localized: "Nothing in the colony makes it; the \(name) has none left from \(EVETime.dateTime(at)).")
            return ColonyIssueText(label: String(localized: "\(commodity.name) runs out"),
                                   title: String(localized: "\(commodity.name) runs out"), detail: detail,
                                   advice: detail + " " + String(localized: "Bring more to the \(name) in game."),
                                   when: relative(at), whenDetail: moment(at), isWarning: true,
                                   route: .facility(planetID: planetID, pinID: pinID))

        case let .unusedStock(pinID, commodity, quantity):
            let name = facilityName(pinID)
            var volume = Double(quantity) * commodity.volume
            if let facility = facility(pinID: pinID), case let .storage(storage) = facility.role,
               let stock = storage.contents.first(where: { $0.commodity == commodity }) {
                volume = stock.volume
            }
            return ColonyIssueText(label: String(localized: "Unused \(commodity.name)"),
                                   title: String(localized: "\(PlanetaryFormat.quantity(quantity)) \(commodity.name) unused"),
                                   detail: String(localized: "No factory takes them. \(FitStatFormat.m³(volume)) in the \(name)."),
                                   advice: nil, when: String(localized: "idle"), whenDetail: nil, isWarning: false,
                                   route: .facility(planetID: planetID, pinID: pinID))

        case let .extractorNotSetUp(pinID):
            let pin = facility(pinID: pinID)?.name ?? ""
            let detail = String(localized: "Extractor \(pin) has no program and extracts nothing.")
            return ColonyIssueText(label: String(localized: "Extractor not set up"),
                                   title: String(localized: "Extractor not set up"), detail: detail,
                                   advice: detail + " " + String(localized: "Start a program in game."),
                                   when: String(localized: "now"), whenDetail: nil, isWarning: true,
                                   route: .facility(planetID: planetID, pinID: pinID))

        case let .factoryNotSetUp(pinID):
            let pin = facility(pinID: pinID)?.name ?? ""
            let detail = String(localized: "Factory \(pin) has no schematic and makes nothing.")
            return ColonyIssueText(label: String(localized: "Factory not set up"),
                                   title: String(localized: "Factory not set up"), detail: detail,
                                   advice: detail + " " + String(localized: "Pick a schematic in game."),
                                   when: String(localized: "now"), whenDetail: nil, isWarning: true,
                                   route: .facility(planetID: planetID, pinID: pinID))
        }
    }

    /// Where the forecast stops, in words: `program end` or `a day ahead`.
    var horizonIsProgramEnd: Bool {
        programEnd.map { $0 > now } ?? false
    }

    /// The storage that ends the forecast fullest, for the colony's summary.
    var fullestStorage: (facility: FacilityDetail, storage: StorageDetail)? {
        facilities.compactMap { facility -> (FacilityDetail, StorageDetail)? in
            guard case let .storage(storage) = facility.role, storage.capacity > 0 else { return nil }
            return (facility, storage)
        }
        .max { $0.1.usedAtEnd / $0.1.capacity < $1.1.usedAtEnd / $1.1.capacity }
        .map { (facility: $0.0, storage: $0.1) }
    }
}
