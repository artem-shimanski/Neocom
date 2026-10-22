import SwiftUI

/// Character picker: select the active character, add a new one via EVE SSO, or remove one.
struct AccountsView: View {
    @Environment(AccountStore.self) private var accounts
    @Environment(\.dismiss) private var dismiss

    @State private var isSigningIn = false
    @State private var error: Error?
    @State private var pendingRemoval: Account?
    @State private var isConfirmingDemoExit = false

    var body: some View {
        NavigationStack {
            HUDList {
                if accounts.pickerAccounts.isEmpty {
                    Section {
                        HUDEmptyPanel(title: Text("No Characters"),
                                      message: DemoPilot.isAvailable
                                          ? Text("Sign in with EVE Online to see your characters here, or look around with a demo pilot.")
                                          : Text("Sign in with EVE Online to see your characters here."))
                            .hudBareRow()
                    }
                } else {
                    HUDListSection {
                        ForEach(accounts.accounts) { account in
                            HUDSwipeRow(onRemove: { pendingRemoval = account }, inContextMenu: false) {
                                pilotRow(account)
                            }
                        }
                        if let demo = accounts.demoAccount {
                            pilotRow(demo)
                        }
                    } header: {
                        HUDSectionHeader(Text("Pilots · \(accounts.pickerAccounts.count)"))
                    } footer: {
                        if !accounts.accounts.isEmpty {
                            HUDFootnote("Swipe a pilot left to remove it.")
                        }
                    }
                }

                HUDListSection {
                    Button {
                        signIn()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Add Character")
                                .font(.hudTileTitle)
                        }
                        .foregroundStyle(Color.hudAccent)
                        .hudRow()
                    }
                    .hudRowButton()
                    .disabled(isSigningIn)
                } footer: {
                    HUDFootnote("Opens the EVE Online sign-in page.")
                }

                if accounts.demoAccount != nil {
                    HUDListSection {
                        Button {
                            isConfirmingDemoExit = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("Exit Demo")
                                    .font(.hudTileTitle)
                            }
                            .foregroundStyle(Color.hudDanger)
                            .hudRow()
                        }
                        .hudRowButton()
                    }
                } else if DemoPilot.isAvailable {
                    HUDListSection {
                        Button {
                            Task {
                                await accounts.enterDemo()
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "play.circle")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("Explore with a Demo Pilot")
                                    .font(.hudTileTitle)
                            }
                            .foregroundStyle(Color.hudAccent)
                            .hudRow()
                        }
                        .hudRowButton()
                    } footer: {
                        HUDFootnote("No sign-in needed. Recorded data; nothing in EVE is changed.")
                    }
                }
            }
            .navigationTitle("Characters")
            #if !targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", role: .confirm) { dismiss() }
                }
            }
            .overlay {
                if isSigningIn { ProgressView().controlSize(.large) }
            }
            .confirmationDialog(
                pendingRemoval.map { Text("Remove \($0.characterName)?") } ?? Text("Remove Pilot?"),
                isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
                titleVisibility: .visible,
                presenting: pendingRemoval
            ) { account in
                Button("Remove", role: .destructive) { accounts.remove(account) }
            } message: { _ in
                Text("The pilot will be signed out. You can add it back by signing in again.")
            }
            .confirmationDialog("Exit Demo?", isPresented: $isConfirmingDemoExit, titleVisibility: .visible) {
                Button("Exit Demo", role: .destructive) { accounts.exitDemo() }
            } message: {
                Text("The demo pilot will be removed, with everything changed during the demo.")
            }
            .alert(
                "Sign-in Failed",
                isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } }),
                presenting: error
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error.localizedDescription)
            }
        }
    }

    private func pilotRow(_ account: Account) -> some View {
        Button {
            accounts.currentAccountID = account.id
            dismiss()
        } label: {
            HStack(spacing: 12) {
                HUDImagePlate(url: account.portraitURL, size: 44, radius: 10, framed: true)
                Text(account.characterName)
                    .font(.hudTileTitle)
                if account.isDemo {
                    HUDOutlineTag.demo
                }
                Spacer(minLength: 0)
                if account.id == accounts.currentAccountID {
                    HUDStatusChip(text: Text("Active"), color: .hudAccent, mark: .symbol("checkmark"))
                }
            }
            .hudRow(HUDRowStyle(minHeight: 68, verticalPadding: 12))
        }
        .hudRowButton(HUDRowStyle(minHeight: 68, verticalPadding: 12))
        .contextMenu {
            if account.isDemo {
                Button("Exit Demo", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    isConfirmingDemoExit = true
                }
            } else {
                Button("Remove", systemImage: "trash", role: .destructive) {
                    pendingRemoval = account
                }
            }
        }
    }

    private func signIn() {
        isSigningIn = true
        Task {
            defer { isSigningIn = false }
            do {
                try await accounts.signIn()
                dismiss()
            } catch SSOError.cancelled {
                // Cancelled by the user.
            } catch {
                self.error = error
            }
        }
    }
}

#Preview {
    AccountsView()
        .environment(AccountStore())
}
