import CryptoKit
import DemoFixtures
import Foundation

public enum DemoExportError: Error, CustomStringConvertible {
    case missingPilotProfile(Int64)
    case overBudget(size: Int, budget: Int)
    case leaks([String])

    public var description: String {
        switch self {
        case let .missingPilotProfile(id):
            "The recording has no GET /characters/\(id) response."
        case let .overBudget(size, budget):
            "The archive is \(size) bytes, over the budget of \(budget) bytes."
        case let .leaks(findings):
            "The archive leaks the real pilot:\n" + findings.map { "  - \($0)" }.joined(separator: "\n")
        }
    }
}

/// What identifies the real pilot of a recording.
public struct DemoRealIdentity: Sendable {
    public var characterID: Int64
    public var name: String
    public var corporationID: Int64?
    public var allianceID: Int64?
    public var ownerHash: String?

    public init(characterID: Int64, name: String, corporationID: Int64?, allianceID: Int64?, ownerHash: String?) {
        self.characterID = characterID
        self.name = name
        self.corporationID = corporationID
        self.allianceID = allianceID
        self.ownerHash = ownerHash
    }

    /// Read from the recorded `GET /characters/{id}` of the pilot.
    public init(recording: DemoRecording) throws {
        let profile = recording.entries.first {
            $0.operationID == "GetCharactersDetail" && $0.method == "GET" && (200 ..< 300).contains($0.status)
                && DemoExporter.ids(inPath: $0.path).contains(recording.pilotID)
        }?.body
        guard let name = profile?["name"]?.string else {
            throw DemoExportError.missingPilotProfile(recording.pilotID)
        }
        self.init(characterID: recording.pilotID, name: name, corporationID: profile?["corporation_id"]?.int,
                  allianceID: profile?["alliance_id"]?.int, ownerHash: recording.ownerHash)
    }
}

/// Turns a raw recording into the anonymised demo archive.
public struct DemoExporter {
    public let config: DemoConfig

    public init(config: DemoConfig) {
        self.config = config
    }

    /// Ids at or above this value are Upwell structures or items, never stations.
    static let structureThreshold: Int64 = 1_000_000_000_000

    static let locationKeys: Set<String> = [
        "location_id", "station_id", "structure_id", "facility_id", "start_location_id", "end_location_id",
        "blueprint_location_id", "output_location_id",
    ]

    static let partyKeys: [String: String] = [
        "issuer_id": "character", "assignee_id": "character", "acceptor_id": "character", "bidder_id": "character",
        "character_id": "character", "first_party_id": "character", "second_party_id": "character",
        "client_id": "character", "installer_id": "character", "completed_character_id": "character",
        "issuer_corporation_id": "corporation",
    ]

    /// Replaced by synthetic content or folded into the archive tables.
    static func isDropped(_ operationID: String) -> Bool {
        operationID.contains("Mail") || operationID.contains("Contacts") || operationID.contains("Search")
            || operationID.contains("Cspa") || operationID == "PostUniverseNames"
            || operationID == "PostCharactersCharacterIdAssetsNames" || operationID == "GetUniverseStructuresStructureId"
    }

