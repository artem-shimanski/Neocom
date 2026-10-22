import DogmaKit
import Foundation
import LegacyImportKit
import SQLite3
import Testing

/// Mirrors what the old encoder wrote: a flat `modules` array with `Slot(...)` keys.
private let shipJSON = #"""
{
  "typeID": 16229, "name": "Brutix",
  "modules": [
    "Slot(stringValue: \"med\", intValue: 2)", [
      {"typeID": 10850, "id": 7, "state": "unknown", "count": 1, "socket": -1}
    ],
    "Slot(stringValue: \"hi\", intValue: 1)", [
      {"typeID": 3186, "id": 1, "state": "active", "count": 1, "charge": {"typeID": 12791, "count": 80}, "socket": 2},
      {"typeID": 3186, "id": 2, "state": "overloaded", "count": 2, "socket": -1},
      {"typeID": 3186, "id": 3, "state": "offline", "count": 1, "socket": 0}
    ],
    "Slot(stringValue: \"subsystem\", intValue: 5)", [
      {"typeID": 45586, "state": "online", "count": 1, "socket": 3}
    ]
  ],
  "drones": [
    {"typeID": 2488, "id": 1, "isActive": true, "count": 1, "isKamikaze": false, "squadronTag": 0},
    {"typeID": 2488, "id": 2, "isActive": true, "count": 1, "isKamikaze": false, "squadronTag": 0},
    {"typeID": 2488, "id": 3, "isActive": false, "count": 2, "isKamikaze": false, "squadronTag": -1},
    {"typeID": 2488, "id": 4, "isActive": false, "count": 3, "isKamikaze": true, "squadronTag": -1}
  ],
  "cargo": [{"typeID": 27912, "count": 1}],
  "implants": [10228],
  "boosters": [28674]
}
"""#

@Suite struct LegacyShipTests {
    @Test func decodesFlatModules() throws {
        let ship = try JSONDecoder().decode(LegacyShip.self, from: Data(shipJSON.utf8))
        #expect(ship.racks.map(\.slot) == [.med, .hi, .subsystem])
        #expect(ship.racks[1].modules[0].charge?.typeID == 12791)
        #expect(ship.cargo.count == 1)
    }

    @Test func mapsToFitDocument() throws {
        let ship = try JSONDecoder().decode(LegacyShip.self, from: Data(shipJSON.utf8))
        let document = ship.fitDocument(name: "Brutix", skillLevel: 5)
        #expect(document.name == "Brutix")
        let pilot = try #require(document.pilots.first)
        #expect(pilot.skills?.default == 5)
        #expect(pilot.implants == [10228])
        #expect(pilot.boosters == [28674])
        let fit = try #require(pilot.ship)
        #expect(fit.type == 16229)

        // Hi rack first, explicit sockets ascending, the repeated module after them;
        // then med, then the subsystem without its socket.
        let modules = fit.modules
        #expect(modules.map(\.type) == [3186, 3186, 3186, 3186, 10850, 45586])
        #expect(modules.map(\.socket) == [0, 2, nil, nil, nil, nil])
        #expect(modules.map(\.state) == [.offline, .active, .overloaded, .overloaded, nil, .online])
        #expect(modules[1].charge == FitDocument.Item(12791))
        #expect(modules[0].charge == nil)

        // The squadron is one stack; untagged entries stay apart.
        #expect(fit.drones == [
            FitDocument.Drone(type: 2488, count: 2, active: true),
            FitDocument.Drone(type: 2488, count: 2),
            FitDocument.Drone(type: 2488, count: 3, kamikaze: true),
        ])
    }

    @Test func acceptsObjectModulesAndPlainKeys() throws {
        let json = #"{"typeID": 587, "modules": {"low": [{"typeID": 2048, "state": "online", "socket": 1}], "4": [{"typeID": 31790}]}}"#
        let ship = try JSONDecoder().decode(LegacyShip.self, from: Data(json.utf8))
        let modules = try #require(ship.fitDocument(name: nil, skillLevel: 0).pilots.first?.ship?.modules)
        #expect(modules.map(\.type) == [2048, 31790])
        #expect(modules.map(\.socket) == [1, nil])
        #expect(ship.drones.isEmpty && ship.implants.isEmpty)
    }

    @Test func minimalShip() throws {
        let ship = try JSONDecoder().decode(LegacyShip.self, from: Data(#"{"typeID": 587}"#.utf8))
        let document = ship.fitDocument(name: "", skillLevel: 5)
        #expect(document.pilots.first?.ship?.modules.isEmpty == true)
    }
}

@Suite struct LegacyFitStoreTests {
    @Test func missingFileIsNothing() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).sqlite")
        #expect(try LegacyFitStore.read(at: url) == nil)
    }

    @Test func readsLoadoutsAndSkipsBrokenOnes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("cloud.sqlite")

        let good = UUID(), unnamed = UUID(), broken = UUID()
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        let sql = """
            PRAGMA journal_mode = WAL;
            CREATE TABLE ZLOADOUT (Z_PK INTEGER PRIMARY KEY, ZTYPEID INTEGER, ZDATA INTEGER, ZNAME VARCHAR, ZTAG VARCHAR, ZUUID VARCHAR);
            CREATE TABLE ZLOADOUTDATA (Z_PK INTEGER PRIMARY KEY, ZLOADOUT INTEGER, ZDATA BLOB);
            INSERT INTO ZLOADOUTDATA VALUES (1, 1, CAST('\(shipJSON.replacingOccurrences(of: "'", with: "''"))' AS BLOB));
            INSERT INTO ZLOADOUTDATA VALUES (2, 2, CAST('{"typeID": 587, "name": "From JSON"}' AS BLOB));
            INSERT INTO ZLOADOUTDATA VALUES (3, 3, CAST('{"modules": 1' AS BLOB));
            INSERT INTO ZLOADOUTDATA VALUES (4, NULL, CAST('{"typeID": 1}' AS BLOB));
            INSERT INTO ZLOADOUT VALUES (1, 16229, 1, 'My Brutix', NULL, '\(good.uuidString)');
            INSERT INTO ZLOADOUT VALUES (2, 587, 2, '', NULL, '\(unnamed.uuidString)');
            INSERT INTO ZLOADOUT VALUES (3, 587, 3, 'Broken', NULL, '\(broken.uuidString)');
            INSERT INTO ZLOADOUT VALUES (4, 587, NULL, 'No data', NULL, '\(UUID().uuidString)');
            """
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        // Left open, so the rows are still in the WAL when the copy is made.
        defer { sqlite3_close(db) }

        let contents = try #require(try LegacyFitStore.read(at: url))
        #expect(contents.fits.map(\.uuid) == [good, unnamed])
        #expect(contents.fits.map(\.name) == ["My Brutix", "From JSON"])
        #expect(contents.failures.count == 2)
    }
}
