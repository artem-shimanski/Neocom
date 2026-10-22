import SwiftUI

// Previews of the HUD components in `Neocom/Shared/HUD/`, which is compiled into the widget
// extension too and has none of the list and panel scaffolding the previews need.

// MARK: - HUDLevelBar

#Preview("Level bar") {
    LevelBarPreview()
}

private struct LevelBarPreview: View {
    var body: some View {
        HUDList {
            HUDListSection {
                row("Trained III", HUDLevelBar(trained: 3))
                row("Training IV", HUDLevelBar(trained: 3, training: 4))
                row("Training, 62%", HUDLevelBar(trained: 3, training: 4, trainingProgress: 0.62))
                row("Paused", HUDLevelBar(trained: 2, training: 3, paused: true))
                row("Ahead of pilot", HUDLevelBar(trained: 5, ownLevel: 3))
                row("Queued, planned", HUDLevelBar(trained: 2, training: 3, paused: true, queued: 4, planned: 5))
                row("Planned only", HUDLevelBar(trained: 0, planned: 3, height: 8, spacing: 2))
            } header: {
                HUDSectionHeader("Plain").hudListHeader()
            }
            Section {
                row("Set level", HUDLevelBar(trained: 3, includesZero: true) { _ in })
            } header: {
                HUDSectionHeader("Control").hudListHeader()
            }
            HUDListSection {
                HStack(spacing: 12) {
                    ForEach([HUDLevelSegment.trained, .training, .paused, .queued, .planned, .empty], id: \.self) {
                        HUDLevelSwatch(segment: $0)
                    }
                }
                .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 10))
            } header: {
                HUDSectionHeader("Swatches").hudListHeader()
            }
        }
    }

    private func row(_ label: String, _ bar: some View) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: label).font(.hudBody)
            Spacer()
            bar
        }
        .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 10))
    }
}

// MARK: - HUDHatch

#Preview("Hatch") {
    HUDPanel {
        HUDHatch().frame(height: 10).hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 8))
    }
    .padding(.horizontal, HUDMetrics.gutter)
    .background(Color.hudBg.ignoresSafeArea())
}

// MARK: - HUDInitialsAvatar

#Preview("Initials avatar") {
    HStack(spacing: 12) {
        HUDInitialsAvatar(name: "Mira Quillfeather")
        HUDInitialsAvatar(name: "[Corp]")
        HUDInitialsAvatar(name: "")
        HUDInitialsAvatar(name: "Hedda Coldwater", size: 48)
        HUDInitialsAvatar(name: "Mira Quillfeather", url: EVEImage.portrait(characterID: 1, size: 128))
    }
    .padding(HUDMetrics.gutter)
    .background(Color.hudBg)
}

// MARK: - HUDStatusChip

#Preview("Status chip") {
    HStack(spacing: 16) {
        HUDStatusChip(text: Text("Stable"), color: .hudOk, mark: .dot)
        HUDStatusChip(text: Text("Draining"), color: .hudWarn, mark: .symbol("arrow.down"))
        HUDStatusChip(text: Text("Critical"), color: .hudDanger)
    }
    .padding(.horizontal, HUDMetrics.gutter)
    .padding(.top, 8)
    .background(Color.hudBg.ignoresSafeArea())
}

// MARK: - HUDImagePlate

#Preview("Image plate") {
    HStack(spacing: 12) {
        HUDImagePlate(url: nil, size: 32)
        HUDImagePlate(url: nil, size: 48)
        HUDImagePlate(url: nil, size: 64, framed: true)
    }
    .padding(.horizontal, HUDMetrics.gutter)
    .padding(.top, 8)
    .background(Color.hudBg.ignoresSafeArea())
}

// MARK: - HUDJobProgressBar

#Preview("Job progress bar") {
    VStack(spacing: 12) {
        HUDJobProgressBar(fraction: 0.4)
        HUDJobProgressBar(fraction: 1, color: .hudOk)
        HUDJobProgressBar(fraction: 0.6, isPaused: true)
        HUDJobProgressBar(fraction: 0.3, color: .hudDanger, height: 8)
    }
    .padding(HUDMetrics.gutter)
    .background(Color.hudBg.ignoresSafeArea())
}