    public func export(_ recording: DemoRecording) throws -> DemoArchive {
        let identity = try DemoRealIdentity(recording: recording)
        var rewriter = Rewriter(config: config, identity: identity)
        let succeeded = recording.entries.filter { (200 ..< 300).contains($0.status) }

        var recordedNames: [Int64: DemoArchive.Name] = [:]
        var assetNames: [String: String] = [:]
        for entry in succeeded {
            switch entry.operationID {
            case "PostUniverseNames":
                for item in entry.body?.array ?? [] {
                    guard let id = item["id"]?.int, let name = item["name"]?.string,
                          let category = item["category"]?.string else { continue }
                    recordedNames[id] = DemoArchive.Name(name: name, category: category)
                }
            case "PostCharactersCharacterIdAssetsNames" where Self.ids(inPath: entry.path).contains(identity.characterID):
                for item in entry.body?.array ?? [] {
                    guard let id = item["item_id"]?.int, let name = item["name"]?.string, name != "None" else { continue }
                    assetNames[String(id)] = name
                }
            default:
                break
            }
        }
        if let corporationID = identity.corporationID, let name = recordedNames[corporationID]?.name {
            rewriter.corporationName = name
        }

        var itemIDs = Set<Int64>()
        for entry in succeeded {
            entry.body.map { Self.collect(key: "item_id", in: $0, into: &itemIDs) }
        }
        var structures = Set<Int64>()
        for entry in succeeded {
            if entry.operationID == "GetUniverseStructuresStructureId", let id = Self.ids(inPath: entry.path).last {
                structures.insert(id)
            }
            guard Self.ids(inPath: entry.path).contains(identity.characterID), let body = entry.body else { continue }
            var locations = Set<Int64>()
            for key in Self.locationKeys {
                Self.collect(key: key, in: body, into: &locations)
            }
            structures.formUnion(locations.filter { $0 >= Self.structureThreshold && !itemIDs.contains($0) })
        }
        rewriter.structures = structures

        for entry in succeeded where entry.operationID == "GetCharactersCharacterIdKillmailsRecent" {
            for item in entry.body?.array ?? [] {
                guard let id = item["killmail_id"]?.int, let hash = item["killmail_hash"]?.string else { continue }
                rewriter.mapKillmail(id: id, hash: hash)
            }
        }

        var entries: [DemoArchive.Entry] = []
        for entry in succeeded where !Self.isDropped(entry.operationID) {
            let pathIDs = Self.ids(inPath: entry.path)
            let isKillmail = entry.operationID == "GetKillmailsKillmailIdKillmailHash"
                && pathIDs.contains { rewriter.killmails[$0] != nil }
            guard pathIDs.contains(identity.characterID) || isKillmail else { continue }
            var output = entry
            output.path = rewriter.rewrite(path: entry.path)
            output.requestBody = nil
            if let requestBody = entry.requestBody {
                output.bodyDigest = DemoRequestKey.digest(of: rewriter.rewrite(requestBody, operationID: entry.operationID))
            }
            output.body = entry.body.map { rewriter.rewrite($0, operationID: entry.operationID) }
            if entry.operationID == "GetCharactersDetail" {
                output.body?["description"] = .string("")
                output.body?["title"] = nil
            }
            entries.append(output)
        }
        entries.append(contentsOf: syntheticMail(recordedAt: recording.recordedAt))
        entries.append(contacts())

        var names: [String: DemoArchive.Name] = [:]
        for (id, name) in recordedNames {
            if name.category == "character", !(3_000_000 ..< 4_000_000).contains(id) { continue }
            if id == identity.corporationID || id == identity.allianceID || rewriter.synthetic[id] != nil
                || structures.contains(id) { continue }
            names[String(id)] = name
        }
        for (_, synthetic) in rewriter.synthetic {
            names[String(synthetic.id)] = DemoArchive.Name(name: synthetic.name, category: synthetic.category)
        }
        for sender in config.mail.senders {
            names[String(sender.id)] = DemoArchive.Name(name: sender.name, category: "character")
        }
        names[String(DemoIDs.characterID)] = DemoArchive.Name(name: config.pilot.name, category: "character")
        names[String(config.pilot.corporationID)] = DemoArchive.Name(name: config.pilot.corporationName,
                                                                     category: "corporation")
        names[String(config.pilot.homeStationID)] = DemoArchive.Name(name: config.pilot.homeStationName,
                                                                     category: "station")

        var archive = DemoArchive(
            recordedAt: recording.recordedAt,
            compatibilityDate: recording.compatibilityDate,
            pilot: DemoArchive.Pilot(id: DemoIDs.characterID, name: config.pilot.name,
                                     corporationID: config.pilot.corporationID),
            entries: entries.sorted { ($0.path, $0.operationID, $0.query, $0.method) < ($1.path, $1.operationID, $1.query, $1.method) },
            names: names,
            assetNames: assetNames.mapValues { rewriter.rewrite(string: $0) },
            plan: config.plan
        )
        try Self.trim(&archive, budget: config.sizeBudget)
        return archive
    }

