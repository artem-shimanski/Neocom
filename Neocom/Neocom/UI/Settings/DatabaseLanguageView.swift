import SDEKit
import SwiftUI

/// Settings › Database Language: the language of the static data's names and descriptions,
/// one row per language the SDE comes in. Every language is bundled; a tap switches to it.
struct DatabaseLanguageView: View {

    var body: some View {
        SDESectionView { database in
            DatabaseLanguageList(build: database.buildNumber)
        }
        .hudScreen()
        .navigationTitle("Database Language")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DatabaseLanguageList: View {
    #if targetEnvironment(macCatalyst)
    private static let footnote = Text("Names and descriptions of items, ships, skills and places follow this language, in the database, fits, market and assets. Search finds English names too. The rest of Neocom follows the language of macOS.")
    #else
    private static let footnote = Text("Names and descriptions of items, ships, skills and places follow this language, in the database, fits, market and assets. Search finds English names too. The rest of Neocom follows the language of iOS.")
    #endif

    let build: Int

    @Environment(SDEStore.self) private var sde

    @State private var failure: Failure?

    struct Failure: Equatable {
        var language: SDELanguage
        var message: String
    }

    var body: some View {
        HUDList {
            if let failure {
                Section {
                    HUDPanel(tone: .warn) {
                        HUDPanelHeader(title: Text(verbatim: failure.language.nativeName))
                        HUDWarnNote(Text(failure.message))
                    }
                    .hudBareRow()
                }
            }

            HUDListSection(SDELanguage.all) { language in
                LanguageRow(language: language,
                            isCurrent: language == (sde.requested ?? sde.switchingTo ?? sde.language),
                            isSwitching: language == sde.switchingTo,
                            onPick: { pick(language) })
            } header: {
                HUDSectionHeader(Text("Languages · \(SDELanguage.all.count)")) {
                    Text(verbatim: "SDE \(build)")
                }
            } footer: {
                HUDFootnote(Self.footnote)
            }
        }
        .animation(.default, value: failure)
    }

    private func pick(_ language: SDELanguage) {
        failure = nil
        Task {
            do {
                try await sde.selectLanguage(language)
            } catch is CancellationError {
            } catch {
                failure = Failure(language: language, message: error.localizedDescription)
            }
        }
    }
}

/// One language: its name in itself, its English name in caps under it, and at the end the check of
/// the current one, or a spinner while it is being switched to.
private struct LanguageRow: View {
    let language: SDELanguage
    let isCurrent: Bool
    let isSwitching: Bool
    let onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: language.nativeName)
                        .font(.hudTileTitle)
                        .foregroundStyle(Color.hudInk)
                    Text(verbatim: language.englishName.uppercased())
                        .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                        .foregroundStyle(Color.hudInkMuted)
                }
                Spacer(minLength: 8)
                if isSwitching {
                    ProgressView()
                } else if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.hudAccent)
                        .accessibilityLabel(Text("Selected"))
                }
            }
            .padding(.horizontal, HUDMetrics.gutter)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: HUDRowStyle.subtitled.minHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.hudRow)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .hudRowCell(.subtitled)
    }
}

#Preview {
    NavigationStack {
        DatabaseLanguageView()
    }
    .environment(SDEStore())
}
