import SwiftUI

extension View {
    /// The one main action on a screen: the system's glass prominent button tinted
    /// `accent-fill`.
    func hudProminentButton() -> some View {
        self
            .buttonStyle(.glassProminent)
            .tint(Color.hudAccentFill)
            // The content layer sets `ink` for everything under it; the label on the fill is
            // white in both themes.
            .foregroundStyle(Color.hudOnAccentFill)
            .controlSize(.large)
    }
}

#Preview("Prominent button") {
    VStack(spacing: 12) {
        Button("Save Fit") {}
            .hudProminentButton()
    }
    .padding(32)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .hudScreen()
}
