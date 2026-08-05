import AppKit
import SwiftUI
import FlowModel
import Persistence

struct HistoryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var flows: [StoredFlow] = []
    @State private var selection: StoredFlow.ID?
    @State private var lastError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search app, IP or port", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                    .onSubmit { reload() }
                Button("Search", action: reload)
                Spacer()
                Button("Export…", action: export)
                    .disabled(flows.isEmpty)
                Text("\(flows.count) flows")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)

            Table(flows, selection: $selection) {
                TableColumn("Process") { flow in
                    Text(flow.processPath.split(separator: "/").last.map(String.init) ?? "?")
                        .font(.system(.body, design: .monospaced))
                }
                TableColumn("Remote") { flow in
                    Text("\(flow.remoteAddress.text):\(flow.remotePort)")
                        .font(.system(.body, design: .monospaced))
                }
                TableColumn("Transport") { flow in
                    Text(flow.transport.rawValue)
                }
                TableColumn("Bytes ↓") { flow in
                    Text(flow.bytesReceived.formatted(.byteCount(style: .decimal)))
                }
                TableColumn("Bytes ↑") { flow in
                    Text(flow.bytesSent.formatted(.byteCount(style: .decimal)))
                }
                TableColumn("Started") { flow in
                    Text(flow.startedAt.formatted(date: .abbreviated, time: .shortened))
                }
                TableColumn("Duration") { flow in
                    Text(flow.endedAt.map {
                        Duration.seconds($0.timeIntervalSince(flow.startedAt))
                            .formatted(.time(pattern: .minuteSecond))
                    } ?? "—")
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
            if let flow = flows.first(where: { $0.flowID == selection }) {
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
        do { flows = try HistoryQuery.search(database: db, text: searchText) }
        catch { lastError = "search failed: \(error)" }
    }

    private func export() {
        guard let db = appState.database else { return }
        do {
            let all = try HistoryQuery.search(database: db, text: "")
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "netglass-history.json"
            panel.allowedContentTypes = [.json]
            if panel.runModal() == .OK, let url = panel.url {
                try Exporter.exportJSON(all, to: url)
            }
        } catch { lastError = "export failed: \(error)" }
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
