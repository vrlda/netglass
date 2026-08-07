import AppKit
import SwiftUI
import FlowModel
import Persistence

/// History tab: flows grouped by app (or domain), with search and export.
struct HistoryTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var groups: [HistoryGroup] = []
    @State private var selection: StoredFlow.ID?
    @State private var lastError: String?
    @State private var groupByDomain = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search app, IP or port", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                    .onSubmit { reload() }
                Button("Search", action: reload)
                Picker("Group by", selection: $groupByDomain) {
                    Text("App").tag(false)
                    Text("Domain").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 150)
                .onChange(of: groupByDomain) { _, _ in reload() }
                Spacer()
                Button("Export…", action: export)
                    .disabled(groups.isEmpty)
                Text("\(groups.reduce(0) { $0 + $1.flows.count }) flows")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)

            List(selection: $selection) {
                ForEach(groups, id: \.title) { group in
                    Section {
                        ForEach(group.flows, id: \.flowID) { flow in
                            FlowRow(flow: flow)
                                .tag(flow.flowID)
                        }
                    } header: {
                        HistoryGroupHeader(group: group)
                    }
                }
            }
            .frame(minHeight: 300)

            if let lastError {
                Text(lastError).font(.caption).foregroundStyle(.red).padding(4)
            }
        }
        .onAppear(perform: reload)
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty { reload() }
        }
        .sheet(isPresented: detailPresented) {
            if let flow = groups.flatMap(\.flows).first(where: { $0.flowID == selection }) {
                StoredFlowDetailView(flow: flow)
            }
        }
    }

    /// The sheet is driven off the row selection so any dismissal (Escape,
    /// Cmd-W, Done) clears the selection — re-clicking the same row after a
    /// dismiss sets selection again and reopens the detail.
    private var detailPresented: Binding<Bool> {
        Binding(
            get: { selection != nil },
            set: { if !$0 { selection = nil } }
        )
    }

    private func reload() {
        guard let db = appState.database else {
            lastError = appState.bootstrapError ?? "database unavailable"
            return
        }
        do {
            groups = groupByDomain
                ? try HistoryQuery.groupedByDomain(database: db, text: searchText)
                : try HistoryQuery.grouped(database: db, text: searchText)
        } catch { lastError = "search failed: \(error)" }
    }

    private func export() {
        guard let db = appState.database else { return }
        do {
            let all = try HistoryQuery.search(database: db, text: searchText, limit: Int.max)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "netglass-history.json"
            panel.allowedContentTypes = [.json, .commaSeparatedText]
            panel.canSelectHiddenExtension = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            if url.pathExtension.lowercased() == "csv" {
                try Exporter.exportCSV(all, to: url)
            } else {
                try Exporter.exportJSON(all, to: url)
            }
        } catch { lastError = "export failed: \(error)" }
    }
}

/// Section header: app icon (or globe for domain groups), name, flow count,
/// and aggregate bytes.
private struct HistoryGroupHeader: View {
    let group: HistoryGroup

    var body: some View {
        HStack(spacing: 6) {
            if let processPath = group.processPath {
                Image(nsImage: AppIcon.image(forProcessPath: processPath))
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Text(group.title).font(.system(size: 13, weight: .medium))
            Text("\(group.flows.count) flows")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text("↓ \(group.totalBytesReceived.formatted(.byteCount(style: .decimal)))"
                + "  ↑ \(group.totalBytesSent.formatted(.byteCount(style: .decimal)))")
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}

/// One flow, laid out in table-like fixed columns.
private struct FlowRow: View {
    let flow: StoredFlow

    var body: some View {
        HStack(spacing: 10) {
            Text("\(flow.remoteAddress.text):\(flow.remotePort)")
                .font(.system(.caption, design: .monospaced))
                .frame(width: 150, alignment: .leading)
            Text(flow.domain.isEmpty ? "—" : flow.domain)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(flow.domainConfidence >= 0.5 ? Color.primary : Color.secondary)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)
            Text(flow.transport.rawValue)
                .font(.caption)
                .frame(width: 40, alignment: .leading)
            Text(flow.bytesReceived.formatted(.byteCount(style: .decimal)))
                .font(.caption).monospacedDigit()
                .frame(width: 76, alignment: .trailing)
            Text(flow.bytesSent.formatted(.byteCount(style: .decimal)))
                .font(.caption).monospacedDigit()
                .frame(width: 76, alignment: .trailing)
            Text(flow.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .trailing)
            Spacer(minLength: 0)
        }
    }
}

private struct StoredFlowDetailView: View {
    let flow: StoredFlow
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(flow.processPath).font(.title3).bold()
                .font(.system(.body, design: .monospaced))
            LabeledContent("Bundle", value: flow.bundleIdentifier ?? "—")
            LabeledContent("Transport", value: flow.transport.rawValue)
            LabeledContent("Local", value: "\(flow.localAddress.text):\(flow.localPort)")
            LabeledContent("Remote", value: "\(flow.remoteAddress.text):\(flow.remotePort)")
            LabeledContent("Bytes sent", value: flow.bytesSent.formatted(.byteCount(style: .decimal)))
            LabeledContent("Bytes received", value: flow.bytesReceived.formatted(.byteCount(style: .decimal)))
            LabeledContent("Started", value: flow.startedAt.formatted())
            LabeledContent("Ended", value: flow.endedAt?.formatted() ?? "—")
            Spacer()
        }
        .padding(16)
        .frame(minWidth: 460, minHeight: 300)
    }
}
