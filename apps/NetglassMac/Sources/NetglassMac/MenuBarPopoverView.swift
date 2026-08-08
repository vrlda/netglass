import SwiftUI

/// The popover shown by the existing menu bar item. Compact monitoring panel
/// built from real live data.
struct MenuBarPopoverView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var liveModel: LiveConnectionsModel
    @EnvironmentObject private var appVM: AppViewModel
    @EnvironmentObject private var monitoring: MonitoringViewModel
    @EnvironmentObject private var capture: PacketCaptureViewModel
    @EnvironmentObject private var rateTracker: AppRateTracker

    private var apps: [AppAgg] { RealAgg.apps(from: liveModel.flows) }
    private var samples: [TrafficChartSample] {
        TrafficHistory.aggregate(liveModel.throughputHistory,
                                                                 bucketSeconds: liveModel.samplesPerBucket, capacity: 60)
    }
    private var totalUp: Double { samples.reduce(0) { $0 + $1.up } }
    private var totalDown: Double { samples.reduce(0) { $0 + $1.down } }

    private var recentEvents: [(symbol: String, color: Color, text: String)] {
        var events: [(String, Color, String)] = []
        if let unresolved = liveModel.resolutionEvents.last(where: { $0.domain == nil }) {
            events.append(("questionmark.circle", NetglassColors.warning,
                           "No domain for \(unresolved.ip)"))
        }
        if let resolved = liveModel.resolutionEvents.last(where: { $0.domain != nil }) {
            events.append(("globe", NetglassColors.download,
                           "\(resolved.ip) → \(resolved.domain ?? "")"))
        }
        if capture.isRecording {
            events.append(("record.circle", NetglassColors.error,
                           "Capturing \(capture.currentScope.rawValue)\(capture.scopeValue.map { " · \($0)" } ?? "")"))
        }
        if monitoring.isPaused {
            events.append(("pause.fill", NetglassColors.warning, "Monitoring paused"))
        }
        return events
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NetglassSpacing.section) {
            header
            graph
            recentActivity
            if !recentEvents.isEmpty {
                events
            }
            summary
            footer
        }
        .padding(NetglassSpacing.section)
        .frame(width: 372)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Text("Netglass").font(.system(size: 13, weight: .semibold))
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(statusColor)
            Spacer()
            Text(primaryInterfaceDisplay)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(.quaternary.opacity(0.5), in: Capsule())
            Button {
                monitoring.toggle()
            } label: {
                Image(systemName: monitoring.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 9))
            }
            .controlSize(.mini)
            .help(monitoring.isPaused ? "Resume monitoring" : "Pause monitoring")
        }
    }

    private var primaryInterfaceDisplay: String {
        let name = InterfaceStore.primary()
        let ip = InterfaceStore.interfaces().first { $0.name == name }?.ipv4
        return ip.map { "\(name) · \($0)" } ?? name
    }

    private var statusColor: Color {
        if capture.isRecording { return NetglassColors.error }
        if monitoring.isPaused { return NetglassColors.warning }
        return NetglassColors.active
    }

    private var statusText: String {
        if capture.isRecording { return "Recording" }
        if monitoring.isPaused { return "Paused" }
        return "Monitoring"
    }

    // MARK: - Graph

    private var graph: some View {
        VStack(spacing: 2) {
            HStack {
                Text("Last 5 minutes")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("↑ \(ByteRate.string(totalUp))")
                    .font(.system(size: 9, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(NetglassColors.upload)
                Text("↓ \(ByteRate.string(totalDown))")
                    .font(.system(size: 9, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(NetglassColors.download)
            }
            TrafficBarChart(samples: samples.isEmpty ? [.zero] : samples,
                            paused: monitoring.isPaused, tickSeconds: 5, capacity: 60)
                .frame(height: 120)
        }
    }

    // MARK: - Recent activity

    private var recentActivity: some View {
        let active = rateTracker.activeApps(apps).prefix(4)
        return VStack(alignment: .leading, spacing: 1) {
            Text("Active Apps")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 3)
            if active.isEmpty {
                Text("No traffic observed yet")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(active) { app in
                    let rate = rateTracker.rates[app.processPath] ?? (0, 0)
                    Button {
                        appVM.selectedSection = .applications
                        NotificationCenter.default.post(name: .netglassOpenMainWindow, object: nil)
                    } label: {
                        HStack(spacing: 6) {
                            Image(nsImage: AppIcon.image(forProcessPath: app.processPath))
                                .resizable()
                                .frame(width: 16, height: 16)
                            Text(app.name)
                                .font(.system(size: 12))
                            Spacer()
                            Text("↑ \(ByteRate.string(rate.up))")
                                .font(.system(size: 10, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(NetglassColors.upload)
                            Text("↓ \(ByteRate.string(rate.down))")
                                .font(.system(size: 10, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(NetglassColors.download)
                            Text("\(app.activeConnections)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .frame(width: 18, alignment: .trailing)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Events

    private var events: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Recent Events")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 3)
            ForEach(Array(recentEvents.enumerated()), id: \.offset) { _, event in
                HStack(spacing: 5) {
                    Image(systemName: event.symbol)
                        .font(.system(size: 9))
                        .foregroundStyle(event.color)
                        .frame(width: 14)
                    Text(event.text)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 1)
            }
        }
    }

    // MARK: - Summary

    private var summary: some View {
        HStack(spacing: 0) {
            summaryItem("Active", "\(liveModel.flows.filter(\.isActive).count)")
            Divider()
            summaryItem("Up · 5 min", ByteRate.string(totalUp))
            Divider()
            summaryItem("Down · 5 min", ByteRate.string(totalDown))
            Divider()
            summaryItem("Packets", capture.isRecording
                        ? "\(Int(capture.packetsPerSecond))/s" : "—")
        }
        .padding(.top, 2)
    }

    private func summaryItem(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 9)).foregroundStyle(.tertiary)
            Text(value).font(.system(size: 11, design: .monospaced)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, NetglassSpacing.standard)
        .padding(.vertical, 2)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Button("Open Netglass") {
                NotificationCenter.default.post(name: .netglassOpenMainWindow, object: nil)
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)

            Button {
                if capture.isRecording {
                    capture.stop()
                } else {
                    capture.start(scope: .allTraffic)
                }
            } label: {
                Label(capture.isRecording ? "Stop Capture" : "Start Capture",
                      systemImage: capture.isRecording ? "stop.fill" : "record.circle")
            }
            .controlSize(.small)
            .tint(capture.isRecording ? .red : nil)

            Button {
                appVM.selectedSection = .packetInspector
                NotificationCenter.default.post(name: .netglassOpenMainWindow, object: nil)
            } label: {
                Image(systemName: "rectangle.3.group")
            }
            .controlSize(.small)
            .help("Open Packet Inspector")

            Spacer()

            Menu {
                Button("Open Settings") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                Divider()
                Button("Quit Netglass") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
            }
            .controlSize(.small)
            .help("More")
        }
    }
}
