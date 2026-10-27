import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI
import TrainingKit

/// The Skills section: every published skill, grouped as the SDE files them, with where each stands
/// for the pilot (trained to V, can train now, needs a skillbook, locked) and what the game queue
/// and the local plan hold of it.
///
/// Wrapped in `SDESectionView`: skill and group names live in the SDE. Levels and queue come from
/// `CharacterSheet` through the training context.
struct SkillsView: View {
    @State private var showsLegend = false

    var body: some View {
        SDESectionView { database in
            SkillsReader { overview in
                SkillsRootList(overview: overview)
            }
            // Registered here rather than in `SDESectionView`: the group screen is this section's
            // own and needs the open database handed to it.
            .navigationDestination(for: SkillsRoute.self) { route in
                switch route {
                case let .group(id):
                    SkillGroupView(groupID: id)
                        .liteDatabase(database.database)
                }
            }
        }
        .hudScreen()
        .navigationTitle("Skills")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { SkillsLegendButton(isPresented: $showsLegend) }
        .sheet(isPresented: $showsLegend) { SkillsLegendSheet() }
    }
}

/// Reads the skills out of the SDE and the pilot out of the environment, and draws `content` once
/// both are there; a loading or an error state until then.
///
/// Both Skills screens go through it: the group screen needs every skill's name for the
/// prerequisites of a locked skill.
struct SkillsReader<Content: View>: View {
    @ViewBuilder var content: (SkillsOverview) -> Content

    @Environment(\.trainingContext) private var trainingContext
    @Environment(AccountStore.self) private var accounts

    @LiteQuery private var rows: [SkillListRow]

    init(@ViewBuilder content: @escaping (SkillsOverview) -> Content) {
        self.content = content
        _rows = LiteQuery(SkillBrowser.skills())
    }

    var body: some View {
        SwiftUI.Group {
            if let context = trainingContext, let pilot = context.pilot, !rows.isEmpty {
                content(SkillsOverview(rows: rows, context: context, pilot: pilot))
            } else if case let .failed(error) = accounts.currentSheet?.state,
                      accounts.currentSheet?.snapshot == nil {
                ContentUnavailableView {
                    Label("Skills Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                }
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .refreshableCommand { [accounts] in
            await accounts.currentSheet?.refresh()
        }
        .task(id: accounts.currentAccountID) {
            await accounts.currentSheet?.ensureFresh()
        }
    }
}

/// The root list: the filter, then either the summary and the groups or, narrowed by the filter or
/// a search, the matching skills under their groups.
private struct SkillsRootList: View {
    let overview: SkillsOverview

    @State private var filter: SkillFilter = .all
    @State private var searchText = ""

    var body: some View {
        HUDList {
            Section {
                Picker("Show", selection: $filter) {
                    ForEach(SkillFilter.allCases, id: \.self) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .hudBareRow()
            }

            if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                searchResults
            } else if let state = filter.state {
                filtered(state)
            } else {
                summary
                groups
            }
        }
        .searchable(text: $searchText, prompt: Text("Skill name"))
    }

    // MARK: - All

    private var summary: some View {
        Section {
            HUDPanel {
                HUDStatStrip(items: [
                    .init(id: 0, label: Text("Skill Points"),
                          value: Text(verbatim: SkillPointsFormat.compact(overview.tally.skillPoints))),
                    .init(id: 1, label: Text("Skills"),
                          value: Text(overview.tally.injected, format: .number),
                          unit: Text(verbatim: "/ \(overview.tally.total)")),
                    .init(id: 2, label: Text("At Level V"),
                          value: Text(overview.tally.trainedToV, format: .number)),
                ], unitCase: nil)
            }
            .hudBareRow()
        }
    }

    private var groups: some View {
        HUDListSection(overview.groups, row: { group in
            SkillGroupRowView(group: group)
        }, header: {
            HUDSectionHeader(Text("Groups · \(overview.groups.count)"))
        }, footer: {
            HUDFootnote("Skills / total counts every injected skill, level 0 included. Tap a group for its skills; a locked skill lists what it still needs.")
        })
    }

    // MARK: - Narrowed

    @ViewBuilder
    private func filtered(_ state: SkillStanding.State) -> some View {
        let sections = overview.sections(filter: filter, search: "", byRank: true)
        Section {
            SkillFilterHeader(state: state, count: overview.tally.count(of: state))
                .hudBareRow()
        }
        skillSections(sections, footnote: Text("Sorted by rank within each group: the quickest to train come first."))
    }

    @ViewBuilder
    private var searchResults: some View {
        let sections = overview.sections(filter: filter, search: searchText, byRank: false)
        if sections.isEmpty {
            Section {
                ContentUnavailableView.search(text: searchText)
                    .hudBareRow()
            }
        } else {
            skillSections(sections, footnote: nil)
        }
    }

    /// One card per group, the footnote under the last of them.
    @ViewBuilder
    private func skillSections(_ sections: [SkillsOverview.Group], footnote: Text?) -> some View {
        ForEach(sections.dropLast()) { section in
            HUDListSection(section.skills, row: { skill in
                SkillRowView(skill: skill, names: overview.names)
            }, header: {
                header(of: section)
            })
        }
        if let last = sections.last {
            HUDListSection(last.skills, row: { skill in
                SkillRowView(skill: skill, names: overview.names)
            }, header: {
                header(of: last)
            }, footer: {
                if let footnote { HUDFootnote(footnote) }
            })
        }
    }

    private func header(of section: SkillsOverview.Group) -> some View {
        HUDSectionHeader(Text(verbatim: section.name)) {
            Text(section.skills.count, format: .number)
        }
    }
}

/// What a narrowed view lists, over the list: the state's glyph, how many, and what to do
/// about them.
private struct SkillFilterHeader: View {
    let state: SkillStanding.State
    let count: Int

    var body: some View {
        HUDPanel {
            HStack(spacing: 12) {
                HUDSkillStateIcon(state: state.icon, size: 22)
                VStack(alignment: .leading, spacing: 3) {
                    title
                        .font(.hudFigure)
                        .textCase(.uppercase)
                    message
                        .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                        .lineSpacing(3)
                        .foregroundStyle(Color.hudInkMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, HUDMetrics.gutter)
            .padding(.vertical, 14)
        }
        .accessibilityElement(children: .combine)
    }

    private var title: Text {
        switch state {
        case .trainedToV: Text("\(count) at level V")
        case .canTrain: Text("\(count) can train")
        case .needsBook: Text("\(count) skillbooks")
        case .locked: Text("\(count) locked")
        }
    }

    private var message: Text {
        switch state {
        case .trainedToV: Text("Every level trained. Nothing left to do.")
        case .canTrain: Text("Injected and prerequisites met: add the next level to the queue.")
        case .needsBook: Text("Prerequisites met, book not injected. Buy the book on the market and inject it in game.")
        case .locked: Text("Prerequisites missing. Each row says which ones.")
        }
    }
}

#Preview {
    NavigationStack {
        SkillsView()
    }
    .environment(AccountStore())
    .environment(SDEStore())
}
