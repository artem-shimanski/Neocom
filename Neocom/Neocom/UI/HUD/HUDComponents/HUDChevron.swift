import SwiftUI

/// The chevron at the end of a row that leads somewhere.
struct HUDChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.hudInkFaint)
            .accessibilityHidden(true)
    }
}

/// The ↗ at the end of a row that opens a page outside the app — a site, the App Store — where
/// the chevron would say it leads to a screen of the app. Spoken, since that is worth knowing
/// before the tap.
struct HUDExternalMark: View {
    var body: some View {
        Image(systemName: "arrow.up.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.hudInkFaint)
            .accessibilityLabel(Text("Opens outside Neocom"))
    }
}

#Preview("Chevron") {
    HUDList {
        Section {
            HStack(spacing: 8) {
                Text(verbatim: "Details").font(.hudBody)
                Spacer()
                HUDChevron()
            }
            .hudRow()
        }
    }
}
