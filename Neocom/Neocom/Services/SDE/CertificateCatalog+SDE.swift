import LiteRow
import SDEKit
import TrainingKit

extension CertificateCatalog {
    /// Reads the certificates and their per-grade skill requirements from the open database.
    /// Names are not loaded.
    init(loading database: SDEDatabase) async throws {
        let certificateQuery = CertificateInfo.all().query()
        let skillQuery = CertificateSkill.all().query()

        let certificates = try await database.database.read { reader in
            let certificateRows = try reader.fetchAll(certificateQuery)
            let skillRows = try reader.fetchAll(skillQuery)

            var skills: [CertificateID: [Certificate.SkillLevels]] = [:]
            for row in skillRows {
                // The five grade columns become an array indexed by `CertificateTier`; the order
                // defines the index.
                skills[row.certificateID, default: []].append(
                    Certificate.SkillLevels(
                        skillID: row.skillID,
                        levels: [row.basic, row.standard, row.improved, row.advanced, row.elite]
                    )
                )
            }

            var certificates: [CertificateID: Certificate] = [:]
            certificates.reserveCapacity(certificateRows.count)
            for row in certificateRows {
                certificates[row.id] = Certificate(id: row.id,
                                                   groupID: row.groupID,
                                                   skills: skills[row.id] ?? [])
            }
            return certificates
        }

        self.init(certificates: certificates)
    }
}
