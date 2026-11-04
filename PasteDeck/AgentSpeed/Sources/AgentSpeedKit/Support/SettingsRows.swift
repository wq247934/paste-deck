import SwiftUI

/// A row title that dims with its row when the row is disabled, as AppKit labels do.
struct RowTitle: View {
    let text: String
    @Environment(\.isEnabled) private var isEnabled

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
    }
}

/// Secondary explanatory text under a row title or below a section.
struct Footnote: View {
    let text: String
    @Environment(\.isEnabled) private var isEnabled

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(isEnabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A live value readout beside a control: tabular digits, secondary, dimmed with a disabled row.
struct ValueText: View {
    let text: String
    @Environment(\.isEnabled) private var isEnabled

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .monospacedDigit()
            .foregroundStyle(isEnabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
    }
}

/// A switch row with an optional explanatory subtitle.
struct SettingToggle: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                RowTitle(title)
                if let subtitle {
                    Footnote(subtitle)
                }
            }
        }
    }
}

/// A footnote led by a small status symbol, for warnings and notes that need a little more weight.
struct Notice: View {
    let text: String
    let symbol: String
    var tint: Color = .secondary

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .imageScale(.small)
        }
        .font(.subheadline)
    }
}

/// Label on the left; a slider and its live value on the right.
struct SliderRow<EndLabel: View>: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// Amount one VoiceOver or keyboard adjustment moves the value.
    let step: Double
    let valueText: String
    @ViewBuilder var minimumLabel: EndLabel
    @ViewBuilder var maximumLabel: EndLabel

    static var controlWidth: CGFloat { 300 }

    var body: some View {
        LabeledContent {
            HStack(spacing: Spacing.s) {
                Slider(value: $value, in: range) {
                    Text(title)
                } minimumValueLabel: {
                    minimumLabel
                } maximumValueLabel: {
                    maximumLabel
                }
                .labelsHidden()
                .accessibilityValue(Text(valueText))
                .accessibilityAdjustableAction { direction in
                    value = SliderStep.adjust(value, direction, step: step, in: range)
                }
                ValueText(valueText)
                    .frame(minWidth: 52, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            .frame(width: Self.controlWidth)
        } label: {
            RowTitle(title)
        }
    }
}

enum SliderStep {
    static func adjust(
        _ value: Double,
        _ direction: AccessibilityAdjustmentDirection,
        step: Double,
        in range: ClosedRange<Double>
    ) -> Double {
        switch direction {
        case .increment: (value + step).clamped(to: range)
        case .decrement: (value - step).clamped(to: range)
        @unknown default: value
        }
    }
}

/// A segmented picker with equal segments, trailing-aligned like the other row controls.
struct SegmentedRow<Selection: Hashable, Options: View>: View {
    let title: String
    @Binding var selection: Selection
    /// Width of one segment: the control takes up to `segmentWidth × count`, flush with the trailing edge (the
    /// Liquid Glass control sizes to its labels instead of filling that room).
    var segmentWidth: CGFloat = 76
    let count: Int
    @ViewBuilder var options: Options

    var body: some View {
        LabeledContent {
            Picker(title, selection: $selection) {
                options
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: segmentWidth * CGFloat(count), alignment: .trailing)
        } label: {
            RowTitle(title)
        }
    }
}

/// A section footer with explanatory text, aligned with the rows above it.
struct SectionFootnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Footnote(text)
            // Form footers otherwise align wrapped lines to the trailing edge.
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Small filled circles that hint at "less" and "more" at the ends of a slider.
struct SliderEndDot: View {
    var size: CGFloat
    var opacity: Double = 1

    var body: some View {
        Circle()
            .fill(.secondary)
            .opacity(opacity)
            .frame(width: size, height: size)
            .frame(width: 14, height: 14)
            .accessibilityHidden(true)
    }
}

/// Heat colors tuned for text: darker on light surfaces so small type keeps at least 4.5:1 contrast.
enum HeatText {
    static func color(_ heat: Double, dark: Bool, increasedContrast: Bool) -> Color {
        let base = HeatPalette.color(heat)
        if dark { return (increasedContrast ? base.brightened(0.25) : base).color }
        return base.darkened(increasedContrast ? 0.46 : 0.36).color
    }
}
