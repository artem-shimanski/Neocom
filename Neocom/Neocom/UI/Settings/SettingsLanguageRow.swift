import SwiftUI

/// Settings › Data › Database Language: the language of the static data's names and descriptions,
/// by its own name, leading to the picker (`DatabaseLanguageView`).
struct SettingsLanguageRow: View {
    @Environment(SDEStore.self) private var sde

    var body: some View {
        NavigationLink {
            DatabaseLanguageView()
        } label: {
            HUDLinkRowLabel(systemImage: "globe", title: Text("Database Language"),
                            subtitle: Text("Item names and descriptions"),
                            value: Text(verbatim: sde.language.nativeName))
        }
        .hudRowButton()
    }
}
