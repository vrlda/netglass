import SwiftUI

/// Application Detail for a real app aggregate.
struct ApplicationDetailView: View {
    let app: AppAgg
    @EnvironmentObject private var liveModel: LiveConnectionsModel
    @State private var tab: Tab = .activity

    enum Tab: String, CaseIterable, Identifiable {
        case activity = "Activity"
        case connections = "Connections"
        case domains = "Domains"
        case dns = "DNS"
        case processes = "Processes"
        case captures = "Captures"
        case metadata = "Metadata"
        var id: String { rawValue }
    }

    private var appFlows: [LiveFlow] {
        liveModel.flows.filter { $0.executablePath == app.processPath }
    }

    private var appDomains: [DomainAgg] {
        RealAgg.domains(from: appFlows)
    }

    private var appResolutions: [ResolutionEvent] {
        liveModel.resolutionEvents.filter { $0.processName == app.name }.suffix(20).reversed()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("Tab", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            Group {
                switch tab {
                case .activity: activityTab
                case .connections: connectionsTab
                case .domains: domainsTab
                case .dns: dnsTab
                case .processes: processesTab
                case .captures: capturesTab
                case .metadata: metadataTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, minHeight: 520)
        .padding(.top, 12)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(nsImage: AppIcon.image(forProcessPath: app.processPath))
                    .resizable()
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name).font(.system(size: 19, weight: .semibold))
                    Text(app.processPath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("PIDs: \(app.pids.sorted().map(String.init).joined(separator: ", "))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("Last active \(app.lastActive, style: .relative)")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)

            HStack(spacing: 16) {
                MetricGroup(label: "Active connections", value: "\(app.activeConnections)")
                MetricGroup(label: "Total sent", value: app.bytesSent.formatted(.byteCount(style: .decimal)))
                MetricGroup(label: "Total received", value: app.bytesReceived.formatted(.byteCount(style: .decimal)))
                MetricGroup(label: "Domains", value: "\(app.domains.count)")
                MetricGroup(label: "IPs", value: "\(app.ips.count)")
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
    }

    private var activityTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            TrafficBarChart(samples: TrafficHistory.aggregate(liveModel.throughputHistory,
                                                               bucketSeconds: 5, capacity: 60),
                            paused: false, tickSeconds: 5, capacity: 60)
                .frame(height: 140)
            Text("Recent destinations")
                .font(.system(size: 12, weight: .semibold))
            ForEach(app.destinations) { destination in
                HStack(spacing: 6) {
                    Circle().fill(destination.active ? Color.green : Color.gray)
                        .frame(width: 6, height: 6)
                    Text(destination.name).font(.system(size: 12))
                    Text("\(destination.transport.rawValue.uppercased()) :\(destination.port)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    EvidenceBadge(text: destination.evidence)
                    Spacer()
                }
                .padding(.vertical, 1)
            }
            Spacer()
        }
        .padding(12)
    }

    private var connectionsTab: some View {
        Table(appFlows) {
            TableColumn("Remote") { flow in
                Text("\(flow.remote.address.text):\(flow.remote.port)")
                    .font(.system(size: 11, design: .monospaced))
            }
            TableColumn("Domain") {
                Text($0.remoteDomain ?? "—").font(.system(size: 11))
            }
            TableColumn("Protocol") {
                Text($0.transport.rawValue.uppercased()).font(.system(size: 11, design: .monospaced))
            }
            TableColumn("Sent") {
                MonoCell(text: Self.bytes($0.bytesSent), width: 76)
            }
            TableColumn("Received") {
                MonoCell(text: Self.bytes($0.bytesReceived), width: 76)
            }
            TableColumn("State") {
                StateBadge(state: $0.isActive ? "Active" : "Closed")
            }
        }
        .overlay {
            if appFlows.isEmpty {
                EmptyStateView(symbol: "point.3.connected.trianglepath.dotted",
                               title: "No connections",
                               message: "This application has no observed connections")
            }
        }
    }

    private var domainsTab: some View {
        Table(appDomains) {
            TableColumn("Domain") { Text($0.name).font(.system(size: 12)) }
            TableColumn("Evidence") { EvidenceBadge(text: $0.evidence) }
            TableColumn("Confidence") {
                Text($0.confidence.map { String(format: "%.0f%%", $0 * 100) } ?? "—")
                    .font(.system(size: 11, design: .monospaced))
            }
            TableColumn("IPs") {
                Text($0.ipAddresses.joined(separator: ", "))
                    .font(.system(size: 11, design: .monospaced))
            }
            TableColumn("Sent") {
                Text($0.bytesSent.formatted(.byteCount(style: .decimal)))
                    .font(.system(size: 11, design: .monospaced))
            }
            TableColumn("Received") {
                Text($0.bytesReceived.formatted(.byteCount(style: .decimal)))
                    .font(.system(size: 11, design: .monospaced))
            }
        }
    }

    private var dnsTab: some View {
        VStack(alignment: .leading) {
            if appResolutions.isEmpty {
                EmptyStateView(symbol: "globe",
                               title: "No domain lookups yet",
                               message: "Reverse DNS evidence for this app appears here")
            } else {
                Table(Array(appResolutions)) {
                    TableColumn("Time") {
                        Text($0.date.formatted(date: .omitted, time: .standard))
                            .font(.system(size: 11, design: .monospaced))
                    }
                    TableColumn("IP") {
                        Text($0.ip).font(.system(size: 11, design: .monospaced))
                    }
                    TableColumn("Result") {
                        Text($0.domain ?? "No domain observed")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle($0.domain != nil ? Color.primary : Color.secondary)
                    }
                    TableColumn("Evidence") { EvidenceBadge(text: $0.source ?? "Unknown") }
                }
            }
        }
    }

    private var processesTab: some View {
        VStack(alignment: .leading) {
            Table(app.pids.sorted().map { ProcessRow(pid: $0, path: app.processPath) }) {
                TableColumn("PID") {
                    Text("\($0.pid)").font(.system(size: 11, design: .monospaced))
                }
                TableColumn("Executable") {
                    Text($0.path).font(.system(size: 11, design: .monospaced))
                }
            }
        }
    }

    private var capturesTab: some View {
        VStack(alignment: .leading) {
            EmptyStateView(symbol: "record.circle",
                           title: "No captures",
                           message: "Explicit packet captures appear here (requires capture infrastructure)")
        }
    }

    private var metadataTab: some View {
        Form {
            LabeledContent("Executable", value: app.processPath)
            LabeledContent("Process IDs", value: app.pids.sorted().map(String.init).joined(separator: ", "))
            LabeledContent("Architecture", value: "arm64")
            LabeledContent("First seen", value: appFlows.map(\.startedAt).min()?.formatted() ?? "—")
            LabeledContent("Last seen", value: app.lastActive.formatted())
        }
        .formStyle(.grouped)
    }

    private struct ProcessRow: Identifiable {
        let pid: Int32
        let path: String
        var id: Int32 { pid }
    }

    private static func bytes(_ value: UInt64) -> String {
        value.formatted(.byteCount(style: .decimal))
    }
}
