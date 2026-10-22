import SwiftUI
import UIKit

/// The warning that iOS does not allow Neocom's notifications: a caps chip, what it means for
/// the screen, and the way to Settings. Shared by Settings and the Planetary Interaction
/// schedule; a list puts it in a section of its own with `hudBareRow()`.
struct HUDNotificationsOffPanel: View {
    /// A sentence under the headline.
    var detail: Text?
    /// The line beside the button.
    let note: Text

    var body: some View {
        HUDPanel(tone: .warn) {
            VStack(alignment: .leading, spacing: 4) {
                HUDStatusChip(text: Self.chip, color: .hudWarn, mark: .symbol("bell.slash.fill"))
                Text("Nothing below will reach you")
                    .font(HUDFont.display(15, weight: .semibold, relativeTo: .body))
                if let detail {
                    detail
                        .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                        .lineSpacing(3)
                        .foregroundStyle(Color.hudInkBodyMuted)
                }
            }
            .padding(.horizontal, HUDMetrics.gutter)
            .padding(.vertical, 12)
            HUDPanelRule()
            HStack(spacing: 12) {
                note
                    .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                    .lineSpacing(3)
                    .foregroundStyle(Color.hudWarnNoteInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Open Settings") {
                    if let url = URL(string: Self.settingsURL) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.glassProminent)
                .tint(Color.hudAccentFill)
                .foregroundStyle(Color.hudOnAccentFill)
            }
            .padding(.horizontal, HUDMetrics.gutter)
            .padding(.vertical, 10)
        }
    }

    #if targetEnvironment(macCatalyst)
    private static let chip = Text("Notifications off in macOS")
    /// On Mac the app's settings page has no notification switches; System Settings' pane does.
    private static let settingsURL = UIApplication.openNotificationSettingsURLString
    #else
    private static let chip = Text("Notifications off in iOS")
    private static let settingsURL = UIApplication.openSettingsURLString
    #endif
}

#Preview("Notifications off") {
    HUDList {
        Section {
            HUDNotificationsOffPanel(note: Text(verbatim: "Your choices are kept and start working once you allow them."))
                .hudBareRow()
        }
        Section {
            HUDNotificationsOffPanel(detail: Text(verbatim: "The schedule is kept and starts working as soon as you allow it."),
                                     note: Text(verbatim: "Allow notifications for Neocom in Settings."))
                .hudBareRow()
        }
    }
}
