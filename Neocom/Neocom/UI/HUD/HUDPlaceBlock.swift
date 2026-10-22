import SwiftUI

/// A station or structure as a block: the name, and a line that places it
/// (`RENS 0.9 · HEIMATAR · 2 J FROM OSOGGUR`) with the security in its own colour.
struct HUDPlaceBlock: View {
    let name: String
    let line: Text?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: name)
                .font(.hudBody)
                .fixedSize(horizontal: false, vertical: true)
            if let line {
                line
                    .font(.hudCaption)
                    .foregroundStyle(Color.hudInkMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `RENS 0.9`: the system upper-cased, its security in the security colour.
    static func system(name: String, security: Double) -> Text {
        let security = Text(verbatim: SecurityStatus.string(security))
            .foregroundStyle(SecurityStatus.color(security))
        return Text("\(Text(verbatim: name.uppercased())) \(security)")
    }

    /// Parts joined with a middle dot, each keeping its colour; `nil` for none.
    static func joined(_ parts: [Text]) -> Text? {
        guard let first = parts.first else { return nil }
        return parts.dropFirst().reduce(first) { Text("\($0) · \($1)") }
    }

    /// The place line: system with security, then region, facility kind and jumps, upper-cased;
    /// `nil` when empty.
    static func line(systemName: String?, security: Double?, details: [String?]) -> Text? {
        var parts: [Text] = []
        if let systemName, let security { parts.append(system(name: systemName, security: security)) }
        parts += details.compactMap { $0 }.filter { !$0.isEmpty }.map { Text(verbatim: $0.uppercased()) }
        return joined(parts)
    }
}

#Preview("Place block") {
    HUDPlaceBlock(name: "Rens VI - Moon 8 - Brutor Tribe Treasury",
                  line: HUDPlaceBlock.line(systemName: "Rens", security: 0.9, details: ["Heimatar", "2 J from Osoggur"]))
        .padding(HUDMetrics.gutter)
        .background(Color.hudBg)
}
