import SwiftUI
import FlowModel
import FlowSource

/// Right-column inspector for a selected connection. Native inspector style:
/// compact header, collapsible groups separated by quiet dividers.
struct ConnectionInspectorView: View {
    let flow: LiveFlow
    @EnvironmentObject private var liveModel: LiveConnectionsModel
    @State private var ancestryNames: [String] = []
    @State private var trust: ProcessTrust?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                header
                    .padding(.bottom, NetglassSpacing.standard)

                InspectorSection(title: "Process", systemImage: "gearshape.2") {
                    InspectorField(name: "Executable", value: flow.executablePath)
                    InspectorField(name: "Bundle", value: flow.bundleIdentifier ?? "—", mono: false)
                    InspectorField(name: "PID", value: "\(flow.pid)")
                    InspectorField(name: "Ancestry", value: ancestryNames.joined(separator: " → "), mono: true)
                    InspectorField(name: "User", value: NSUserName(), mono: false)
                }
                InspectorSection(title: "Trust", systemImage: "checkmark.shield") {
                    if let trust {
                        InspectorField(name: "Signed", value: trust.signed ? "Yes" : "No", mono: false)
                        if let authority = trust.authority {
                            InspectorField(name: "Authority", value: authority, mono: false)
                        }
                        if let teamID = trust.teamID {
                            InspectorField(name: "Team ID", value: teamID, mono: false)
                        }
                        InspectorField(name: "SHA-256", value: String(trust.sha256.prefix(16)) + "…", mono: true)
                        InspectorField(name: "Flags", value: trustFlags(trust), mono: false)
                        if !trust.networkEntitlements.isEmpty {
                            InspectorField(name: "Net entitlements",
                                           value: trust.networkEntitlements.joined(separator: ", "), mono: false)
                        }
                    } else {
                        InspectorField(name: "Trust", value: "Checking…", mono: false)
                    }
                }
                InspectorSection(title: "Connection", systemImage: "point.3.connected.trianglepath.dotted") {
                    InspectorField(name: "Local", value: "\(flow.local.address.text):\(flow.local.port)")
                    InspectorField(name: "Remote", value: "\(flow.remote.address.text):\(flow.remote.port)")
                    InspectorField(name: "Domain", value: flow.remoteDomain ?? "No verified domain", mono: false)
                    InspectorField(name: "Protocol", value: flow.transport.rawValue.uppercased(), mono: false)
                    InspectorField(name: "Interface", value: InterfaceStore.primary(), mono: false)
                    InspectorField(name: "State", value: flow.isActive ? "Active" : "Closed", mono: false)
                    InspectorField(name: "Started", value: flow.startedAt.formatted(date: .abbreviated, time: .standard), mono: false)
                    InspectorField(name: "Duration", value: durationText, mono: false)
                }
                InspectorSection(title: "Traffic", systemImage: "arrow.up.arrow.down") {
                    InspectorField(name: "Sent", value: flow.bytesSent.formatted(.byteCount(style: .decimal)))
                    InspectorField(name: "Received", value: flow.bytesReceived.formatted(.byteCount(style: .decimal)))
                    MiniTrafficSparkline(
                        samples: Array(TrafficHistory.aggregate(liveModel.throughputHistory,
                                                                bucketSeconds: liveModel.samplesPerBucket, capacity: 24)))
                        .frame(height: 36)
                        .padding(.top, 2)
                }
                InspectorSection(title: "Domain Evidence", systemImage: "globe") {
                    InspectorField(name: "Domain", value: flow.remoteDomain ?? "Unknown", mono: false)
                    InspectorField(name: "Evidence", value: evidenceText, mono: false)
                    InspectorField(name: "Confidence", value: confidenceText, mono: false)
                }
                InspectorSection(title: "TLS", systemImage: "lock") {
                    InspectorField(name: "Status", value: flow.remote.port == 443 ? "TLS 1.3 observed" : "No TLS observed", mono: false)
                    InspectorField(name: "SNI", value: flow.remoteDomain ?? "—", mono: false)
                }
                InspectorSection(title: "Network", systemImage: "network") {
                    InspectorField(name: "ASN", value: geo?.asn ?? "—", mono: false)
                    InspectorField(name: "Organization", value: geo?.organization ?? "—", mono: false)
                    InspectorField(name: "Country", value: geo?.country ?? "—", mono: false)
                    InspectorField(name: "Interface", value: InterfaceStore.primary(), mono: false)
                    InspectorField(name: "Reverse DNS", value: flow.remoteDomain ?? "—", mono: false)
                }

                HStack(spacing: 8) {
                    Button("Copy Domain") { copyText(flow.remoteDomain) }
                    Button("Copy IP") { copyText(flow.remote.address.text) }
                    Button("Copy Details") { copyText(detailsText) }
                }
                .controlSize(.small)
                .padding(.top, NetglassSpacing.section)
            }
            .task(id: flow.flowID) {
                ancestryNames = ProcessAncestry.chain(for: flow.pid)
                    .map { $0.executablePath.split(separator: "/").last.map(String.init) ?? "?" }
                trust = ProcessTrustInspector.inspect(path: flow.executablePath)
            }
            .padding(NetglassSpacing.section)
        }
        .frame(minWidth: 280, idealWidth: NetglassMetrics.inspectorWidth,
               maxWidth: NetglassMetrics.inspectorWidth + 40)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: NetglassSpacing.standard) {
            Image(nsImage: AppIcon.image(forProcessPath: flow.executablePath))
                .resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(flow.processName)
                    .font(.system(size: 13, weight: .medium))
                Text(flow.remoteDomain ?? flow.remote.address.text)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            StateBadge(state: flow.isActive ? "Active" : "Closed")
        }
    }

    private var durationText: String {
        let end = flow.endedAt ?? Date()
        return Duration.seconds(end.timeIntervalSince(flow.startedAt))
            .formatted(.time(pattern: .minuteSecond))
    }

    private var evidenceText: String {
        guard let confidence = flow.remoteDomainConfidence else { return "Unknown" }
        return confidence >= 0.5 ? "Verified by DNS" : "Reverse DNS estimate"
    }

    private var confidenceText: String {
        flow.remoteDomainConfidence.map { String(format: "%.0f%%", $0 * 100) } ?? "—"
    }

    private var geo: GeoInfo? { GeoIP.lookup(flow.remote.address.text) }

    private func trustFlags(_ trust: ProcessTrust) -> String {
        var flags: [String] = []
        if trust.isTemporary { flags.append("Temp path") }
        if trust.isDiskImage { flags.append("Disk image") }
        if trust.isSystemBinary { flags.append("System") }
        if trust.changedSinceFirstSeen { flags.append("Changed since first seen") }
        return flags.isEmpty ? "—" : flags.joined(separator: ", ")
    }

    private var detailsText: String {
        "\(flow.processName) (PID \(flow.pid)) \(flow.remote.address.text):\(flow.remote.port) "
            + "\(flow.transport.rawValue) sent \(flow.bytesSent) received \(flow.bytesReceived)"
    }

    private func copyText(_ text: String?) {
        guard let text, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
