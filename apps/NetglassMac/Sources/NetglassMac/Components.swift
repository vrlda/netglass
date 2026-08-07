import SwiftUI

// MARK: - Design tokens

enum NetglassSpacing {
    static let tiny: CGFloat = 4
    static let small: CGFloat = 6
    static let standard: CGFloat = 8
    static let section: CGFloat = 12
    static let major: CGFloat = 16
    static let page: CGFloat = 20
}

enum NetglassCorner {
    static let compact: CGFloat = 8
    static let panel: CGFloat = 10
}

enum NetglassColors {
    /// Upload — muted magenta/violet (charts, transfer values only).
    static let upload = Color(red: 0.66, green: 0.44, blue: 0.84)
    /// Download — clear system blue.
    static let download = Color(red: 0.25, green: 0.50, blue: 0.96)
    static let active = Color.green
    static let warning = Color.orange
    static let error = Color.red
}

enum NetglassTypography {
    static func pageTitle(_ text: String) -> Text {
        Text(text).font(.system(size: 15, weight: .semibold))
    }
    static func sectionHeading(_ text: String) -> Text {
        Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
    }
    static func row(_ text: String) -> Text {
        Text(text).font(.system(size: 13))
    }
    static func technical(_ text: String) -> Text {
        Text(text).font(.system(size: 12, design: .monospaced))
    }
    static func support(_ text: String) -> Text {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
    }
    static func metadata(_ text: String) -> Text {
        Text(text).font(.system(size: 10)).foregroundStyle(.tertiary)
    }
}

enum NetglassMetrics {
    static let sidebarWidth: CGFloat = 248
    static let inspectorWidth: CGFloat = 300
    static let navigationRowHeight: CGFloat = 30
    /// Fixed traffic-chart full scale (B/s): 5 MB/s keeps idle bars visible
    /// and guarantees old candles never rescale.
    static let chartPeak: Double = 5_000_000
}

// MARK: - Shared components

/// Compact ↑/↓ rate pair; direction colors only on the arrows.
struct TrafficRateView: View {
    let up: Double
    let down: Double

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                Text("↑").font(.system(size: 10, weight: .medium)).foregroundStyle(NetglassColors.upload)
                Text(ByteRate.string(up)).font(.system(size: 11, design: .monospaced)).monospacedDigit()
            }
            HStack(spacing: 3) {
                Text("↓").font(.system(size: 10, weight: .medium)).foregroundStyle(NetglassColors.download)
                Text(ByteRate.string(down)).font(.system(size: 11, design: .monospaced)).monospacedDigit()
            }
        }
    }
}

/// Metric pair: secondary label above, aligned value below. No card.
struct MetricGroup: View {
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(valueColor)
        }
        .frame(minWidth: 74, alignment: .leading)
    }
}

/// Collapsible inspector group with quiet separators, label-value rows.
/// The whole header toggles expansion.
struct InspectorSection<Content: View>: View {
    let title: String
    let systemImage: String
    @State private var expanded = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            ExpandableRow(isExpanded: $expanded) {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            } content: {
                VStack(alignment: .leading, spacing: 3) {
                    content()
                }
                .padding(.top, 4)
            }
            .padding(.vertical, 5)
            Divider().opacity(0.5)
        }
    }
}

/// Inspector label-value row: fixed label, selectable right-aligned value.
struct InspectorField: View {
    let name: String
    let value: String
    var mono = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(name)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .font(mono ? .system(size: 11, design: .monospaced) : .system(size: 11))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

/// Subtle evidence badge (Verified by DNS, TLS SNI, …).
struct EvidenceBadge: View {
    let text: String

    var body: some View {
        if text.isEmpty || text == "Unknown" {
            EmptyView()
        } else {
            Text(text)
                .font(.system(size: 9))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.quaternary.opacity(0.6), in: Capsule())
                .foregroundStyle(.secondary)
        }
    }
}

/// Connection state chip.
struct StateBadge: View {
    let state: String

    var body: some View {
        Text(state)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch state {
        case "Active": .green
        case "Connecting": .yellow
        case "Idle": .gray
        case "Closed": .secondary
        case "Failed": .red
        default: .secondary
        }
    }
}

/// Capture status chip with red recording state.
struct CaptureStatusBadge: View {
    let status: CaptureStatus

    var body: some View {
        HStack(spacing: 4) {
            if status == .recording {
                Circle().fill(.red).frame(width: 7, height: 7)
            }
            Text(status.rawValue.capitalized)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(status == .recording ? .red
                                 : status == .failed ? .orange : .secondary)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(
            (status == .recording ? Color.red : status == .failed ? Color.orange : Color.gray)
                .opacity(0.12), in: Capsule())
    }
}

/// Restrained empty state.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Text(message).font(.system(size: 10)).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(NetglassSpacing.major)
    }
}

/// Fixed-width monospaced cell for tables.
struct MonoCell: View {
    let text: String
    let width: CGFloat
    var alignment: Alignment = .trailing
    var color: Color = .primary

    var body: some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(color)
            .frame(width: width, alignment: alignment)
    }
}

/// Expandable row where the ENTIRE label area toggles expansion, not just a
/// chevron. Chevron rotates to keep the affordance obvious. Use everywhere an
/// expand/collapse interaction exists.
struct ExpandableRow<Label: View, Content: View>: View {
    @Binding var isExpanded: Bool
    @ViewBuilder let label: () -> Label
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    // Swap glyphs instead of rotating: rotating SF Symbol
                    // chevrons shifts the visual glyph (offset bounding box)
                    // and List rows drop rotation animations — both read as a
                    // "jump". Glyph replace morphs in place.
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .contentTransition(.symbolEffect(.replace))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15),
                                   value: isExpanded)
                    label()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .padding(.leading, 12)
            }
        }
    }
}