    /// Encodes the archive and fails when it still contains anything of the real pilot.
    public func encode(_ archive: DemoArchive, recording: DemoRecording) throws -> Data {
        let data = try archive.encoded()
        let findings = Self.leaks(in: data, identity: try DemoRealIdentity(recording: recording))
        guard findings.isEmpty else { throw DemoExportError.leaks(findings) }
        return data
    }

    /// Everything in `data` that points at the real pilot.
    public static func leaks(in data: Data, identity: DemoRealIdentity) -> [String] {
        let text = String(decoding: data, as: UTF8.self)
        var findings: [String] = []
        func search(_ pattern: String, _ label: String) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let count = regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
            if count > 0 { findings.append("\(label): \(count) occurrence(s)") }
        }
        search("(?<![0-9])\(identity.characterID)(?![0-9])", "character id")
        if let id = identity.corporationID { search("(?<![0-9])\(id)(?![0-9])", "corporation id") }
        if let id = identity.allianceID { search("(?<![0-9])\(id)(?![0-9])", "alliance id") }
        search(NSRegularExpression.escapedPattern(for: identity.name), "character name")
        if let hash = identity.ownerHash, !hash.isEmpty {
            search(NSRegularExpression.escapedPattern(for: hash), "owner hash")
        }
        search("eyJ[A-Za-z0-9_-]{8,}", "token-like string")
        return findings
    }

    // MARK: - Synthetic content

    func syntheticMail(recordedAt: Date) -> [DemoArchive.Entry] {
        let mail = config.mail
        let base = "/characters/\(DemoIDs.characterID)/mail"
        let messages = mail.messages.sorted { $0.hoursAgo < $1.hoursAgo }
        func timestamp(_ message: DemoConfig.Message) -> DemoJSON {
            .string(DemoRebaser.timestamp(recordedAt.addingTimeInterval(-message.hoursAgo * 3600)))
        }
        func recipients(_ message: DemoConfig.Message) -> DemoJSON {
            let recipients = message.recipients ?? [DemoConfig.Recipient(id: DemoIDs.characterID, type: "character")]
            return .array(recipients.map { .object(["recipient_id": .int($0.id), "recipient_type": .string($0.type)]) })
        }
        func labels(_ message: DemoConfig.Message) -> DemoJSON {
            .array(message.labels.map(DemoJSON.int))
        }
        func headers(_ filter: Int64?) -> DemoJSON {
            .array(messages.filter { filter == nil || $0.labels.contains(filter!) }.map { message in
                .object([
                    "mail_id": .int(message.mailID), "from": .int(message.from), "subject": .string(message.subject),
                    "timestamp": timestamp(message), "labels": labels(message), "is_read": .bool(message.isRead),
                    "recipients": recipients(message),
                ])
            })
        }

        var entries = [DemoArchive.Entry(operationID: "GetCharactersCharacterIdMail", method: "GET", path: base,
                                         body: headers(nil))]
        for label in mail.labels {
            entries.append(DemoArchive.Entry(operationID: "GetCharactersCharacterIdMail", method: "GET", path: base,
                                             query: "labels=\(label.labelID)", body: headers(label.labelID)))
        }
        let unread = mail.labels.map { label in
            Int64(messages.filter { !$0.isRead && $0.labels.contains(label.labelID) }.count)
        }
        entries.append(DemoArchive.Entry(
            operationID: "GetCharactersCharacterIdMailLabels", method: "GET", path: base + "/labels",
            body: .object([
                "labels": .array(zip(mail.labels, unread).map { label, unread in
                    .object(["label_id": .int(label.labelID), "name": .string(label.name),
                             "color": .string(label.color), "unread_count": .int(unread)])
                }),
                "total_unread_count": .int(Int64(messages.filter { !$0.isRead }.count)),
            ])
        ))
        entries.append(DemoArchive.Entry(
            operationID: "GetCharactersCharacterIdMailLists", method: "GET", path: base + "/lists",
            body: .array(mail.mailingLists.map {
                .object(["mailing_list_id": .int($0.mailingListID), "name": .string($0.name)])
            })
        ))
        for message in messages {
            entries.append(DemoArchive.Entry(
                operationID: "GetCharactersCharacterIdMailMailId", method: "GET", path: base + "/\(message.mailID)",
                body: .object([
                    "body": .string(message.body), "from": .int(message.from), "labels": labels(message),
                    "read": .bool(message.isRead), "recipients": recipients(message),
                    "subject": .string(message.subject), "timestamp": timestamp(message),
                ])
            ))
        }
        return entries
    }

    func contacts() -> DemoArchive.Entry {
        DemoArchive.Entry(
            operationID: "GetCharactersCharacterIdContacts", method: "GET",
            path: "/characters/\(DemoIDs.characterID)/contacts", headers: DemoArchive.Headers(xPages: 1),
            body: .array(config.contacts.map {
                .object(["contact_id": .int($0.id), "contact_type": .string("character"), "standing": .double($0.standing)])
            })
        )
    }

    // MARK: - Budget

    /// Drops trailing pages of paged routes, then halves the largest arrays, until the archive fits.
    static func trim(_ archive: inout DemoArchive, budget: Int) throws {
        var size = try archive.encoded().count
        while size > budget {
            let paged = archive.entries.indices.filter { (archive.entries[$0].headers.xPages ?? 1) > 1 }
            let groups = Dictionary(grouping: paged) { index in
                let entry = archive.entries[index]
                return [entry.method, entry.operationID, entry.path,
                        entry.query.split(separator: "&").filter { !$0.hasPrefix("page=") }.joined(separator: "&")]
            }
            if let group = groups.values.max(by: { $0.count < $1.count }), group.count > 1 {
                let last = group.max { archive.entries[$0].page < archive.entries[$1].page }!
                let pages = group.count - 1
                for index in group {
                    archive.entries[index].headers.xPages = pages
                }
                archive.entries.remove(at: last)
            } else {
                let sizes = archive.entries.indices.map { index in
                    (index, archive.entries[index].body?.array?.count ?? 0,
                     (try? archive.entries[index].body?.data().count) ?? 0)
                }
                guard let (index, count, _) = sizes.filter({ $0.1 > 1 }).max(by: { $0.2 < $1.2 }) else {
                    throw DemoExportError.overBudget(size: size, budget: budget)
                }
                archive.entries[index].body = .array(Array(archive.entries[index].body!.array!.prefix(count / 2)))
            }
            size = try archive.encoded().count
        }
    }

    // MARK: - Helpers

    static func ids(inPath path: String) -> [Int64] {
        path.split(separator: "/").compactMap { Int64($0) }
    }

    static func collect(key: String, in json: DemoJSON, into ids: inout Set<Int64>) {
        switch json {
        case let .object(object):
            for (name, value) in object {
                if name == key, let id = value.int { ids.insert(id) }
                collect(key: key, in: value, into: &ids)
            }
        case let .array(values):
            for value in values { collect(key: key, in: value, into: &ids) }
        default:
            break
        }
    }
}

