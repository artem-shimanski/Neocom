import BusinessKit
import SDEKit
import SwiftUI

// Phrasing of jobs by activity and state, shared by the list and the detail.

extension IndustryActivity {
    /// The name in the job list and its legend.
    var title: String {
        switch self {
        case .manufacturing: String(localized: "Manufacturing")
        case .researchTime: String(localized: "Research · Time")
        case .researchMaterial: String(localized: "Research · Material")
        case .copying: String(localized: "Copying")
        case .reverseEngineering: String(localized: "Reverse Engineering")
        case .invention: String(localized: "Invention")
        case .reaction: String(localized: "Reactions")
        case .unknown: String(localized: "Industry")
        }
    }

    /// The name on a job's own screen, where there is room for it in full.
    var longTitle: String {
        switch self {
        case .researchTime: String(localized: "Research · Time Efficiency")
        case .researchMaterial: String(localized: "Research · Material Efficiency")
        case .reaction: String(localized: "Reaction")
        default: title
        }
    }

    /// The short name a list row's meta line starts with.
    var shortTitle: String {
        switch self {
        case .researchTime: String(localized: "Research TE")
        case .researchMaterial: String(localized: "Research ME")
        case .reaction: String(localized: "Reaction")
        default: title
        }
    }

    var symbol: String {
        switch self {
        case .manufacturing: "hammer"
        case .researchTime: "timer"
        case .researchMaterial: "cube.transparent"
        case .copying: "doc.on.doc"
        case .reverseEngineering: "gearshape.2"
        case .invention: "lightbulb"
        case .reaction: "testtube.2"
        case .unknown: "wrench.and.screwdriver"
        }
    }

    /// The activities the legend explains, in the order the game lists them.
    static let legend: [IndustryActivity] = [
        .manufacturing, .researchTime, .researchMaterial, .copying, .invention, .reaction,
    ]

    /// What the job's `runs` are counted in: `10 runs`, `2 levels`, `1 copy`.
    func count(_ runs: Int) -> String {
        switch runUnit {
        case .runs: String(localized: "\(runs) runs")
        case .levels: String(localized: "\(runs) levels")
        case .copies: String(localized: "\(runs) copies")
        }
    }
}

extension IndustryJobPhase {
    var title: String {
        switch self {
        case .ready: String(localized: "Ready")
        case .active: String(localized: "industry.jobs.active", defaultValue: "Active", comment: "An industry job that is running; also the count of such jobs")
        case .paused: String(localized: "Paused")
        case .delivered: String(localized: "Delivered")
        case .cancelled: String(localized: "Cancelled")
        case .reverted: String(localized: "Reverted")
        case .unknown: String(localized: "Unknown")
        }
    }

    /// The colour of the state's word and mark.
    var ink: Color {
        switch self {
        case .ready, .delivered: .hudOk
        case .active: .hudInk
        case .paused: .hudWarn
        case .cancelled, .unknown: .hudInkMuted
        case .reverted: .hudDanger
        }
    }

    /// The colour of the progress bar's fill.
    var bar: Color {
        switch self {
        case .ready: .hudOk
        case .active: .hudAccent
        case .paused: .hudWarn
        case .delivered, .cancelled, .unknown: .hudInkFaint
        case .reverted: .hudDanger
        }
    }

    var tone: HUDTone {
        switch self {
        case .paused: .warn
        case .reverted: .danger
        default: .normal
        }
    }
}

extension IndustryContext {
    /// The figure at the right of a job's name: units for manufacturing and reactions, a chance for
    /// invention, `copies × runs` for copying, the efficiency raised for research.
    func outputText(of job: IndustryJob) -> String {
        switch job.activity {
        case .manufacturing, .reaction:
            return "×\((units(of: job) ?? job.runs).formatted())"
        case .invention, .reverseEngineering:
            return job.probability.map { IndustryFormat.percent($0) } ?? "—"
        case .copying:
            return job.licensedRuns.map { "\(job.runs) × \($0)" } ?? job.activity.count(job.runs)
        case .researchTime: return String(localized: "TE")
        case .researchMaterial: return String(localized: "ME")
        case .unknown: return ""
        }
    }

    /// `MANUFACTURING · 10 RUNS · RENS`, upper-cased by the row.
    func meta(of job: IndustryJob) -> String {
        var parts = [job.activity.shortTitle, job.activity.count(job.runs)]
        if let system = system(of: job) { parts.append(system.name) }
        return parts.joined(separator: " · ")
    }

    /// The meta line of a completed job: how it came out instead of where it ran.
    func completedMeta(of job: IndustryJob) -> String {
        var parts = [job.activity.shortTitle]
        switch job.activity {
        case .invention, .reverseEngineering:
            if job.status == "delivered", let ok = job.successfulRuns {
                parts.append(String(localized: "\(ok) of \(job.runs) succeeded"))
            } else {
                parts.append(job.activity.count(job.runs))
            }
            if let probability = job.probability { parts.append(IndustryFormat.percent(probability)) }
        case .copying:
            parts.append(job.activity.count(job.runs))
            if let licensed = job.licensedRuns { parts.append(String(localized: "\(licensed) runs each")) }
        case .manufacturing, .reaction:
            parts.append(job.activity.count(job.runs))
            if let units = units(of: job) { parts.append("×\(units.formatted())") }
            if let system = system(of: job) { parts.append(system.name) }
        default:
            parts.append(job.activity.count(job.runs))
        }
        return parts.joined(separator: " · ")
    }

    /// `Delivered 2026.10.12 19:04 by Bram Ironvale`: the moment it closed, and who did it where
    /// that is not the pilot themselves.
    func closedText(of job: IndustryJob, phase: IndustryJobPhase) -> String {
        let when = EVETime.dateTime(job.completedDate ?? job.endDate)
        if let by = job.completedCharacterID, by != characterID, phase != .reverted {
            return String(localized: "\(phase.title) \(when) by \(pilotName(by))")
        }
        return String(localized: "\(phase.title) \(when)")
    }
}

enum IndustryFormat {
    /// A chance as a whole percent: `43%`.
    static func percent(_ fraction: Double) -> String {
        "\((fraction * 100).formatted(.number.precision(.fractionLength(0))))%"
    }
}
