import MailKit
import SwiftUI

/// `New Label…`: a name of at most 40 characters and one of EVE's 18 colours. A system sheet
/// with a system title, Cancel and Create; the fields are the content layer's sheet cards.
struct MailNewLabelSheet: View {
    let sheet: MailSheet

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color = MailLabelColor.default
    @State private var isSaving = false
    @State private var error: (any Error)?
    @FocusState private var isNameFocused: Bool

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            HUDList(isTransparent: true) {
                HUDListSection {
                    TextField("Label name", text: $name)
                        .font(.hudSheetBody)
                        .focused($isNameFocused)
                        .submitLabel(.done)
                        .onSubmit(create)
                        .hudRow(.sheet)
                } header: {
                    HUDSectionHeader(Text("Name")) {
                        Text(verbatim: "\(name.count)/\(MailLabel.maxNameLength)")
                    }
                }

                HUDListSection {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 12) {
                        ForEach(MailLabelColor.all, id: \.self) { hex in
                            swatch(hex)
                        }
                    }
                    .padding(.vertical, 14)
                    .hudRow(.sheet)
                } header: {
                    HUDSectionHeader(Text("Colour"))
                } footer: {
                    HUDFootnote("EVE offers these 18 colours for a label. The label’s mail keeps it until you remove it.")
                }
            }
            .navigationTitle("New Label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Create", action: create)
                            .disabled(trimmedName.isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(isSaving)
        .onAppear { isNameFocused = true }
        .onChange(of: name) { _, new in
            if new.count > MailLabel.maxNameLength { name = String(new.prefix(MailLabel.maxNameLength)) }
        }
        .alert(
            "Label Not Created",
            isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } }),
            presenting: error
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.localizedDescription)
        }
    }

    private func swatch(_ hex: String) -> some View {
        let isSelected = hex == color
        return Button {
            color = hex
        } label: {
            HUDColorDot(color: MailText.color(ofLabel: hex), size: 30)
                .padding(4)
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(Color.hudAccent, lineWidth: 2)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        // A List row fires every default-styled control it holds at once.
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: hex))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func create() {
        guard !trimmedName.isEmpty, !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await sheet.createLabel(name: trimmedName, color: color)
                dismiss()
            } catch {
                self.error = error
            }
        }
    }
}
