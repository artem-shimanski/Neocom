import Observation
import SwiftUI

/// Runs EVE SSO again for the current account and keeps what a sign-in control needs: whether
/// one is in flight and its failure. Shared by every `Grant Access` and `Sign In` control.
@Observable
@MainActor
final class GrantAccessAction {
    private(set) var isSigningIn = false
    var error: (any Error)?

    func signIn(_ accounts: AccountStore) {
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

extension View {
    /// Shows the failure of `action`.
    func signInFailureAlert(_ action: GrantAccessAction) -> some View {
        alert("Sign-In Failed", isPresented: Binding(get: { action.error != nil }, set: { if !$0 { action.error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(action.error?.localizedDescription ?? "")
        }
    }
}
