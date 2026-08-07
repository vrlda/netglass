import SwiftUI

/// Overview: compact summary strip, live traffic timeline (real data), and
/// two dense real-data columns.
struct OverviewView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var liveModel: LiveConnectionsModel
    @EnvironmentObject private var monitoring: MonitoringViewModel
    @EnvironmentObject private var appVM: AppViewModel
    @EnvironmentObject private var rateTracker: AppRateTracker
    @EnvironmentObject private var capture: PacketCaptureViewModel
    @State private var metricMode: MetricMode = .bytes
    @State private var historicalSamples: [TrafficChartSample] = []

    enum MetricMode: String, CaseIterable, Identifiable {
        case bytes = "B/s"
        case packets = "packets/s"
        var id: String { rawValue }
    }

    private var apps: [AppAgg] { RealAgg.apps(from: liveModel.flows) }
    private var domains: [DomainAgg] { RealAgg.domains(from: liveModel.flows) }
    private var activeFlows: [LiveFlow] { liveModel.flows.filter(\.isActive) }

    private var liveSamples: [TrafficChartSample] {
        TrafficHistory.aggregate(liveModel.throughputHistory,
                                                                 bucketSeconds: liveModel.samplesPerBucket, capacity: 60)
    }

    private var samples: [TrafficChartSample] {
        if metricMode == .packets {
            // real per-second packet rates from the active capture
            return capture.packetsHistory
        }
        switch appVM.timeRange {
        case .live, .fiveMinutes:
            return liveSamples.isEmpty ? [.zero] : liveSamples
        case .hour, .day:
            return historicalSamples
        }
    }

    private var totalUp: Double { samples.reduce(0) { $0 + $1.up } }
    private var totalDown: Double { samples.reduce(0) { $0 + $1.down } }

    private var chartCapacity: Int {
        switch appVM.timeRange {
        case .live, .fiveMinutes: 60
        case .hour: 60
        case .day: 144
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NetglassSpacing.section) {
                summaryStrip
                Divider().opacity(0.6)
                trafficSection
                Divider().opacity(0.6)
                columns
            }
            .padding(.horizontal, NetglassSpacing.page)
            .padding(.vertical, NetglassSpacing.section)
        }
        .task(id: appVM.timeRange) { await loadHistorical() }
    }

    private func loadHistorical() async {
        guard appVM.timeRange == .hour || appVM.timeRange == .day else {
            historicalSamples = []
            return
        }
        guard let db = appState.database else { return }
        let layout = TrafficHistory.bucketLayout(appVM.timeRange)
        let buckets = (try? db.trafficBuckets(secondsPerBucket: layout.seconds,
                                              buckets: layout.count)) ?? []
        historicalSamples = TrafficHistory.bucketSamples(buckets,
                                                         secondsPerBucket: layout.seconds)
    }

    // MARK: - Summary strip

    private var summaryStrip: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 16, alignment: .leading)],
                  alignment: .leading, spacing: 10) {
            MetricGroup(label: "Upload", value: "↑ \(ByteRate.string(liveModel.throughput.bytesPerSecondUp))",
                        valueColor: NetglassColors.upload)
            MetricGroup(label: "Download", value: "↓ \(ByteRate.string(liveModel.throughput.bytesPerSecondDown))",
                        valueColor: NetglassColors.download)
            MetricGroup(label: "Total uploaded", value: ByteRate.string(totalUp))
            MetricGroup(label: "Total downloaded", value: ByteRate.string(totalDown))
            MetricGroup(label: "Active connections", value: "\(activeFlows.count)")
            MetricGroup(label: "Active apps", value: "\(Set(activeFlows.map(\.processName)).count)")
            MetricGroup(label: "Unresolved", value: "\(RealAgg.unresolvedIPs(from: liveModel.flows).count)",
                        valueColor: RealAgg.unresolvedIPs(from: liveModel.flows).isEmpty
                            ? .primary : NetglassColors.warning)
        }
    }

    // MARK: - Traffic timeline

    private var trafficSection: some View {
        VStack(alignment: .leading, spacing: NetglassSpacing.small) {
            HStack(alignment: .firstTextBaseline) {
                NetglassTypography.sectionHeading("Traffic")
                Spacer()
                HStack(spacing: 10) {
                    if metricMode == .packets {
                        Text("\(Int(capture.packetsPerSecond)) packets/s")
                            .font(.system(size: 10, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        if !capture.isRecording {
                            Text("(start a capture)")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    } else {
                        Text("↑ \(ByteRate.string(totalUp))")
                            .font(.system(size: 10, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(NetglassColors.upload)
                        Text("↓ \(ByteRate.string(totalDown))")
                            .font(.system(size: 10, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(NetglassColors.download)
                    }
                }
                Picker("Metric", selection: $metricMode) {
                    ForEach(MetricMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 110)
            }
            TrafficBarChart(samples: samples, paused: monitoring.isPaused,
                            leftLabel: appVM.timeRange == .day ? "24 hours ago"
                                : appVM.timeRange == .hour ? "1 hour ago" : "5 minutes ago",
                            tickSeconds: appVM.timeRange == .live || appVM.timeRange == .fiveMinutes ? 5 : 0,
                            capacity: chartCapacity)
                .frame(height: 250)
        }
    }

    // MARK: - Bottom columns

    private var columns: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), alignment: .topLeading)],
                  alignment: .leading, spacing: NetglassSpacing.major) {
            column(title: "Top Applications", section: .applications) {
                ForEach(apps.prefix(6)) { app in
                    HStack(spacing: 6) {
                        Image(systemName: "app").font(.system(size: 12)).foregroundStyle(.secondary)
                            .frame(width: 16)
                        NetglassTypography.row(app.name)
                        Spacer()
                        Text(app.bytesReceived.formatted(.byteCount(style: .decimal)))
                            .font(.system(size: 11, design: .monospaced)).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            column(title: "Top Domains", section: .domains) {
                ForEach(domains.prefix(6)) { domain in
                    HStack(spacing: 6) {
                        Image(systemName: domain.confidence != nil ? "globe" : "questionmark.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(domain.confidence != nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                            .frame(width: 16)
                        NetglassTypography.row(domain.name)
                        EvidenceBadge(text: domain.evidence)
                        Spacer()
                        Text(domain.bytesReceived.formatted(.byteCount(style: .decimal)))
                            .font(.system(size: 11, design: .monospaced)).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            column(title: "New Destinations", section: .domains) {
                let unresolved = RealAgg.unresolvedIPs(from: liveModel.flows)
                if unresolved.isEmpty {
                    Text("No new destinations yet")
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(unresolved.prefix(6), id: \.self) { ip in
                        HStack(spacing: 6) {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                                .frame(width: 16)
                            NetglassTypography.row(ip)
                            Spacer()
                            Text("No verified domain observed")
                                .font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            column(title: "Recent Resolutions", section: .dnsActivity) {
                let events = liveModel.resolutionEvents.suffix(4)
                if events.isEmpty {
                    Text("Waiting for domain lookups")
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(Array(events)) { event in
                        HStack(spacing: 6) {
                            Image(systemName: event.domain != nil ? "globe" : "questionmark.circle")
                                .font(.system(size: 10))
                                .foregroundStyle(event.domain != nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(NetglassColors.warning))
                                .frame(width: 14)
                            NetglassTypography.row(event.domain ?? event.ip)
                            Spacer()
                            Text(event.processName)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func column<Content: View>(title: String, section: AppSection? = nil,
                                       @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                NetglassTypography.sectionHeading(title)
                Spacer()
                if let section {
                    Button("Show All") { appVM.selectedSection = section }
                        .controlSize(.small)
                        .buttonStyle(.link)
                        .font(.system(size: 10))
                }
            }
            .padding(.bottom, 4)
            Divider().opacity(0.5)
            content()
        }
    }
}
