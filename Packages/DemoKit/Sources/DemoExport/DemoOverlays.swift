import DemoFixtures
import Foundation

/// Synthetic content from `DemoConfig.json` that replaces the recorded bodies of the business and
/// training routes, and the clean-up of strings the player wrote.
extension DemoExporter {
    static let skillQueueOperation = "GetCharactersCharacterIdSkillqueue"
    static let ordersOperation = "GetCharactersCharacterIdOrders"
    static let orderHistoryOperation = "GetCharactersCharacterIdOrdersHistory"
    static let industryJobsOperation = "GetCharactersCharacterIdIndustryJobs"
    static let contractsOperation = "GetCharactersCharacterIdContracts"
    static let contractItemsOperation = "GetCharactersCharacterIdContractsContractIdItems"

    /// Replaces the recorded bodies of the overlaid routes; a route missing from the recording
    /// stays missing.
    func applyOverlays(to entries: inout [DemoArchive.Entry], recordedAt: Date) throws {
        try validateSyntheticIDs()
        let base = "/characters/\(DemoIDs.characterID)"
        func index(_ operationID: String, _ path: String, query: String = "") -> Int? {
            entries.firstIndex { $0.operationID == operationID && $0.path == path && $0.query == query }
        }

        if let queue = index(Self.skillQueueOperation, base + "/skillqueue") {
            let attributes = entries.first { $0.operationID == "GetCharactersCharacterIdAttributes" && $0.path == base + "/attributes" }?.body
            let skills = entries.first { $0.operationID == "GetCharactersCharacterIdSkills" && $0.path == base + "/skills" }?.body
            entries[queue].body = try skillQueue(attributes: attributes, skills: skills, recordedAt: recordedAt)
        }
        if let orders = index(Self.ordersOperation, base + "/orders") {
            entries[orders].body = .array(config.orders.open.map { Self.json(order: $0, recordedAt: recordedAt) })
        }
        if let history = index(Self.orderHistoryOperation, base + "/orders/history") {
            // Recorded orders keep their contents; when they were issued is made up.
            let recorded = (entries[history].body?.array ?? []).enumerated().map { index, order in
                var order = order
                order["issued"] = Self.timestamp(recordedAt, hours: -(260 + 31 * Double(index)))
                return order
            }
            entries[history].body = .array(recorded + config.orders.history.map { Self.json(order: $0, recordedAt: recordedAt) })
        }
        if let jobs = index(Self.industryJobsOperation, base + "/industry/jobs", query: "include_completed=true") {
            entries[jobs].body = .array(config.industryJobs.map { Self.json(job: $0, recordedAt: recordedAt) })
        }
        if let contracts = index(Self.contractsOperation, base + "/contracts") {
            entries[contracts].body = .array(config.contracts.map { Self.json(contract: $0, recordedAt: recordedAt) })
            entries[contracts].headers.xPages = 1
            entries.removeAll { $0.operationID == Self.contractItemsOperation }
            for (contractIndex, contract) in config.contracts.enumerated() {
                let items = contract.items.enumerated().map { itemIndex, item in
                    Self.json(item: item, recordID: Self.recordID(contract: contractIndex, item: itemIndex))
                }
                entries.append(DemoArchive.Entry(operationID: Self.contractItemsOperation, method: "GET",
                                                 path: base + "/contracts/\(contract.contractID)/items",
                                                 body: .array(items)))
            }
        }
    }

    static func recordID(contract: Int, item: Int) -> Int64 {
        DemoIDs.syntheticRange.lowerBound + 8000 + Int64(contract) * 100 + Int64(item) + 1
    }

    // MARK: - Skill queue

