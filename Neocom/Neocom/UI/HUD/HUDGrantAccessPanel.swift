import SwiftUI

/// The empty state of a section whose ESI route needs a scope the account was not granted:
/// what is missing and a `Grant Access` button that runs EVE SSO again.
///
/// Shown when a sheet's `isMissingScope` is true. Re-authorizing replaces the account's sheets
/// (`AccountStore.signInGeneration` moves), so the screen behind restarts with the new token.
struct HUDGrantAccessPanel: View {
    let title: Text
    let message: Text

    @Environment(AccountStore.self) private var accounts
    @State private var isSigningIn = false
    @State private var error: (any Error)?

    init(title: Text, message: Text) {
        self.title = title
        self.message = message
    }

    var body: some View {
        HUDEmptyPanel(title: title, message: message) {
            Button(action: signIn) {
                Label("Grant Access", systemImage: "lock")
            }
            .hudProminentButton()
            .disabled(isSigningIn)
        }
        .alert("Sign-In Failed", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error?.localizedDescription ?? "")
        }
    }

    private func signIn() {
        isSigningIn = true
        Task {
            defer { isSigningIn = false }
            do {
                try await accounts.signIn()
            } catch SSOError.cancelled {
                // The sign-in sheet was dismissed.
            } catch {
                self.error = error
            }
        }
    }
}

#Preview("Grant access") {
    HUDList {
        Section {
            HUDGrantAccessPanel(title: Text("No Market Access"),
                                message: Text("Your own orders need one more permission. Sign in to EVE again and allow Neocom to read your market orders."))
                .hudBareRow()
        }
    }
    .environment(AccountStore())
}
