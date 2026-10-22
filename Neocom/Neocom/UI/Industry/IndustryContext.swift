import AssetsKit
import BusinessKit
import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI

// Names from the static data, manufacturing yields and the places ESI named, read once per
// screen and passed down as a plain value.

/// A type with the group it belongs to.
@Projection
struct IndustryTypeRow: Sendable, Identifiable {
    var id: TypeID
    var name: String
    var groupName: String
}

/// What one run of a blueprint's activity yields.
@Projection
struct IndustryOutputRow: Sendable {
    var blueprintID: TypeID
    var activity: BlueprintActivity
    var quantity: Int
}

enum IndustryBrowser {
    static func types(_ types: [TypeID]) -> SQLQuery<IndustryTypeRow> {
        let withName = TypeInfo.all()
            .join(NameRow.self) { type, name in type.nameID == name.id }
        let withGroup = withName
            .join(GroupInfo.self) { type, _, group in type.groupID == group.id }
        let withGroupName = withGroup
            .join(NameRow.self) { _, _, group, groupName in group.nameID == groupName.id }
        return withGroupName
            .filter { type, _, _, _ in type.id.in(types) }
            .select { type, name, _, groupName in
                IndustryTypeRow.projection(id: type.id, name: name.text, groupName: groupName.text)
            }
            .query()
    }

    static func outputs(of blueprints: [TypeID]) -> SQLQuery<IndustryOutputRow> {
        BlueprintProduct.all()
            .filter { product in product.blueprintID.in(blueprints) }
            .select { product in
                IndustryOutputRow.projection(blueprintID: product.blueprintID, activity: product.activity,
                                             quantity: product.quantity)
            }
            .query()
    }
}

/// The jobs' data with everything a screen needs to word it.
struct IndustryContext {
    var data: ESIIndustryJobs
    var characterID: Int64
    /// Custom names of the character's containers, by item id.
    var assetNames: [Int64: String]
    var types: [Int64: IndustryTypeRow]
    var systems: [Int64: MarketSystemRow]
    var outputs: [Int64: [BlueprintActivity: Int]]

    func job(_ id: Int64) -> IndustryJob? { data.jobs.first { $0.id == id } }

    // MARK: Types

    func typeName(_ id: Int64) -> String {
        types[id]?.name ?? String(localized: "Unknown type")
    }

    /// What a job is listed under: the product of a manufacturing or reaction job, the
    /// blueprint of the rest.
    func title(of job: IndustryJob) -> String {
        switch job.activity {
        case .manufacturing, .reaction: typeName(job.productTypeID ?? job.blueprintTypeID)
        default: typeName(job.blueprintTypeID)
        }
    }

    /// The type whose icon stands for the job.
    func iconType(of job: IndustryJob) -> Int64 {
        switch job.activity {
        case .manufacturing, .reaction: job.productTypeID ?? job.blueprintTypeID
        default: job.blueprintTypeID
        }
    }

    /// What the job makes: its product, or — for copying and research — the blueprint itself.
    func productType(of job: IndustryJob) -> Int64 {
        job.productTypeID ?? job.blueprintTypeID
    }

    /// Units a manufacturing or reaction job yields in all, where the static data says what a
    /// run gives.
    func units(of job: IndustryJob) -> Int? {
        let activity: BlueprintActivity
        switch job.activity {
        case .manufacturing: activity = .manufacturing
        case .reaction: activity = .reaction
        default: return nil
        }
        return outputs[job.blueprintTypeID]?[activity].map { $0 * job.runs }
    }

    // MARK: Places

    func location(of job: IndustryJob) -> AssetLocationInfo? {
        data.locations[job.stationID] ?? data.locations[job.facilityID]
    }

    func facilityName(of job: IndustryJob) -> String {
        if let name = location(of: job)?.name { return name }
        return String(localized: "Unknown structure")
    }

    func system(of job: IndustryJob) -> MarketSystemRow? {
        location(of: job)?.solarSystemID.flatMap { systems[$0] }
    }

    /// `NPC STATION`, or the structure's type: `Raitaru`.
    func facilityKind(of job: IndustryJob) -> String? {
        guard let location = location(of: job) else { return nil }
        switch location.kind {
        case .station: return String(localized: "NPC Station")
        case .structure: return location.typeID.map(typeName)
        default: return nil
        }
    }

    /// Where a blueprint comes from or an output goes to: the facility's hangar, or a container
    /// inside it.
    func place(_ id: Int64, in job: IndustryJob) -> String {
        if id == job.stationID || id == job.facilityID { return String(localized: "Item hangar") }
        if let name = assetNames[id] { return String(localized: "Container “\(name)”") }
        return String(localized: "Container")
    }

    func pilotName(_ id: Int64) -> String {
        data.names[id]?.name ?? String(localized: "Unknown pilot")
    }
}

/// Reads the static data the jobs refer to and hands the screen its `IndustryContext`.
struct IndustryContextReader<Content: View>: View {
    private let data: ESIIndustryJobs
    private let characterID: Int64
    private let assetNames: [Int64: String]
    private let content: (IndustryContext) -> Content

    @LiteQuery private var types: [IndustryTypeRow]
    @LiteQuery private var systems: [MarketSystemRow]
    @LiteQuery private var outputs: [IndustryOutputRow]

    /// `jobs` are the ones the screen draws — all of them for the list, one for its detail.
    init(data: ESIIndustryJobs, jobs: [IndustryJob], characterID: Int64, assetNames: [Int64: String],
         @ViewBuilder content: @escaping (IndustryContext) -> Content) {
        self.data = data
        self.characterID = characterID
        self.assetNames = assetNames
        self.content = content

        var typeIDs = Set<Int64>()
        var systemIDs = Set<Int64>()
        for job in jobs {
            typeIDs.insert(job.blueprintTypeID)
            if let product = job.productTypeID { typeIDs.insert(product) }
            if let location = data.locations[job.stationID] ?? data.locations[job.facilityID] {
                if let type = location.typeID { typeIDs.insert(type) }
                if let system = location.solarSystemID { systemIDs.insert(system) }
            }
        }
        _types = LiteQuery(IndustryBrowser.types(typeIDs.sorted().map(Self.typeID)))
        _systems = LiteQuery(MarketBrowser.systems(systemIDs.sorted().map(MarketFormat.systemID)))
        _outputs = LiteQuery(IndustryBrowser.outputs(of: Set(jobs.map(\.blueprintTypeID)).sorted().map(Self.typeID)))
    }

    private static func typeID(_ id: Int64) -> TypeID { TypeID(rawValue: UInt32(clamping: id)) }

    var body: some View {
        var outputsByBlueprint: [Int64: [BlueprintActivity: Int]] = [:]
        for row in outputs {
            outputsByBlueprint[Int64(row.blueprintID.rawValue), default: [:]][row.activity] = row.quantity
        }
        let context = IndustryContext(
            data: data, characterID: characterID, assetNames: assetNames,
            types: Dictionary(types.map { (Int64($0.id.rawValue), $0) }, uniquingKeysWith: { first, _ in first }),
            systems: Dictionary(systems.map { (Int64($0.id.rawValue), $0) }, uniquingKeysWith: { first, _ in first }),
            outputs: outputsByBlueprint)
        return content(context)
    }
}
