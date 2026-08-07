import SwiftUI
import FlowModel

/// A removable filter token (application, protocol, port, evidence, …).
struct FilterToken: Identifiable, Hashable {
    let id = UUID()
    let label: String

    func matches(_ flow: LiveFlow) -> Bool {
        let lower = label.lowercased()
        var negated = false
        var field: String?
        var value: String?
        if let range = lower.range(of: " is not ") {
            negated = true
            field = String(lower[..<range.lowerBound])
            value = String(lower[range.upperBound...])
        } else if let range = lower.range(of: " is ") {
            field = String(lower[..<range.lowerBound])
            value = String(lower[range.upperBound...])
        }
        guard let field, let value else { return true }
        var matched = false
        switch field {
        case "application":
            matched = flow.processName.lowercased().contains(value)
        case "domain":
            matched = (flow.remoteDomain ?? "").lowercased().contains(value)
        case "port":
            matched = String(flow.remote.port) == value
        case "protocol":
            matched = flow.transport.rawValue.lowercased() == value
        case "evidence":
            let evidence = (flow.remoteDomainConfidence ?? 0) >= 0.5 ? "verified" : "unknown"
            matched = evidence == value
        default:
            return true
        }
        return negated ? !matched : matched
    }
}

/// Live Connections: high-density sortable table with filters, density modes,
/// pause-aware "new rows" banner, and selection sync to the right inspector.
struct LiveConnectionsView: View {
    @EnvironmentObject private var liveModel: LiveConnectionsModel
    @EnvironmentObject private var monitoring: MonitoringViewModel
    @EnvironmentObject private var appVM: AppViewModel
    @Binding var selectedFlow: LiveFlow?

    @State private var tokens: [FilterToken] = []
    @State private var pausedFlowCount = 0
    @State private var advancedFiltersPresented = false

    private var filteredFlows: [LiveFlow] {
        liveModel.visibleFlows.filter { flow in
            tokens.allSatisfy { $0.matches(flow) }
        }
        .sorted { $0.bytesReceived > $1.bytesReceived }
    }