    /// The queue, back to back, the first entry in training at `recordedAt`. Fails when the
    /// recorded skills do not lead into it: the first entry of each skill must start right at
    /// the level the pilot has, with the points of that level.
    func skillQueue(attributes: DemoJSON?, skills: DemoJSON?, recordedAt: Date) throws -> DemoJSON {
        let queue = config.skillQueue
        var trained: [Int64: (level: Int64, points: Int64)] = [:]
        for skill in skills?["skills"]?.array ?? [] {
            guard let id = skill["skill_id"]?.int, let level = skill["trained_skill_level"]?.int,
                  let points = skill["skillpoints_in_skill"]?.int else { continue }
            trained[id] = (level, points)
        }
        func attribute(_ name: String) throws -> Int {
            guard let value = attributes?[name]?.int else {
                throw DemoExportError.inconsistentSkillQueue("no recorded attribute \(name)")
            }
            return Int(value)
        }

        var start = recordedAt.addingTimeInterval(-queue.startedHoursAgo * 3600)
        start = Date(timeIntervalSince1970: start.timeIntervalSince1970.rounded(.down))
        var levels: [Int64: Int] = [:]
        var output: [DemoJSON] = []
        for (position, entry) in queue.entries.enumerated() {
            let expected: Int
            if let queued = levels[entry.skillID] {
                expected = queued
            } else {
                guard let recorded = trained[entry.skillID] else {
                    throw DemoExportError.inconsistentSkillQueue("skill \(entry.skillID) is not trained")
                }
                guard recorded.points == Self.skillPoints(rank: entry.rank, level: Int(recorded.level)) else {
                    throw DemoExportError.inconsistentSkillQueue(
                        "skill \(entry.skillID) has \(recorded.points) points, not the points of level \(recorded.level)")
                }
                expected = Int(recorded.level)
            }
            guard entry.level == expected + 1 else {
                throw DemoExportError.inconsistentSkillQueue(
                    "skill \(entry.skillID) is queued to level \(entry.level) after level \(expected)")
            }
            levels[entry.skillID] = entry.level

            let startPoints = Self.skillPoints(rank: entry.rank, level: entry.level - 1)
            let endPoints = Self.skillPoints(rank: entry.rank, level: entry.level)
            let rate = (Double(try attribute(entry.primary)) + Double(try attribute(entry.secondary)) / 2) / 60
            let finish = start.addingTimeInterval((Double(endPoints - startPoints) / rate).rounded())
            output.append(.object([
                "skill_id": .int(entry.skillID), "finished_level": .int(Int64(entry.level)),
                "queue_position": .int(Int64(position)),
                "level_start_sp": .int(startPoints), "level_end_sp": .int(endPoints), "training_start_sp": .int(startPoints),
                "start_date": .string(DemoRebaser.timestamp(start)), "finish_date": .string(DemoRebaser.timestamp(finish)),
            ]))
            start = finish
        }
        return .array(output)
    }

    /// EVE's points for a level: `250 · rank · √32^(level − 1)` rounded up (1415, not 1414, for
    /// level 2 of a rank 1 skill), 0 below level 1.
    public static func skillPoints(rank: Double, level: Int) -> Int64 {
        guard level > 0 else { return 0 }
        return Int64((250 * rank * pow(2, 2.5 * Double(level - 1)) - 1e-6).rounded(.up))
    }

    // MARK: - Bodies

    static func timestamp(_ recordedAt: Date, hours: Double) -> DemoJSON {
        .string(DemoRebaser.timestamp(recordedAt.addingTimeInterval(hours * 3600)))
    }

    static func json(order: DemoConfig.Order, recordedAt: Date) -> DemoJSON {
        var object: [String: DemoJSON] = [
            "order_id": .int(order.orderID), "type_id": .int(order.typeID), "is_buy_order": .bool(order.isBuyOrder),
            "is_corporation": .bool(false), "location_id": .int(order.locationID), "region_id": .int(order.regionID),
            "price": .double(order.price), "volume_total": .int(order.volumeTotal),
            "volume_remain": .int(order.volumeRemain), "range": .string(order.range), "duration": .int(order.duration),
            "issued": timestamp(recordedAt, hours: -order.issuedHoursAgo),
        ]
        if order.isBuyOrder {
            object["min_volume"] = .int(order.minVolume ?? 1)
            object["escrow"] = .double(order.price * Double(order.volumeRemain))
        }
        if let state = order.state { object["state"] = .string(state) }
        return .object(object)
    }

    static func json(job: DemoConfig.IndustryJob, recordedAt: Date) -> DemoJSON {
        var object: [String: DemoJSON] = [
            "job_id": .int(job.jobID), "activity_id": .int(job.activityID), "status": .string(job.status),
            "blueprint_id": .int(job.blueprintID), "blueprint_type_id": .int(job.blueprintTypeID),
            "blueprint_location_id": .int(job.stationID), "output_location_id": .int(job.stationID),
            "facility_id": .int(job.stationID), "station_id": .int(job.stationID),
            "installer_id": .int(DemoIDs.characterID), "runs": .int(job.runs),
            "duration": .int(Int64((job.durationHours * 3600).rounded())),
            "start_date": timestamp(recordedAt, hours: -job.startedHoursAgo),
            "end_date": timestamp(recordedAt, hours: job.durationHours - job.startedHoursAgo),
        ]
        if let product = job.productTypeID { object["product_type_id"] = .int(product) }
        if let runs = job.licensedRuns { object["licensed_runs"] = .int(runs) }
        if let cost = job.cost { object["cost"] = .double(cost) }
        if job.status == "delivered" {
            object["completed_character_id"] = .int(DemoIDs.characterID)
            object["completed_date"] = object["end_date"]
            object["successful_runs"] = .int(job.runs)
        }
        return .object(object)
    }

