import DogmaKit
import SwiftUI

/// "Upload to EVE" flow shared by My Fits and the editor: lays the document out, builds the
/// upload, asks about anything the game will not keep, then sends it and links `esiFittingID`
/// once the game has answered.
///
/// The `POST` goes through `FittingsSheet.create`. Held by the screen as `@State`, paired with
/// `fitUploadFlow(_:)`, which presents the losses sheet and the error alert.
@Observable
final class FitUploader {
    /// Fits with an upload in flight; a second upload of the same fit is refused.
    private(set) var uploadingFitIDs: Set<UUID> = []
    var error: (any Error)?
    /// Set when `ESIUpload` found something the game will not keep; presented as a sheet.
    var pending: PendingUpload?

    func isUploading(_ fitID: UUID) -> Bool {
        uploadingFitIDs.contains(fitID)
    }

    /// Starts the upload of `fitID`. `document` is the fit as it is to be sent.
    ///
    /// The name and notes are read from the stored record, so a draft must be persisted by the
    /// caller first. `fitID` joins `uploadingFitIDs` synchronously and leaves it when the flow ends,
    /// the losses sheet included.
    func upload(_ fitID: UUID,
                fittings: FittingStore,
                accounts: AccountStore,
                document: @escaping () async -> FitDocument?) {
        guard !uploadingFitIDs.contains(fitID) else { return }
        uploadingFitIDs.insert(fitID)

        Task {
            guard let document = await document(), let fit = fittings.summary(of: fitID) else {
                error = UploadFlowError.unreadable
                uploadingFitIDs.remove(fitID)
                return
            }
            do {
                let layout = try await FittingEngine().layout(of: document)
                let upload = try ESIUpload(document: document, name: fit.name, notes: fit.notes, layout: layout)
                if upload.losses.isEmpty {
                    await send(fit: fit, upload: upload, fittings: fittings, accounts: accounts)
                } else {
                    // Stays in `uploadingFitIDs` until `send` or the sheet's cancel clears it.
                    pending = PendingUpload(fit: fit, upload: upload)
                }
            } catch {
                self.error = error
                uploadingFitIDs.remove(fitID)
            }
        }
    }

    fileprivate func confirm(_ pending: PendingUpload, fittings: FittingStore, accounts: AccountStore) {
        self.pending = nil
        Task { await send(fit: pending.fit, upload: pending.upload, fittings: fittings, accounts: accounts) }
    }

    fileprivate func cancel(_ pending: PendingUpload) {
        uploadingFitIDs.remove(pending.fit.id)
        self.pending = nil
    }

    /// The `POST` plus the link that makes the "in game" badge appear; shared by the direct path
    /// and the losses sheet's "Upload".
    private func send(fit: FittingSummary, upload: ESIUpload, fittings: FittingStore, accounts: AccountStore) async {
        defer { uploadingFitIDs.remove(fit.id) }
        // Menus offer the item only with a character signed in; the error keeps a failure visible.
        guard let sheet = accounts.currentFittings else {
            error = UploadFlowError.noCharacter
            return
        }
        do {
            let newID = try await sheet.create(name: upload.name,
                                               description: upload.description,
                                               shipTypeID: upload.shipTypeID,
                                               items: upload.items)
            fittings.link(fit.id, esiFittingID: newID, characterID: sheet.characterID)
        } catch {
            self.error = error
        }
    }
}

extension View {
    /// The parts of `uploader`'s flow the player sees: the losses sheet and the error alert.
    func fitUploadFlow(_ uploader: FitUploader) -> some View {
        modifier(FitUploadFlow(uploader: uploader))
    }
}

private struct FitUploadFlow: ViewModifier {
    @Bindable var uploader: FitUploader

    @Environment(FittingStore.self) private var fittings
    @Environment(AccountStore.self) private var accounts

    func body(content: Content) -> some View {
        content
            .alert(
                "Upload Failed",
                isPresented: Binding(
                    get: { uploader.error != nil },
                    set: { isPresented in if !isPresented { uploader.error = nil } }
                ),
                presenting: uploader.error
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error.localizedDescription)
            }
            .sheet(item: $uploader.pending) { pending in
                UploadLossesView(fitName: pending.fit.name, losses: pending.upload.losses) {
                    uploader.confirm(pending, fittings: fittings, accounts: accounts)
                } onCancel: {
                    uploader.cancel(pending)
                }
                // Dismissing by swipe would skip `onUpload` and `onCancel`, which clear `uploadingFitIDs`.
                .interactiveDismissDisabled()
            }
    }
}

/// An upload waiting on the player's answer about what it would lose, with its fit.
struct PendingUpload: Identifiable {
    var id: UUID { fit.id }
    var fit: FittingSummary
    var upload: ESIUpload
}

/// Why the upload flow stopped before it could even build an `ESIUpload`.
nonisolated enum UploadFlowError: LocalizedError {
    case unreadable
    case noCharacter

    var errorDescription: String? {
        switch self {
        case .unreadable:
            String(localized: "This fit cannot be read.")
        case .noCharacter:
            String(localized: "Sign in with EVE Online to upload a fit.")
        }
    }
}

/// Confirmation sheet listing everything `ESIUpload` found that the game will not keep.
private struct UploadLossesView: View {
    let fitName: String
    let losses: [String]
    let onUpload: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            HUDList {
                HUDListSection(losses, id: \.self, row: { loss in
                    Text(loss)
                        .font(.hudBody)
                        .hudRow(HUDRowStyle(border: HUDTone.warn.border, minHeight: 44))
                }, header: {
                    HUDSectionHeader(Text("EVE will not keep the following"))
                })
            }
            .navigationTitle(fitName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel, action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Upload", action: onUpload)
                }
            }
        }
    }
}
