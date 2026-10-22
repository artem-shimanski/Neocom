import LiteRow
import SDEKit

/// A certificate as the list shows it, with the skill group it is filed under.
@Projection
struct CertificateListRow: Sendable, Identifiable {
    var id: CertificateID
    var name: String
    var groupID: GroupID
    var groupName: String
    /// Position of the group's name in the language's alphabet; orders the sections.
    var groupOrdinal: UInt32
    /// Position of the certificate's name; orders the rows within a section.
    var ordinal: UInt32
}

/// Everything the certificate screen shows above its grades.
@Projection
struct CertificateSummary: Sendable, Identifiable {
    var id: CertificateID
    var name: String
    /// Raw SDE markup, converted by `EVEMarkup`.
    var descriptionText: String?
    var groupID: GroupID
    var groupName: String
}

/// One row of a ship's mastery table: a certificate at a mastery level, with its name.
@Projection
struct TypeMasteryRow: Sendable {
    var level: Int
    var certificateID: CertificateID
    var name: String
}

/// Queries behind the Certificates section and the mastery section of the type screen.
///
/// Built outside the views because `@LiteQuery` treats the query as the identity of a fetch, so it
/// has to be an argument of the view.
enum CertificateBrowser {

    /// Every certificate, ordered by group and then by name. Grouped in Swift: the sections are
    /// always expanded, where `LiteSections` does not pay off.
    static func certificates() -> SQLQuery<CertificateListRow> {
        let withName = CertificateInfo.all()
            .join(NameRow.self) { certificate, name in certificate.nameID == name.id }
        let withGroup = withName
            .join(GroupInfo.self) { certificate, _, group in certificate.groupID == group.id }
        let withGroupName = withGroup
            .join(NameRow.self) { _, _, group, groupName in group.nameID == groupName.id }
        return withGroupName
            .select { certificate, name, group, groupName in
                CertificateListRow.projection(
                    id: certificate.id,
                    name: name.text,
                    groupID: group.id,
                    groupName: groupName.text,
                    groupOrdinal: groupName.ordinal,
                    ordinal: name.ordinal
                )
            }
            .order(by: { _, _, _, groupName in groupName.ordinal })
            .order(by: { _, name, _, _ in name.ordinal })
            .query()
    }

    static func summary(of certificate: CertificateID) -> SQLQuery<CertificateSummary> {
        let withName = CertificateInfo.all()
            .join(NameRow.self) { row, name in row.nameID == name.id }
        let withDescription = withName
            .leftJoin(DescriptionRow.self) { row, _, text in row.descriptionID == text.id }
        let withGroup = withDescription
            .join(GroupInfo.self) { row, _, _, group in row.groupID == group.id }
        let withGroupName = withGroup
            .join(NameRow.self) { _, _, _, group, groupName in group.nameID == groupName.id }
        return withGroupName
            .filter { row, _, _, _, _ in row.id == certificate }
            .select { row, name, text, group, groupName in
                CertificateSummary.projection(
                    id: row.id,
                    name: name.text,
                    descriptionText: text.text,
                    groupID: group.id,
                    groupName: groupName.text
                )
            }
            .limit(1)
            .query()
    }

    /// Names of the skills one certificate requires, alphabetically. Levels come from
    /// `CertificateCatalog`.
    static func skills(ofCertificate certificate: CertificateID) -> SQLQuery<TypeNameRow> {
        let withType = CertificateSkill.all()
            .join(TypeInfo.self) { row, type in row.skillID == type.id }
        let withName = withType
            .join(NameRow.self) { _, type, name in type.nameID == name.id }
        return withName
            .filter { row, _, _ in row.certificateID == certificate }
            .select { _, type, name in
                TypeNameRow.projection(id: type.id, name: name.text)
            }
            .order(by: { _, _, name in name.ordinal })
            .query()
    }

    /// The ships a certificate is recommended for.
    static func ships(recommendedBy certificate: CertificateID) -> SQLQuery<TypeReference> {
        let withType = CertificateRecommendation.all()
            .join(TypeInfo.self) { row, type in row.typeID == type.id }
        let withName = withType
            .join(NameRow.self) { _, type, name in type.nameID == name.id }
        return withName
            .filter { row, _, _ in row.certificateID == certificate }
            .select { _, type, name in
                TypeReference.projection(id: type.id, name: name.text)
            }
            .order(by: { _, _, name in name.ordinal })
            .query()
    }

    /// A ship's whole mastery table: five levels with the certificates of each.
    ///
    /// The sets are nested (every certificate of level `N` is also in `N + 1`), so level 4 holds the
    /// ship's full certificate list.
    static func masteries(of type: TypeID) -> SQLQuery<TypeMasteryRow> {
        let withCertificate = TypeMastery.all()
            .join(CertificateInfo.self) { row, certificate in
                row.certificateID == certificate.id
            }
        let withName = withCertificate
            .join(NameRow.self) { _, certificate, name in certificate.nameID == name.id }
        return withName
            .filter { row, _, _ in row.typeID == type }
            .select { row, certificate, name in
                TypeMasteryRow.projection(
                    level: row.level,
                    certificateID: certificate.id,
                    name: name.text
                )
            }
            .order(by: { row, _, _ in row.level })
            .order(by: { _, _, name in name.ordinal })
            .query()
    }
}
