import DogmaKit
import SwiftUI

/// The round 32 pt control at the leading edge of a module row and of a drone row: a glyph on a
/// disc whose look shows the state.
///
/// Shared by both rows: a module's state, or for a drone "in space" (`active`) or "in the bay"
/// (`offline`). The control only draws; what a tap does is the caller's.
struct FitStateControl: View {
    let state: Entity.Module.State
    /// What the glyph is, for VoiceOver.
    let label: Text
    /// What a tap does.
    let hint: Text
    var value: Text?
    let action: () -> Void

    @ViewBuilder
    var body: some View {
        let look = Self.look(of: state)
        let button = Button(action: action) {
            Image(systemName: Self.symbolName(for: state))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(look.ink)
                .frame(width: FitStateColumn.width, height: FitStateColumn.width)
                .background(look.fill, in: Circle())
                .overlay(Circle().strokeBorder(look.line, lineWidth: 1))
                // Drawn 32 pt, with the touch target grown to 44 pt behind it (6 pt on every side).
                .contentShape(Circle().inset(by: -6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
        // A drone says "on" or "off" besides its name; a module's label already carries its state.
        if let value {
            button.accessibilityValue(value)
        } else {
            button
        }
    }

    /// The four looks of the control: fill, border and ink. Offline is an empty ring, online a pale
    /// wash, active the accent, overheat the warning orange.
    ///
    /// The inks and the offline border are tokens; the washes and the active/overheat borders are a
    /// token at a fixed opacity over the panel, so they follow the colour scheme.
    struct Look {
        let fill: Color
        let line: Color
        let ink: Color
    }

    static func look(of state: Entity.Module.State) -> Look {
        switch state {
        case .offline: Look(fill: .clear, line: .hudLineLeader, ink: .hudInkFaint)
        case .online: Look(fill: Color.hudInk.opacity(0.08), line: Color.hudInk.opacity(0.16), ink: .hudInk)
        case .active: Look(fill: Color.hudAccent.opacity(0.14), line: Color.hudAccent.opacity(0.27), ink: .hudAccent)
        case .overloaded: Look(fill: Color.hudWarn.opacity(0.16), line: Color.hudWarn.opacity(0.30), ink: .hudWarn)
        }
    }

    /// One symbol for offline and online; the background tells them apart.
    static func symbolName(for state: Entity.Module.State) -> String {
        switch state {
        case .offline, .online: "power"
        case .active: "bolt.fill"
        case .overloaded: "flame.fill"
        }
    }
}
