import SwiftUI

/// A dashed empty-state panel: what will appear here, why it is not here yet, and the one
/// action that fixes that.
///
/// Two looks. Without a `systemImage` it is the centred block of a whole empty screen. With
/// one it is the compact note for a screen that is not empty but is missing one part — an
/// accent icon, the caption and the sentence left-aligned beside it.
///
/// A third, `init(placeholderSystemImage:)`, is the centred block with a muted symbol on top, a
/// tile-title heading in its own case and a mono caption — the stand-in for a whole part of a
/// screen that is not available yet, such as the groups hidden from the home screen until a
/// pilot signs in.
struct HUDEmptyPanel<Actions: View>: View {
    let title: Text
    let message: Text
    var systemImage: String?
    /// Set by the placeholder variant; wins over `systemImage`.
    var placeholderSystemImage: String?
    @ViewBuilder var actions: Actions

    var body: some View {
        Group {
            if let placeholderSystemImage {
                placeholder(placeholderSystemImage)
            } else if let systemImage {
                note(systemImage)
            } else {
                centered
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: HUDMetrics.panelRadius, style: .continuous)
                .strokeBorder(Color.hudLineLeader, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }

    private var caption: some View {
        title
            .font(HUDFont.mono(13, weight: .regular, relativeTo: .subheadline))
            .tracking(2)
            .textCase(.uppercase)
            .foregroundStyle(Color.hudInkMuted)
    }

    private var centered: some View {
        VStack(spacing: 10) {
            caption
            message
                .font(.hudBody)
                .foregroundStyle(Color.hudInkBodyMuted)
                .frame(maxWidth: 280)
            actions
                .padding(.top, 10)
        }
        .multilineTextAlignment(.center)
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }

    private func placeholder(_ systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 22))
                .foregroundStyle(Color.hudInkFaint)
                .accessibilityHidden(true)
            title
                .font(.hudTileTitle)
                .foregroundStyle(Color.hudInk)
            message
                .font(.hudCaption)
                .lineSpacing(3)
                .foregroundStyle(Color.hudInkMuted)
            actions
                .padding(.top, 4)
        }
        .multilineTextAlignment(.center)
        .padding(.vertical, 22)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }

    private func note(_ systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 20))
                .foregroundStyle(Color.hudAccent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                title
                    .font(.hudLabel)
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hudInkMuted)
                message
                    .font(.hudBody)
                    .lineSpacing(2)
                    .foregroundStyle(Color.hudInkBodyMuted)
                actions
                    .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .multilineTextAlignment(.leading)
        .padding(.vertical, 14)
        .padding(.horizontal, HUDMetrics.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension HUDEmptyPanel where Actions == EmptyView {
    init(title: Text, message: Text) {
        self.title = title
        self.message = message
        self.actions = EmptyView()
    }

    /// The compact note: `systemImage` in `accent` beside the caption and the sentence.
    init(systemImage: String, title: Text, message: Text) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actions = EmptyView()
    }

    /// The placeholder: `placeholderSystemImage` in muted ink above a heading and a caption,
    /// all centred.
    init(placeholderSystemImage: String, title: Text, message: Text) {
        self.title = title
        self.message = message
        self.placeholderSystemImage = placeholderSystemImage
        self.actions = EmptyView()
    }
}

#Preview("Empty panel") {
    HUDList {
        Section {
            HUDEmptyPanel(systemImage: "square.stack.3d.up",
                          title: Text("No Subsystems Yet"),
                          message: Text("A strategic cruiser has no high, medium, low or drone slots until its subsystems are fitted. Fit a core, defensive, offensive and propulsion subsystem."))
                .hudBareRow()
        }
        Section {
            HUDEmptyPanel(title: Text("No Fits"), message: Text("Tap ＋ to create a fit."))
                .hudBareRow()
        }
        Section {
            HUDEmptyPanel(placeholderSystemImage: "lock.open",
                          title: Text("Sign in to unlock the rest of Neocom"),
                          message: Text("Skills and training, assets, mail, planets, market orders, industry and contracts open up as soon as a pilot is on board."))
                .hudBareRow()
        }
    }
}