/// Rewrites ids and names of the real pilot and the third parties around it.
struct Rewriter {
    struct Synthetic {
        var id: Int64
        var name: String
        var category: String
    }

    let config: DemoConfig
    let identity: DemoRealIdentity
    var corporationName: String?
    var structures = Set<Int64>()
    private(set) var killmails: [Int64: Int64] = [:]
    private(set) var killmailHashes: [String: String] = [:]
    private(set) var synthetic: [Int64: Synthetic] = [:]
    private var nextID = DemoIDs.syntheticRange.lowerBound + 100_000
    private var characterCount = 0
    private var corporationCount = 0

    init(config: DemoConfig, identity: DemoRealIdentity) {
        self.config = config
        self.identity = identity
    }

    mutating func allocate() -> Int64 {
        defer { nextID += 1 }
        return nextID
    }

    mutating func mapKillmail(id: Int64, hash: String) {
        guard killmails[id] == nil else { return }
        let synthetic = allocate()
        killmails[id] = synthetic
        let digest = SHA256.hash(data: Data("demo-killmail-\(synthetic)".utf8))
        killmailHashes[hash] = String(digest.map { String(format: "%02x", $0) }.joined().prefix(40))
    }

    mutating func party(_ id: Int64, category: String) -> Int64 {
        if let existing = synthetic[id] { return existing.id }
        let name: String
        if category == "corporation" {
            name = Self.pick(config.syntheticCorporationNames, corporationCount, fallback: "Demo Holdings")
            corporationCount += 1
        } else {
            name = Self.pick(config.syntheticCharacterNames, characterCount, fallback: "Capsuleer")
            characterCount += 1
        }
        let entry = Synthetic(id: allocate(), name: name, category: category)
        synthetic[id] = entry
        return entry.id
    }

