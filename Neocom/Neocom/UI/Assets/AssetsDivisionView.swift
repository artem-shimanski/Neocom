import AssetsKit
import SwiftUI

/// One hangar division of a corporation's offices at a location: its ships, containers and items.
struct AssetsDivisionView: View {
    let model: AssetsModel
    let locationID: Int64
    let number: Int

    var body: some View {
        AssetsIndexContent(model: model) { index in
            let sections = index.contents(ofDivision: number, at: locationID)
            if sections.isEmpty {
                AssetsGoneList()
            } else {
                HUDList {
                    AssetsSections(sections: sections)
                    Section {
                        HUDFootnote("Stacks of the same item are added together. Tap a ship or a container to see what is inside; tap an item for its info.")
                            .hudBareRow()
                    }
                }
            }
        }
        .assetsRefresh(model)
        .navigationTitle(model.divisionName(number))
        .navigationBarTitleDisplayMode(.inline)
    }
}
