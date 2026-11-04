import AgentSpeedCore
import SwiftUI

/// One rate in fixed cells (DESIGN 10): the arrow, the number right-aligned in an `8.88` cell, the unit left-aligned in
/// an `MB/s` cell. A rate below `dashBelow` reads as the tertiary `–` in the number cell.
struct TrafficRateLabel: View {
    let down: Bool
    /// Bytes per second; nil reads `–`.
    let rate: Double?
    let text: TrafficText
    var size: CGFloat = 11
    var weight: Font.Weight = .medium
    var dashBelow: Double = 0
    /// Number color; arrows and units are secondary.
    var numberStyle: AnyShapeStyle = AnyShapeStyle(.primary)

    var body: some View {
        let cells = TrafficCells.widths(size: size, weight: weight.nsWeight, bits: text.bits)
        let shown = rate.flatMap { $0 >= dashBelow ? text.rate($0) : nil }
        HStack(spacing: 0) {
            Text(verbatim: down ? "↓" : "↑")
                .foregroundStyle(.dashboardSecondary)
                .padding(.trailing, size * 0.25)
            Text(verbatim: shown?.number ?? "–")
                .foregroundStyle(shown == nil ? AnyShapeStyle(.tertiary) : numberStyle)
                .frame(width: cells.number, alignment: .trailing)
            Text(verbatim: shown?.unit ?? "")
                .foregroundStyle(.dashboardSecondary)
                .padding(.leading, size * 0.25)
                .frame(width: cells.unit + size * 0.25, alignment: .leading)
        }
        .font(.system(size: size, weight: weight).monospacedDigit())
        .lineLimit(1)
        .fixedSize()
        .accessibilityHidden(true)
    }
}

extension Font.Weight {
    var nsWeight: NSFont.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }
}
