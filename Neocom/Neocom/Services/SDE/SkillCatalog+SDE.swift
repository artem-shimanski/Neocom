import LiteRow
import SDEKit
import TrainingKit

extension SkillCatalog {
    /// Reads every skill, its prerequisite skills and the attribute bonuses of each implant from
    /// the open database.
    ///
    /// The three queries share one `read` (one connection, one hop off the main actor) and are
    /// folded inside it, since the rows are not `Sendable`.
    init(loading database: SDEDatabase) async throws {
        // `dogmaSkills` holds only skills.
        let skillQuery = DogmaSkill.all().query()

        // Prerequisites only: `dogmaItemSkills` covers every item, and joining `dogmaSkills` on
        // the item side keeps the rows where the item is itself a skill. `select` narrows the
        // output back to the requirement row.
        let withSkill = DogmaItemSkill.all()
            .join(DogmaSkill.self) { requirement, skill in requirement.itemID == skill.id }
        let prerequisiteQuery = withSkill
            .select { requirement, _ in requirement }
            .query()

        // One row per (implant, attribute) pair, non-zero bonuses only.
        let implantQuery = DogmaImplantAttribute.all().query()

        let (skills, implantBonuses) = try await database.database.read { reader in
            let skillRows = try reader.fetchAll(skillQuery)
            let prerequisiteRows = try reader.fetchAll(prerequisiteQuery)
            let implantRows = try reader.fetchAll(implantQuery)

            var prerequisites: [TypeID: [Requirement]] = [:]
            prerequisites.reserveCapacity(skillRows.count)
            for row in prerequisiteRows {
                prerequisites[row.itemID, default: []]
                    .append(Requirement(skillID: row.skillID, level: row.level))
            }

            var skills: [TypeID: Skill] = [:]
            skills.reserveCapacity(skillRows.count)
            for row in skillRows {
                skills[row.id] = Skill(
                    rank: row.rank,
                    primaryAttribute: row.primaryAttribute,
                    secondaryAttribute: row.secondaryAttribute,
                    prerequisites: prerequisites[row.id] ?? []
                )
            }

            // Accumulated, not assigned: category 20 includes boosters, which can raise up to five
            // attributes at once.
            var implantBonuses: [TypeID: CharacterAttributes] = [:]
            for row in implantRows {
                implantBonuses[row.implantID, default: .zero][row.attribute] += row.bonus
            }

            return (skills, implantBonuses)
        }

        self.init(skills: skills, implantBonuses: implantBonuses)
    }
}