    static func json(contract: DemoConfig.Contract, recordedAt: Date) -> DemoJSON {
        var object: [String: DemoJSON] = [
            "contract_id": .int(contract.contractID), "type": .string(contract.type), "status": .string(contract.status),
            "issuer_id": .int(contract.issuerID), "issuer_corporation_id": .int(contract.issuerCorporationID),
            "assignee_id": .int(contract.assigneeID), "acceptor_id": .int(contract.acceptorID ?? 0),
            "availability": .string(contract.availability), "for_corporation": .bool(false),
            "title": .string(contract.title), "volume": .double(contract.volume),
            "start_location_id": .int(contract.startLocationID), "end_location_id": .int(contract.endLocationID),
            "date_issued": timestamp(recordedAt, hours: -contract.issuedHoursAgo),
            "date_expired": timestamp(recordedAt, hours: contract.expiresInHours),
        ]
        if let price = contract.price { object["price"] = .double(price) }
        if let reward = contract.reward { object["reward"] = .double(reward) }
        if let collateral = contract.collateral { object["collateral"] = .double(collateral) }
        if let days = contract.daysToComplete { object["days_to_complete"] = .int(days) }
        return .object(object)
    }

    static func json(item: DemoConfig.ContractItem, recordID: Int64) -> DemoJSON {
        .object([
            "record_id": .int(recordID), "type_id": .int(item.typeID), "quantity": .int(item.quantity),
            "is_included": .bool(item.isIncluded), "is_singleton": .bool(item.isSingleton ?? false),
        ])
    }

    /// Ids the config makes up must be synthetic, so that nothing real gets a fake payload.
    func validateSyntheticIDs() throws {
        var ids: [Int64] = []
        ids += config.orders.open.map(\.orderID) + config.orders.history.map(\.orderID)
        ids += config.industryJobs.flatMap { [$0.jobID, $0.blueprintID] }
        ids += config.contracts.map(\.contractID)
        ids += config.names.filter { $0.category == "character" || $0.category == "corporation" }.map(\.id)
        if let id = ids.first(where: { !DemoIDs.contains($0) }) {
            throw DemoExportError.notSynthetic(id)
        }
    }

    // MARK: - Player-authored strings

    /// Keeps the first fitting per configured ship that no drop pattern matches, under the
    /// configured name, without a description.
    func cleanFittings(_ body: DemoJSON) -> DemoJSON {
        let patterns = config.fittings.dropPatterns.compactMap {
            try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
        }
        var seen = Set<Int64>()
        var kept: [DemoJSON] = []
        for fitting in body.array ?? [] {
            guard kept.count < config.fittings.maxCount, let ship = fitting["ship_type_id"]?.int,
                  let name = config.fittings.names[String(ship)], !seen.contains(ship) else { continue }
            let original = fitting["name"]?.string ?? ""
            let range = NSRange(original.startIndex..., in: original)
            guard !patterns.contains(where: { $0.firstMatch(in: original, range: range) != nil }) else { continue }
            seen.insert(ship)
            var fitting = fitting
            fitting["name"] = .string(name)
            fitting["description"] = .string("")
            kept.append(fitting)
        }
        return .array(kept)
    }

    /// Only names the game gives by default, `<pilot>'s <type>`, normalised to that form; any
    /// other name the player typed is dropped, so the app shows the type name.
    func cleanAssetNames(_ names: [String: String]) -> [String: String] {
        let pilot = config.pilot.name
        return names.compactMapValues { name in
            for prefix in ["\(pilot)'s ", "\(pilot)s "] where name.hasPrefix(prefix) && name.count > prefix.count {
                return "\(pilot)'s " + name.dropFirst(prefix.count)
            }
            return nil
        }
    }

    // MARK: - Names

    /// Keeps the names, and the asset names, of ids that some entry still mentions, in a path or
    /// anywhere in a body.
    static func prune(_ archive: inout DemoArchive) {
        var referenced: Set<Int64> = [archive.pilot.id, archive.pilot.corporationID]
        func collect(_ json: DemoJSON) {
            switch json {
            case let .int(value): referenced.insert(value)
            case let .array(values): values.forEach(collect)
            case let .object(object): object.values.forEach(collect)
            default: break
            }
        }
        for entry in archive.entries {
            referenced.formUnion(ids(inPath: entry.path))
            entry.body.map(collect)
        }
        archive.names = archive.names.filter { key, _ in Int64(key).map(referenced.contains) ?? false }
        archive.assetNames = archive.assetNames.filter { key, _ in Int64(key).map(referenced.contains) ?? false }
    }
}
