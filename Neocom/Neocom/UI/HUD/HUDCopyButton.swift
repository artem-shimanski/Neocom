import SDEKit
import SwiftUI
import UIKit

/// A context-menu item that puts text on the general pasteboard, so every "Copy …" item reads
/// and behaves the same.
struct HUDCopyButton: View {
    let title: LocalizedStringKey
    let value: String
    var systemImage = "doc.on.doc"

    init(_ title: LocalizedStringKey, value: String, systemImage: String = "doc.on.doc") {
        self.title = title
        self.value = value
        self.systemImage = systemImage
    }

    /// "Copy Price" for an ISK amount, copied as a plain number with two decimals and no grouping.
    init(price: Double, title: LocalizedStringKey = "Copy Price") {
        self.init(title, value: Self.plainPrice(price), systemImage: "dollarsign.circle")
    }

    var body: some View {
        Button {
            UIPasteboard.general.string = value
        } label: {
            Label(title, systemImage: systemImage)
        }
        .disabled(value.isEmpty)
    }

    static func plainPrice(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }
}

/// "Copy Name" and "Copy Type ID" for an item.
struct HUDTypeCopyButtons: View {
    let typeID: TypeID
    let name: String

    init(typeID: TypeID, name: String) {
        self.typeID = typeID
        self.name = name
    }

    /// For an ESI type id, which arrives as a plain integer.
    init(typeID: some BinaryInteger, name: String) {
        self.init(typeID: TypeID(rawValue: UInt32(clamping: typeID)), name: name)
    }

    var body: some View {
        if !name.isEmpty {
            HUDCopyButton("Copy Name", value: name)
        }
        HUDCopyButton("Copy Type ID", value: String(typeID.rawValue), systemImage: "number")
    }
}

extension View {
    /// A context menu with only the type's copy items. A row with a richer menu puts
    /// `HUDTypeCopyButtons` into it instead; nested context menus do not merge.
    func hudTypeContextMenu(typeID: TypeID, name: String) -> some View {
        contextMenu {
            HUDTypeCopyButtons(typeID: typeID, name: name)
        }
    }

    /// Same, for an ESI type id.
    func hudTypeContextMenu(typeID: some BinaryInteger, name: String) -> some View {
        hudTypeContextMenu(typeID: TypeID(rawValue: UInt32(clamping: typeID)), name: name)
    }
}
