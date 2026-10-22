import SDEKit
import SwiftUI
import TrainingKit

/// One skill group: its figures over the list of its skills, alphabetical.
struct SkillGroupView: View {
    let groupID: GroupID

    @State private var showsLegend = false

    var body: some View {
        SkillsReader { overview in
            if let group = overview.group(groupID) {
                SkillGroupList(group: group, names: overview.names)
            } else {
                ContentUnavailableView(
                    "Unknown Group",
                    systemImage: "book.closed",
                    description: Text("Group \(groupID.rawValue, format: .number.grouping(.never)) has no published skills.")
                )
            }
        }
        .hudScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { SkillsLegendButton(isPresented: $showsLegend) }
        .sheet(isPresented: $showsLegend) { SkillsLegendSheet() }
    }
}

private struct SkillGroupList: View {
    let group: SkillsOverview.Group
    let names: [TypeID: String]

    @State private var searchText = ""

    var body: some View {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let skills = query.isEmpty
            ? group.skills
            : group.skills.filter { $0.row.name.localizedStandardContains(query) }
        HUDList {
            Section {
                header.hudBareRow()
            }
            if skills.isEmpty {
                Section {
                    ContentUnavailableView.search(text: searchText)
                        .hudBareRow()
                }
            } else {
                HUDListSection(skills, row: { skill in
                    SkillRowView(skill: skill, names: names)
                }, header: {
                    HUDSectionHeader(Text("Skills · \(skills.count)"))
                }, footer: {
                    HUDFootnote("Tap a skill for its description, levels and prerequisites. The (?) button explains the symbols and bar segments.")
                })
            }
        }
        .searchable(text: $searchText, prompt: Text("Skill name"))
        .navigationTitle(Text(verbatim: group.name))
    }

    private var header: some View {
        HUDPanel {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: group.name)
                    .font(HUDFont.display(24, weight: .bold, relativeTo: .title2))
                    .tracking(0.5)
                    .textCase(.uppercase)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        figures
                        Spacer(minLength: 0)
                        SkillCountChips(tally: group.tally, includesQueueAndPlan: false)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        figures
                        SkillCountChips(tally: group.tally, includesQueueAndPlan: false)
                    }
                }
            }
            .padding(HUDMetrics.gutter)
        }
    }

    private var figures: some View {
        skillFigures(group.tally, skillsWord: true)
            .font(.hudCaption)
            .textCase(.uppercase)
            .foregroundStyle(Color.hudInkMuted)
            .lineLimit(1)
            .fixedSize()
    }
}
