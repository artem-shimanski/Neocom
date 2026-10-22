import LiteRow
import SDEKit

/// A skill as the Skills section lists it, with its group.
///
/// Rank and prerequisites come from `SkillCatalog`.
@Projection
struct SkillListRow: Sendable, Identifiable {
    var id: TypeID
    var name: String
    var groupID: GroupID
    var groupName: String
}

enum SkillBrowser {
    /// Every published skill, ordered by group and then by name.
    ///
    /// One flat query for the whole section: the root counts every group, and prerequisites may
    /// come from other groups.
    ///
    /// `dogmaSkills` is joined as the skill filter and is the table `SkillCatalog` is read from.
    static func skills() -> SQLQuery<SkillListRow> {
        let withType = DogmaSkill.all()
            .join(TypeInfo.self) { skill, type in skill.id == type.id }
        let withName = withType
            .join(NameRow.self) { _, type, name in type.nameID == name.id }
        let withGroup = withName
            .join(GroupInfo.self) { _, type, _, group in type.groupID == group.id }
        let withGroupName = withGroup
            .join(NameRow.self) { _, _, _, group, groupName in group.nameID == groupName.id }
        return withGroupName
            .filter { _, type, _, group, _ in type.published == true && group.published == true }
            .select { _, type, name, group, groupName in
                SkillListRow.projection(
                    id: type.id,
                    name: name.text,
                    groupID: group.id,
                    groupName: groupName.text
                )
            }
            .order(by: { _, _, _, _, groupName in groupName.ordinal })
            .order(by: { _, _, name, _, _ in name.ordinal })
            .query()
    }
}
