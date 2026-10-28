import SwiftUI

/// The compact form of `HUDGrantAccessPanel`: one line and a small `Sign In` button, for a
/// group of the home screen that is only missing a permission.
struct HUDGrantAccessRow: View {
    let message: Text

    @Environment(AccountStore.self) private var accounts
    @State private var action = GrantAccessAction()

    var body: some View {
        HUDPanel {
            HStack(spacing: 10) {
                Image(systemName: "lock")
                    .font(.hudBody)
                    .foregroundStyle(Color.hudAccent)
                message
                    .font(.hudCaption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Glass styles only: a default-styled button in a List row fires on any tap in it.
                Button("Sign In") { action.signIn(accounts) }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .disabled(action.isSigningIn)
            }
            .padding(.horizontal, HUDMetrics.gutter)
            .padding(.vertical, 10)
        }
        .signInFailureAlert(action)
    }
}

#Preview("Grant access row") {
    HUDList {
        Section {
            HUDGrantAccessRow(message: Text("Sign in again to see your corporation's data"))
                .hudBareRow()
        }
    }
    .environment(AccountStore())
}
