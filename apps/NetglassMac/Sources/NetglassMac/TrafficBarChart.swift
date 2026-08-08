import SwiftUI

/// Up/down traffic timeline: upload extends up from the center baseline,
/// download extends down. Fixed scale (never re-fits, so bars never jump);
/// new buckets SLIDE in with stable candle identities. Paused dims the chart.
struct TrafficBarChart: View {
    let samples: [TrafficChartSample]
    let paused: Bool
    var leftLabel = "5 minutes ago"
    var rightLabel = "now"
    var tickSeconds = 5.0
    /// Fixed number of horizontal slots (right-anchored live scroll).
    var capacity: Int?

    @State private var hoverID: TrafficChartSample.ID?
    /// Fixed full-scale for every chart (5 MB/s per bucket): old candles
    /// never rescale, so bars only change with real traffic.
    private let scale = NetglassMetrics.chartPeak
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var slots: Int { capacity ?? max(samples.count, 1) }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let mid = h / 2
                let slotWidth = w / CGFloat(slots)
                let barWidth = max(2, slotWidth - 1.5)

                ZStack(alignment: .topLeading) {
                    gridAndBaseline(w: w, h: h, mid: mid)

                    HStack(alignment: .center, spacing: 1.5) {
                        ForEach(samples) { sample in
                            column(sample: sample, mid: mid, barWidth: barWidth)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)   // right-anchored
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: samples)

                    if let hoverID,
                       let hoverIndex = samples.firstIndex(where: { $0.id == hoverID }) {
                        tooltip(sample: samples[hoverIndex], index: hoverIndex)
                    }
                }
            }
            .opacity(paused ? 0.45 : 1)

            HStack {
                Text(leftLabel).font(.system(size: 9)).foregroundStyle(.tertiary)
                Spacer()
                Text(rightLabel).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }

    private func column(sample: TrafficChartSample, mid: CGFloat,
                        barWidth: CGFloat) -> some View {
        let upH = min(1, sample.up / scale) * (mid - 6)
        let downH = min(1, sample.down / scale) * (mid - 6)
        return VStack(spacing: 0) {
            Color.clear.frame(height: max(0, mid - upH))
            RoundedRectangle(cornerRadius: 1.5)
                .fill(NetglassColors.upload.opacity(hoverID == sample.id ? 0.95 : 0.72))
                .frame(width: barWidth, height: max(0, upH))
            RoundedRectangle(cornerRadius: 1.5)
                .fill(NetglassColors.download.opacity(hoverID == sample.id ? 0.95 : 0.72))
                .frame(width: barWidth, height: max(0, downH))
            Color.clear.frame(height: max(0, mid - downH))
        }
        .frame(width: barWidth)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hoverID = sample.id }
            else if hoverID == sample.id { hoverID = nil }
        }
    }

    private func gridAndBaseline(w: CGFloat, h: CGFloat, mid: CGFloat) -> some View {
        Canvas { context, _ in
            var base = Path()
            base.move(to: CGPoint(x: 0, y: mid))
            base.addLine(to: CGPoint(x: w, y: mid))
            context.stroke(base, with: .color(.secondary.opacity(0.22)), lineWidth: 0.5)
            for f in [0.25, 0.75] {
                var grid = Path()
                grid.move(to: CGPoint(x: 0, y: mid * f * 2))
                grid.addLine(to: CGPoint(x: w, y: mid * f * 2))
                context.stroke(grid, with: .color(.secondary.opacity(0.06)), lineWidth: 0.5)
            }
        }
    }

    private func tooltip(sample: TrafficChartSample, index: Int) -> some View {
        let secondsAgo = Int(Double(samples.count - 1 - index) * tickSeconds)
        return VStack(alignment: .leading, spacing: 2) {
            Text(timeAgo(secondsAgo)).font(.system(size: 9)).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text("↑").font(.system(size: 9, weight: .medium))
                    .foregroundStyle(NetglassColors.upload)
                Text(ByteRate.string(sample.up)).font(.system(size: 9, design: .monospaced))
            }
            HStack(spacing: 4) {
                Text("↓").font(.system(size: 9, weight: .medium))
                    .foregroundStyle(NetglassColors.download)
                Text(ByteRate.string(sample.down)).font(.system(size: 9, design: .monospaced))
            }
        }
        .padding(5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .offset(x: 8, y: 4)
    }


    private func timeAgo(_ seconds: Int) -> String {
        guard seconds > 0 else { return "now" }
        return "\(seconds / 60)m \(seconds % 60)s ago"
    }
}

/// Tiny two-series sparkline for compact panels and the inspector.
struct MiniTrafficSparkline: View {
    let samples: [TrafficChartSample]

    var body: some View {
        Canvas { context, size in
            let peak = max(1_000, samples.map { max($0.up, $0.down) }.max() ?? 0)
            let w = size.width, h = size.height
            func path(_ keyPath: KeyPath<TrafficChartSample, Double>) -> Path {
                var p = Path()
                for (i, s) in samples.enumerated() {
                    let x = samples.count == 1 ? w / 2 : CGFloat(i) / CGFloat(max(1, samples.count - 1)) * w
                    let y = h - CGFloat(s[keyPath: keyPath] / peak) * (h - 2)
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
                return p
            }
            context.stroke(path(\.up), with: .color(NetglassColors.upload.opacity(0.9)), lineWidth: 1)
            context.stroke(path(\.down), with: .color(NetglassColors.download.opacity(0.9)), lineWidth: 1)
        }
    }
}