    private static func pick(_ names: [String], _ index: Int, fallback: String) -> String {
        guard !names.isEmpty else { return "\(fallback) \(index + 1)" }
        let round = index / names.count
        return round == 0 ? names[index] : "\(names[index % names.count]) \(round + 1)"
    }

    func isThirdParty(_ id: Int64) -> Bool {
        guard id > 0, id != identity.characterID, id != identity.corporationID, !DemoIDs.contains(id) else { return false }
        return !(500_000 ..< 4_000_000).contains(id)
    }

    mutating func rewrite(path: String) -> String {
        let segments = path.split(separator: "/", omittingEmptySubsequences: false).map { segment -> String in
            if let id = Int64(segment) {
                if id == identity.characterID { return String(DemoIDs.characterID) }
                if let killmail = killmails[id] { return String(killmail) }
                if structures.contains(id) { return String(config.pilot.homeStationID) }
                return String(segment)
            }
            return killmailHashes[String(segment)] ?? String(segment)
        }
        return segments.joined(separator: "/")
    }

    func rewrite(string: String) -> String {
        var string = string.replacingOccurrences(of: identity.name, with: config.pilot.name)
        if let corporationName {
            string = string.replacingOccurrences(of: corporationName, with: config.pilot.corporationName)
        }
        return string
    }

    mutating func rewrite(_ json: DemoJSON, operationID: String, key: String? = nil) -> DemoJSON {
        switch json {
        case let .int(value):
            return .int(rewrite(int: value, key: key, operationID: operationID))
        case let .string(value):
            return .string(killmailHashes[value] ?? rewrite(string: value))
        case let .array(values):
            return .array(values.map { rewrite($0, operationID: operationID, key: key) })
        case let .object(object):
            var output: [String: DemoJSON] = [:]
            for (name, value) in object.sorted(by: { $0.key < $1.key }) {
                if name.contains("alliance"), let id = value.int, id == identity.allianceID { continue }
                output[name] = rewrite(value, operationID: operationID, key: name)
            }
            if let location = object["location_id"]?.int, structures.contains(location),
               let type = output["location_type"]?.string, type == "structure" || type == "item" {
                output["location_type"] = .string("station")
            }
            if let structure = object["structure_id"]?.int, structures.contains(structure) {
                output["structure_id"] = nil
                output["station_id"] = .int(config.pilot.homeStationID)
                if output["solar_system_id"] != nil {
                    output["solar_system_id"] = .int(config.pilot.homeSolarSystemID)
                }
            }
            return .object(output)
        default:
            return json
        }
    }

    mutating func rewrite(int value: Int64, key: String?, operationID: String) -> Int64 {
        if value == identity.characterID { return DemoIDs.characterID }
        if value == identity.corporationID { return config.pilot.corporationID }
        guard let key else { return value }
        if Self.locationKeys.contains(key), structures.contains(value) { return config.pilot.homeStationID }
        if key == "killmail_id", let killmail = killmails[value] { return killmail }
        if let category = DemoExporter.partyKeys[key], isThirdParty(value) {
            return party(value, category: category)
        }
        return value
    }

    private static var locationKeys: Set<String> { DemoExporter.locationKeys }
}