    private var newRowsWhilePaused: Int {
        guard monitoring.isPaused else { return 0 }
        return max(0, liveModel.visibleFlows.count - pausedFlowCount)
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar

            if newRowsWhilePaused > 0 {
                Button {
                    pausedFlowCount = liveModel.visibleFlows.count
                    monitoring.resume()
                    monitoring.pause()
                } label: {
                    Label("\(newRowsWhilePaused) new connections available",
                          systemImage: "arrow.down.circle")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.small)
                .padding(.vertical, 4)
            }

            connectionTable
        }
        .onChange(of: monitoring.isPaused) { _, paused in
            pausedFlowCount = paused ? liveModel.visibleFlows.count : 0
        }
        .onAppear { pausedFlowCount = 0 }
        .sheet(item: $presentedFlow) { flow in
            ConnectionInspectorSheet(flow: flow)
        }
    }
    private var connectionTable: some View {
        Table(filteredFlows) {
            if appVM.enabledColumns.contains("Application") {
                TableColumn("Application") { flow in
                    AppCell(flow: flow, padding: appVM.rowPadding)
                }
                .width(min: 140, ideal: 180)
            }
            TableColumn("Remote") { flow in
                Text("\(flow.remote.address.text):\(flow.remote.port)")
            }
            TableColumn("Local") { flow in
                Text("\(flow.local.address.text):\(flow.local.port)")
            }
            TableColumn("Protocol") { flow in
                Text(flow.transport.rawValue.uppercased())
            }
            TableColumn("Direction") { flow in
                Text("→")
            }
            TableColumn("Sent") { flow in
                MonoCell(text: Self.bytes(flow.bytesSent), width: 76)
            }
            .width(min: 76, ideal: 86, max: 120)
            TableColumn("Received") { flow in
                MonoCell(text: Self.bytes(flow.bytesReceived), width: 76)
            }
            .width(min: 76, ideal: 86, max: 120)
            TableColumn("State") { flow in
                StateBadge(state: flow.isActive ? "Active" : "Closed")
            }
            TableColumn("PID") { flow in
                MonoCell(text: "\(flow.pid)", width: 48, alignment: .trailing)
            }
        }

            .contextMenu(forSelectionType: LiveFlow.ID.self) { ids in
                Button("Copy Row") {
                    if let id = ids.first,
                       let flow = liveModel.flows.first(where: { $0.flowID == id }) {
                        copyRow(flow)
                    }
                }
                Button("Copy IP Address") {
                    if let id = ids.first,
                       let flow = liveModel.flows.first(where: { $0.flowID == id }) {
                        copyText(flow.remote.address.text)
                    }
                }
                Button("Copy Domain") {
                    if let id = ids.first,
                       let flow = liveModel.flows.first(where: { $0.flowID == id }) {
                        copyText(flow.remoteDomain)
                    }
                }
                Divider()
                Button("Add Filter: Application") {
                    if let id = ids.first,
                       let flow = liveModel.flows.first(where: { $0.flowID == id }) {
                        addToken("Application is \(flow.processName)")
                    }
                }
                Button("Add Filter: Protocol") {
                    if let id = ids.first,
                       let flow = liveModel.flows.first(where: { $0.flowID == id }) {
                        addToken("Protocol is \(flow.transport.rawValue.uppercased())")
                    }
                }
            } primaryAction: { ids in
                selectFirst(ids)
            }
    }

    @State private var presentedFlow: LiveFlow?

    private func selectFirst(_ ids: Set<LiveFlow.ID>) {
        guard let id = ids.first else { return }
        presentedFlow = liveModel.flows.first { $0.flowID == id }
    }

    private static func bytes(_ value: UInt64) -> String {
        value.formatted(.byteCount(style: .decimal))
    }

    private func evidenceText(_ flow: LiveFlow) -> String {
        guard let confidence = flow.remoteDomainConfidence else { return "Unknown" }
        return confidence >= 0.5 ? "Verified by DNS" : "Reverse DNS estimate"
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(tokens) { token in
                        HStack(spacing: 4) {
                            Text(token.label).font(.system(size: 10, design: .monospaced))
                            Button {
                                tokens.removeAll { $0.id == token.id }
                            } label: {
                                Image(systemName: "xmark").font(.system(size: 8))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.quaternary.opacity(0.7), in: Capsule())
                    }
                    if tokens.isEmpty {
                        Text("No filters").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
            }
            Menu {
                Button("Application is Telegram") { addToken("Application is Telegram") }
                Button("Application is Safari") { addToken("Application is Safari") }
                Divider()
                Button("Protocol is TCP") { addToken("Protocol is TCP") }
                Button("Protocol is UDP") { addToken("Protocol is UDP") }
                Divider()
                Button("Remote Port is 443") { addToken("Remote Port is 443") }
                Button("Remote Port is 53") { addToken("Remote Port is 53") }
                Divider()
                Button("Domain Evidence is Unknown") { addToken("Domain Evidence is Unknown") }
                Button("Domain Evidence is Verified") { addToken("Domain Evidence is Verified") }
                Divider()
                Button("Advanced…") { advancedFiltersPresented = true }
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
            }
            .controlSize(.small)
            .sheet(isPresented: $advancedFiltersPresented) {
                AdvancedFiltersView { token in
                    addToken(token)
                    advancedFiltersPresented = false
                }
            }
            if !tokens.isEmpty {
                Button("Clear") { tokens.removeAll() }
                    .controlSize(.small)
                    .buttonStyle(.link)
            }
            Spacer()
            Text("\(filteredFlows.count) shown")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private func addToken(_ label: String) {
        guard !tokens.contains(where: { $0.label == label }) else { return }
        tokens.append(FilterToken(label: label))
    }

    private func copyRow(_ flow: LiveFlow) {
        let row = "\(flow.processName)\t\(flow.remote.address.text):\(flow.remote.port)\t"
            + "\(flow.transport.rawValue)\t\(flow.bytesSent)\t\(flow.bytesReceived)"
        copyText(row)
    }

    private func copyText(_ text: String?) {
        guard let text, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct ConnectionInspectorSheet: View {
    let flow: LiveFlow
    var body: some View {
        ConnectionInspectorView(flow: flow)
            .frame(minWidth: 420, minHeight: 480)
            .padding(8)
    }
}

private struct AppCell: View {
    let flow: LiveFlow
    let padding: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: AppIcon.image(forProcessPath: flow.executablePath))
                .resizable().frame(width: 16, height: 16)
            Text(flow.processName).font(.system(size: 13))
        }
        .padding(.vertical, padding)
    }
}

/// Structured filter builder: field/operator/value rows → filter tokens.
struct AdvancedFiltersView: View {
    let onApply: (String) -> Void

    private enum Field: String, CaseIterable, Identifiable {
        case application = "Application"
        case domain = "Domain"
        case port = "Port"
        case protocolName = "Protocol"
        case evidence = "Domain Evidence"
        var id: String { rawValue }
    }

    private enum Op: String, CaseIterable, Identifiable {
        case isExactly = "is"
        case isNot = "is not"
        var id: String { rawValue }
    }

    private struct Row: Identifiable {
        let id = UUID()
        var field: Field = .application
        var op: Op = .isExactly
        var value = ""
    }

    @State private var rows: [Row] = [Row()]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Advanced Filters").font(.system(size: 14, weight: .semibold))
            ForEach($rows) { $row in
                HStack(spacing: 8) {
                    Picker("", selection: $row.field) {
                        ForEach(Field.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                    Picker("", selection: $row.op) {
                        ForEach(Op.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 90)
                    TextField("Value", text: $row.value)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                    Button {
                        rows.removeAll { $0.id == row.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Add Row") { rows.append(Row()) }
                    .controlSize(.small)
                Spacer()
                Button("Cancel") { onApply("") }
                    .controlSize(.small)
                Button("Apply") {
                    for row in rows where !row.value.isEmpty {
                        onApply("\\(row.field.rawValue) \\(row.op.rawValue) \\(row.value)")
                    }
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(rows.allSatisfy { $0.value.isEmpty })
            }
        }
        .padding(16)
        .frame(width: 540)
    }
}
