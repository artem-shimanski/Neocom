import SwiftUI

extension View {
    /// The alert for a command the engine refused, bound to the model's `errorMessage`.
    ///
    /// Attached on every screen that can issue a command: an alert is held back while another
    /// screen covers the view it hangs on. Dismissing it clears the message for every screen.
    func fitCommandAlert(_ model: FittingEditorModel?) -> some View {
        alert(
            "Could Not Update Fit",
            isPresented: Binding(
                get: { model?.errorMessage != nil },
                set: { isPresented in if !isPresented { model?.errorMessage = nil } }
            ),
            presenting: model?.errorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }
}
