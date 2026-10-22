import AssetsKit
import SDEKit
import SwiftUI

// Phrasing of the index for every Assets screen. Subtitles are natural case; `HUDRowTitle`
// upper-cases them.

enum AssetsFormat {
    /// `1 234`, grouped the way the locale groups.
    static func quantity(_ value: Int64) -> String {
        value.formatted(.number)
    }

    static func count(_ value: Int) -> String {
        value.formatted(.number)
    }

    /// `1 item`, `25 items`.
    static func items(_ count: Int) -> String {
        String(localized: "\(count) items")
    }

    /// `1 ship`, `9 ships`.
    static func ships(_ count: Int64) -> String {
        String(localized: "\(count) ships")
    }

    /// The trailing figure of a ship section header: `5/5`, `45 / 50 m³`.
    static func capacity(_ capacity: AssetCapacity) -> String {
        switch capacity {
        case let .slots(used, total):
            "\(used)/\(total)"
        case let .volume(used, total):
            "\(FitStatFormat.plain(used)) / \(FitStatFormat.m³(total))"
        }
    }
}

extension AssetLocation {
    /// A structure Neocom may not see into, or a place nobody could name.
    var isUnknown: Bool {
        kind == .structureNoAccess || kind == .unknown
    }

    var displayName: String {
        if let name { return name }
        switch kind {
        case .structure, .structureNoAccess: return String(localized: "Unknown structure")
        case .station: return String(localized: "Unknown station")
        case .solarSystem: return String(localized: "Unknown system")
        case .unknown: return String(localized: "Unknown location")
        }
    }

    /// The navigation bar's title: the station's name up to its operator, as in `Rens VI – Moon 8`.
    var shortName: String {
        let parts = displayName.components(separatedBy: " – ")
        guard parts.count > 2 else { return displayName }
        return parts.dropLast().joined(separator: " – ")
    }

    var systemImage: String {
        switch kind {
        case .station: "building.columns"
        case .structure: "building.2"
        case .solarSystem: "sun.max"
        case .structureNoAccess, .unknown: "questionmark"
        }
    }

    /// `RENS 0.9`, the security in its colour; `nil` when the system is not known.
    var systemText: Text? {
        guard let system else { return nil }
        let security = Text(verbatim: SecurityStatus.string(system.securityStatus))
            .foregroundStyle(SecurityStatus.color(system.securityStatus))
        return Text("\(Text(verbatim: system.name.uppercased())) \(security)")
    }

    /// `RENS 0.9 · HEIMATAR`, for a header; `nil` when the system is not known.
    var systemRegionText: Text? {
        guard let systemText, let system else { return nil }
        return Text("\(systemText) · \(Text(verbatim: system.regionName.uppercased()))")
    }

    /// The row of the list: `RENS 0.9 · 25 ITEMS`, or `STRUCTURE · 854 ITEMS` where no system
    /// is known.
    var listSubtitle: Text {
        let items = Text(verbatim: AssetsFormat.items(itemCount).uppercased())
        if let systemText {
            return Text("\(systemText) · \(items)")
        }
        let place = switch kind {
        case .structure, .structureNoAccess: String(localized: "assets.location.structure", defaultValue: "Structure", comment: "An Upwell structure as a kind of location")
        case .station: String(localized: "Station")
        case .solarSystem: String(localized: "In space")
        case .unknown: String(localized: "Location")
        }
        return Text("\(Text(verbatim: place.uppercased())) · \(items)")
    }
}

extension AssetRow {
    var typeIDValue: TypeID {
        TypeID(rawValue: UInt32(clamping: typeID))
    }

    /// What the mono line under the name says:
    ///
    /// - an assembled ship: `CRUISER · ASSEMBLED`, its type first when it has a name of its own
    ///   (`THORAX · CRUISER · ASSEMBLED`);
    /// - a packaged ship: `CORVETTE · PACKAGED`;
    /// - a container: `STATION CONTAINER · 9 ITEMS`;
    /// - a blueprint copy: `BPC · HYBRID CHARGE BLUEPRINT`;
    /// - anything else: its group.
    var subtitle: String {
        let group = groupName.isEmpty ? categoryName : groupName
        switch kind {
        case .ship:
            let assembled = String(localized: "Assembled")
            return customName != nil ? "\(typeName) · \(group) · \(assembled)" : "\(group) · \(assembled)"
        case .container:
            let base = customName != nil && typeName != group ? "\(typeName) · \(group)" : group
            return "\(base) · \(AssetsFormat.items(childCount))"
        case .item:
            if isShipType {
                return "\(group) · \(isAssembled ? String(localized: "Assembled") : String(localized: "Packaged"))"
            }
            if isBlueprintCopy {
                return "\(String(localized: "BPC")) · \(group)"
            }
            return group
        }
    }

    /// `×1 234`, for a stack of more than one.
    var quantityText: Text? {
        quantity > 1 ? Text(verbatim: "×" + AssetsFormat.quantity(quantity)) : nil
    }
}
